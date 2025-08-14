// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../01-core/AccessControl.sol";
import "../03-pool/LaxcePool.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title TWAPOracle
 * @dev Time-Weighted Average Price Oracle for LAXCE DEX
 * @dev Provides TWAP calculations based on pool observations
 */
contract TWAPOracle is Pausable, LaxceAccessControl {
    using SafeCast for uint256;
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant MAX_PERIOD = 86400; // 24 hours
    uint256 public constant MIN_PERIOD = 60; // 1 minute
    uint256 public constant MAX_CARDINALITY = 65535;
    uint256 public constant MIN_CARDINALITY = 2;
    uint256 public constant PRECISION = 1e18;

    // =========== STRUCTS ===========
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    struct TWAPData {
        address pool;
        uint32 period;
        uint16 cardinality;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 lastUpdate;
        bool isValid;
    }

    struct PriceInfo {
        uint256 price0;
        uint256 price1;
        uint256 timestamp;
        uint256 period;
        bool isValid;
    }

    // =========== STATE VARIABLES ===========
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    // Pool => TWAP data
    mapping(address => TWAPData) public twapData;
    
    // Pool => Observations array
    mapping(address => Observation[]) public observations;
    
    // Pool => observation index
    mapping(address => uint16) public observationIndex;
    
    // Pool => is monitoring enabled
    mapping(address => bool) public isMonitoring;
    
    // Supported pools
    address[] public supportedPools;
    mapping(address => bool) public isSupportedPool;
    
    // Configuration
    uint32 public defaultPeriod = 3600; // 1 hour
    uint16 public defaultCardinality = 100;
    uint256 public updateInterval = 300; // 5 minutes
    uint256 public maxPriceDeviation = 1000; // 10%
    
    // Emergency settings
    bool public emergencyMode = false;
    mapping(address => uint256) public lastEmergencyUpdate;

    // =========== EVENTS ===========
    event TWAPUpdated(
        address indexed pool,
        uint160 sqrtPriceX96,
        int24 tick,
        uint256 timestamp
    );
    
    event ObservationAdded(
        address indexed pool,
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint16 index
    );
    
    event PoolAdded(address indexed pool, uint32 period, uint16 cardinality);
    event PoolRemoved(address indexed pool);
    event ConfigurationUpdated(uint32 period, uint16 cardinality, uint256 updateInterval);
    event EmergencyModeToggled(bool enabled);
    event MaxPriceDeviationUpdated(uint256 oldDeviation, uint256 newDeviation);

    // =========== ERRORS ===========
    error TWAPOracle__InvalidPool();
    error TWAPOracle__InvalidPeriod();
    error TWAPOracle__InvalidCardinality();
    error TWAPOracle__InsufficientObservations();
    error TWAPOracle__StalePrice();
    error TWAPOracle__PriceDeviationTooHigh();
    error TWAPOracle__NotInitialized();
    error TWAPOracle__AlreadySupported();
    error TWAPOracle__UpdateTooSoon();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier validPool(address pool) {
        if (!isSupportedPool[pool]) revert TWAPOracle__InvalidPool();
        _;
    }

    modifier updateAllowed(address pool) {
        if (block.timestamp < twapData[pool].lastUpdate + updateInterval) {
            revert TWAPOracle__UpdateTooSoon();
        }
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor() {
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // =========== POOL MANAGEMENT ===========

    /**
     * @dev Add a pool for TWAP monitoring
     * @param pool Pool address to monitor
     * @param period TWAP calculation period
     * @param cardinality Number of observations to store
     */
    function addPool(
        address pool,
        uint32 period,
        uint16 cardinality
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        if (pool == address(0)) revert TWAPOracle__InvalidPool();
        if (isSupportedPool[pool]) revert TWAPOracle__AlreadySupported();
        if (period < MIN_PERIOD || period > MAX_PERIOD) revert TWAPOracle__InvalidPeriod();
        if (cardinality < MIN_CARDINALITY || cardinality > MAX_CARDINALITY) {
            revert TWAPOracle__InvalidCardinality();
        }

        // Initialize pool data
        twapData[pool] = TWAPData({
            pool: pool,
            period: period,
            cardinality: cardinality,
            sqrtPriceX96: 0,
            tick: 0,
            lastUpdate: 0,
            isValid: false
        });

        // Initialize observations array
        observations[pool] = new Observation[](cardinality);
        observationIndex[pool] = 0;
        
        // Add to supported pools
        supportedPools.push(pool);
        isSupportedPool[pool] = true;
        isMonitoring[pool] = true;

        // Initialize with current pool state
        _initializeObservations(pool);

        emit PoolAdded(pool, period, cardinality);
    }

    /**
     * @dev Remove a pool from TWAP monitoring
     * @param pool Pool address to remove
     */
    function removePool(address pool) external nonReentrant onlyRole(ADMIN_ROLE) validPool(pool) {
        // Remove from supported pools array
        for (uint256 i = 0; i < supportedPools.length; i++) {
            if (supportedPools[i] == pool) {
                supportedPools[i] = supportedPools[supportedPools.length - 1];
                supportedPools.pop();
                break;
            }
        }

        // Reset mappings
        delete twapData[pool];
        delete observations[pool];
        delete observationIndex[pool];
        delete isMonitoring[pool];
        delete isSupportedPool[pool];

        emit PoolRemoved(pool);
    }

    // =========== OBSERVATION MANAGEMENT ===========

    /**
     * @dev Update TWAP for a specific pool
     * @param pool Pool address to update
     */
    function updateTWAP(address pool) 
        external 
        nonReentrant 
        validPool(pool) 
        updateAllowed(pool) 
        whenNotPaused 
    {
        _updateObservation(pool);
    }

    /**
     * @dev Batch update TWAP for multiple pools
     * @param pools Array of pool addresses to update
     */
    function batchUpdateTWAP(address[] calldata pools) 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
    {
        for (uint256 i = 0; i < pools.length; i++) {
            if (isSupportedPool[pools[i]] && 
                block.timestamp >= twapData[pools[i]].lastUpdate + updateInterval) {
                _updateObservation(pools[i]);
            }
        }
    }

    /**
     * @dev Force update all supported pools (emergency)
     */
    function emergencyUpdateAll() external nonReentrant onlyRole(EMERGENCY_ROLE) {
        emergencyMode = true;
        
        for (uint256 i = 0; i < supportedPools.length; i++) {
            address pool = supportedPools[i];
            if (isMonitoring[pool]) {
                _updateObservation(pool);
                lastEmergencyUpdate[pool] = block.timestamp;
            }
        }
        
        emit EmergencyModeToggled(true);
    }

    // =========== TWAP CALCULATIONS ===========

    /**
     * @dev Get TWAP price for a pool
     * @param pool Pool address
     * @param period Time period for TWAP calculation
     * @return price0 Token0 price in terms of token1
     * @return price1 Token1 price in terms of token0
     */
    function getTWAPPrice(address pool, uint32 period) 
        external 
        view 
        validPool(pool) 
        returns (uint256 price0, uint256 price1) 
    {
        TWAPData memory data = twapData[pool];
        if (!data.isValid) revert TWAPOracle__NotInitialized();

        // Get TWAP tick
        int24 twapTick = _getTWAPTick(pool, period);
        
        // Convert tick to price
        (price0, price1) = _tickToPrice(twapTick);
    }

    /**
     * @dev Get current spot price (latest observation)
     * @param pool Pool address
     * @return price0 Token0 price
     * @return price1 Token1 price
     */
    function getSpotPrice(address pool) 
        external 
        view 
        validPool(pool) 
        returns (uint256 price0, uint256 price1) 
    {
        TWAPData memory data = twapData[pool];
        if (!data.isValid) revert TWAPOracle__NotInitialized();

        return _tickToPrice(data.tick);
    }

    /**
     * @dev Get comprehensive price information
     * @param pool Pool address
     * @return info PriceInfo struct with all price data
     */
    function getPriceInfo(address pool) 
        external 
        view 
        validPool(pool) 
        returns (PriceInfo memory info) 
    {
        TWAPData memory data = twapData[pool];
        if (!data.isValid) revert TWAPOracle__NotInitialized();

        (uint256 price0, uint256 price1) = _tickToPrice(data.tick);
        
        info = PriceInfo({
            price0: price0,
            price1: price1,
            timestamp: data.lastUpdate,
            period: data.period,
            isValid: data.isValid
        });
    }

    /**
     * @dev Check if price is within acceptable deviation
     * @param pool Pool address
     * @param referencePrice Reference price to compare against
     * @return isValid True if within acceptable range
     */
    function isPriceValid(address pool, uint256 referencePrice) 
        external 
        view 
        validPool(pool) 
        returns (bool isValid) 
    {
        TWAPData memory data = twapData[pool];
        if (!data.isValid) return false;

        (uint256 currentPrice, ) = _tickToPrice(data.tick);
        
        uint256 deviation = currentPrice > referencePrice 
            ? (currentPrice - referencePrice) * 10000 / referencePrice
            : (referencePrice - currentPrice) * 10000 / referencePrice;
            
        return deviation <= maxPriceDeviation;
    }

    // =========== INTERNAL FUNCTIONS ===========

    /**
     * @dev Initialize observations for a newly added pool
     */
    function _initializeObservations(address pool) internal {
        try LaxcePool(pool).slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            uint32 blockTimestamp = uint32(block.timestamp);
            
            // Initialize first observation
            observations[pool][0] = Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                initialized: true
            });

            // Update TWAP data
            twapData[pool].sqrtPriceX96 = sqrtPriceX96;
            twapData[pool].tick = tick;
            twapData[pool].lastUpdate = block.timestamp;
            twapData[pool].isValid = true;

            emit ObservationAdded(pool, blockTimestamp, 0, 0);
            emit TWAPUpdated(pool, sqrtPriceX96, tick, block.timestamp);

        } catch {
            revert TWAPOracle__InvalidPool();
        }
    }

    /**
     * @dev Update observation for a pool
     */
    function _updateObservation(address pool) internal {
        try LaxcePool(pool).slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            uint32 blockTimestamp = uint32(block.timestamp);
            uint16 index = observationIndex[pool];
            uint16 cardinality = twapData[pool].cardinality;
            
            // Get previous observation
            Observation memory last = observations[pool][index];
            
            // Calculate cumulative values
            uint32 delta = blockTimestamp - last.blockTimestamp;
            int56 tickCumulative = last.tickCumulative + int56(tick) * int56(uint56(delta));
            
            // Calculate seconds per liquidity cumulative
            uint128 liquidity = LaxcePool(pool).liquidity();
            uint160 secondsPerLiquidityCumulativeX128 = last.secondsPerLiquidityCumulativeX128;
            if (liquidity > 0) {
                secondsPerLiquidityCumulativeX128 += 
                    (uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1);
            }

            // Move to next index
            index = (index + 1) % cardinality;
            observationIndex[pool] = index;

            // Store new observation
            observations[pool][index] = Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: tickCumulative,
                secondsPerLiquidityCumulativeX128: secondsPerLiquidityCumulativeX128,
                initialized: true
            });

            // Update TWAP data
            twapData[pool].sqrtPriceX96 = sqrtPriceX96;
            twapData[pool].tick = tick;
            twapData[pool].lastUpdate = block.timestamp;

            emit ObservationAdded(pool, blockTimestamp, tickCumulative, index);
            emit TWAPUpdated(pool, sqrtPriceX96, tick, block.timestamp);

        } catch {
            // Handle failure gracefully in emergency mode
            if (emergencyMode) {
                twapData[pool].isValid = false;
            }
        }
    }

    /**
     * @dev Get TWAP tick for a specific period
     */
    function _getTWAPTick(address pool, uint32 period) internal view returns (int24) {
        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 targetTimestamp = blockTimestamp - period;
        
        uint16 index = observationIndex[pool];
        uint16 cardinality = twapData[pool].cardinality;
        
        // Find observations around target timestamp
        Observation memory beforeOrAt;
        Observation memory atOrAfter;
        bool found = false;
        
        // Search for appropriate observations
        for (uint256 i = 0; i < cardinality; i++) {
            uint16 searchIndex = (index + cardinality - uint16(i)) % cardinality;
            Observation memory obs = observations[pool][searchIndex];
            
            if (!obs.initialized) continue;
            
            if (obs.blockTimestamp <= targetTimestamp) {
                beforeOrAt = obs;
                found = true;
                break;
            }
            atOrAfter = obs;
        }
        
        if (!found) revert TWAPOracle__InsufficientObservations();
        
        // Calculate TWAP tick
        if (beforeOrAt.blockTimestamp == targetTimestamp) {
            return int24(beforeOrAt.tickCumulative / int56(uint56(period)));
        }
        
        // Interpolate between observations
        uint32 timeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
        if (timeDelta == 0) {
            return int24(beforeOrAt.tickCumulative / int56(uint56(period)));
        }
        
        int56 tickCumulativeDelta = atOrAfter.tickCumulative - beforeOrAt.tickCumulative;
        int56 interpolated = beforeOrAt.tickCumulative + 
            (tickCumulativeDelta * int56(uint56(targetTimestamp - beforeOrAt.blockTimestamp))) / 
            int56(uint56(timeDelta));
            
        return int24(interpolated / int56(uint56(period)));
    }

    /**
     * @dev Convert tick to price
     */
    function _tickToPrice(int24 tick) internal pure returns (uint256 price0, uint256 price1) {
        // Simplified price calculation - in production would use TickMath library
        if (tick >= 0) {
            uint256 ratio = uint256(uint24(tick)) * PRECISION / 100;
            price0 = PRECISION + ratio;
            price1 = PRECISION * PRECISION / price0;
        } else {
            uint256 ratio = uint256(uint24(-tick)) * PRECISION / 100;
            price1 = PRECISION + ratio;
            price0 = PRECISION * PRECISION / price1;
        }
    }

    // =========== ADMIN FUNCTIONS ===========

    /**
     * @dev Set default configuration
     */
    function setDefaultConfiguration(
        uint32 _period,
        uint16 _cardinality,
        uint256 _updateInterval
    ) external onlyRole(ADMIN_ROLE) {
        if (_period < MIN_PERIOD || _period > MAX_PERIOD) revert TWAPOracle__InvalidPeriod();
        if (_cardinality < MIN_CARDINALITY || _cardinality > MAX_CARDINALITY) {
            revert TWAPOracle__InvalidCardinality();
        }

        defaultPeriod = _period;
        defaultCardinality = _cardinality;
        updateInterval = _updateInterval;

        emit ConfigurationUpdated(_period, _cardinality, _updateInterval);
    }

    /**
     * @dev Set maximum price deviation tolerance
     */
    function setMaxPriceDeviation(uint256 _maxDeviation) external onlyRole(ADMIN_ROLE) {
        uint256 oldDeviation = maxPriceDeviation;
        maxPriceDeviation = _maxDeviation;
        
        emit MaxPriceDeviationUpdated(oldDeviation, _maxDeviation);
    }

    /**
     * @dev Toggle monitoring for a pool
     */
    function setPoolMonitoring(address pool, bool enabled) 
        external 
        onlyRole(OPERATOR_ROLE) 
        validPool(pool) 
    {
        isMonitoring[pool] = enabled;
    }

    /**
     * @dev Exit emergency mode
     */
    function exitEmergencyMode() external onlyRole(ADMIN_ROLE) {
        emergencyMode = false;
        emit EmergencyModeToggled(false);
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =========== VIEW FUNCTIONS ===========

    /**
     * @dev Get all supported pools
     */
    function getSupportedPools() external view returns (address[] memory) {
        return supportedPools;
    }

    /**
     * @dev Get supported pools count
     */
    function getSupportedPoolsCount() external view returns (uint256) {
        return supportedPools.length;
    }

    /**
     * @dev Get observation at specific index for a pool
     */
    function getObservation(address pool, uint16 index) 
        external 
        view 
        validPool(pool) 
        returns (Observation memory) 
    {
        return observations[pool][index];
    }

    /**
     * @dev Get latest observations for a pool
     */
    function getLatestObservations(address pool, uint256 count) 
        external 
        view 
        validPool(pool) 
        returns (Observation[] memory latestObs) 
    {
        uint16 cardinality = twapData[pool].cardinality;
        uint16 index = observationIndex[pool];
        uint256 returnCount = count > cardinality ? cardinality : count;
        
        latestObs = new Observation[](returnCount);
        
        for (uint256 i = 0; i < returnCount; i++) {
            uint16 searchIndex = (index + cardinality - uint16(i)) % cardinality;
            latestObs[i] = observations[pool][searchIndex];
        }
    }

    /**
     * @dev Check if TWAP is stale
     */
    function isTWAPStale(address pool, uint256 maxAge) 
        external 
        view 
        validPool(pool) 
        returns (bool) 
    {
        return block.timestamp > twapData[pool].lastUpdate + maxAge;
    }

    /**
     * @dev Get configuration
     */
    function getConfiguration() 
        external 
        view 
        returns (
            uint32 _defaultPeriod,
            uint16 _defaultCardinality,
            uint256 _updateInterval,
            uint256 _maxPriceDeviation,
            bool _emergencyMode
        ) 
    {
        return (
            defaultPeriod,
            defaultCardinality,
            updateInterval,
            maxPriceDeviation,
            emergencyMode
        );
    }
} 