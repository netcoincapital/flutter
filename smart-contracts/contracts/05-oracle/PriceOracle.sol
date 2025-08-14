// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";

import "../01-core/AccessControl.sol";
import "./TWAPOracle.sol";
import "./ChainlinkOracle.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title PriceOracle
 * @dev Main oracle contract that aggregates TWAP and Chainlink price data
 * @dev Provides unified interface for price queries with validation and fallback
 */
contract PriceOracle is Pausable, LaxceAccessControl {
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_PRICE_DEVIATION = 2000; // 20%
    uint256 public constant MIN_UPDATE_INTERVAL = 60; // 1 minute
    uint256 public constant MAX_UPDATE_INTERVAL = 3600; // 1 hour
    uint256 public constant EMERGENCY_THRESHOLD = 5000; // 50% deviation triggers emergency

    // =========== ENUMS ===========
    enum PriceSource {
        TWAP,
        CHAINLINK,
        COMBINED,
        FALLBACK
    }

    enum OracleStatus {
        ACTIVE,
        INACTIVE,
        EMERGENCY,
        MAINTENANCE
    }

    // =========== STRUCTS ===========
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
        PriceSource source;
        uint256 confidence; // 0-10000 (0-100%)
        bool isValid;
    }

    struct AggregatedPrice {
        uint256 price;
        uint256 twapPrice;
        uint256 chainlinkPrice;
        uint256 timestamp;
        uint256 deviation;
        PriceSource primarySource;
        bool isValid;
        uint256 confidence;
    }

    struct OracleConfig {
        bool useTWAP;
        bool useChainlink;
        bool requireBothSources;
        uint256 maxDeviation;
        uint256 twapWeight; // 0-10000 (0-100%)
        uint256 chainlinkWeight; // 0-10000 (0-100%)
        uint256 confidenceThreshold; // Minimum confidence required
        uint256 stalePriceThreshold;
    }

    struct TokenPairConfig {
        bool isActive;
        OracleConfig config;
        uint256 lastUpdate;
        uint256 updateInterval;
        PriceSource preferredSource;
        uint256 emergencyPrice;
        uint256 emergencyTimestamp;
    }

    // =========== STATE VARIABLES ===========
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    TWAPOracle public immutable twapOracle;
    ChainlinkOracle public immutable chainlinkOracle;
    
    // Token pair configurations
    mapping(bytes32 => TokenPairConfig) public tokenPairConfigs;
    mapping(bytes32 => AggregatedPrice) public latestPrices;
    
    // Global configuration
    OracleConfig public defaultConfig;
    OracleStatus public status = OracleStatus.ACTIVE;
    
    // Price history for validation
    mapping(bytes32 => uint256[]) public priceHistory;
    mapping(bytes32 => uint256) public historyIndex;
    uint256 public maxHistoryLength = 100;
    
    // Supported token pairs
    bytes32[] public supportedPairs;
    mapping(bytes32 => bool) public isPairSupported;
    
    // Emergency settings
    bool public emergencyMode = false;
    mapping(bytes32 => uint256) public emergencyPrices;
    mapping(bytes32 => uint256) public emergencyTimestamps;

    // =========== EVENTS ===========
    event PriceUpdated(
        bytes32 indexed pairKey,
        uint256 price,
        uint256 twapPrice,
        uint256 chainlinkPrice,
        PriceSource primarySource,
        uint256 confidence
    );
    
    event TokenPairAdded(
        bytes32 indexed pairKey,
        address token0,
        address token1,
        OracleConfig config
    );
    
    event TokenPairConfigUpdated(bytes32 indexed pairKey, OracleConfig config);
    event DefaultConfigUpdated(OracleConfig config);
    event OracleStatusChanged(OracleStatus oldStatus, OracleStatus newStatus);
    event EmergencyModeToggled(bool enabled);
    event EmergencyPriceSet(bytes32 indexed pairKey, uint256 price);
    event PriceDeviationDetected(
        bytes32 indexed pairKey,
        uint256 twapPrice,
        uint256 chainlinkPrice,
        uint256 deviation
    );

    // =========== ERRORS ===========
    error PriceOracle__InvalidOracles();
    error PriceOracle__PairNotSupported();
    error PriceOracle__PairAlreadyExists();
    error PriceOracle__InvalidConfiguration();
    error PriceOracle__NoValidPrice();
    error PriceOracle__PriceDeviationTooHigh();
    error PriceOracle__InsufficientConfidence();
    error PriceOracle__EmergencyModeActive();
    error PriceOracle__OracleInactive();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier validPair(bytes32 pairKey) {
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        _;
    }

    modifier whenActive() {
        if (status != OracleStatus.ACTIVE) revert PriceOracle__OracleInactive();
        _;
    }

    modifier notInEmergency() {
        if (emergencyMode) revert PriceOracle__EmergencyModeActive();
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor(address _twapOracle, address _chainlinkOracle) {
        if (_twapOracle == address(0) || _chainlinkOracle == address(0)) {
            revert PriceOracle__InvalidOracles();
        }

        twapOracle = TWAPOracle(_twapOracle);
        chainlinkOracle = ChainlinkOracle(_chainlinkOracle);
        
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Initialize default configuration
        defaultConfig = OracleConfig({
            useTWAP: true,
            useChainlink: true,
            requireBothSources: false,
            maxDeviation: 1000, // 10%
            twapWeight: 6000, // 60%
            chainlinkWeight: 4000, // 40%
            confidenceThreshold: 7000, // 70%
            stalePriceThreshold: 3600 // 1 hour
        });
    }

    // =========== PAIR MANAGEMENT ===========

    /**
     * @dev Add a new token pair for price tracking
     * @param token0 First token address
     * @param token1 Second token address
     * @param config Oracle configuration for this pair
     */
    function addTokenPair(
        address token0,
        address token1,
        OracleConfig calldata config
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (isPairSupported[pairKey]) revert PriceOracle__PairAlreadyExists();
        
        _validateConfig(config);
        
        tokenPairConfigs[pairKey] = TokenPairConfig({
            isActive: true,
            config: config,
            lastUpdate: 0,
            updateInterval: MIN_UPDATE_INTERVAL,
            preferredSource: PriceSource.COMBINED,
            emergencyPrice: 0,
            emergencyTimestamp: 0
        });
        
        // Initialize price history
        priceHistory[pairKey] = new uint256[](maxHistoryLength);
        historyIndex[pairKey] = 0;
        
        // Add to supported pairs
        supportedPairs.push(pairKey);
        isPairSupported[pairKey] = true;
        
        emit TokenPairAdded(pairKey, token0, token1, config);
    }

    /**
     * @dev Update configuration for a token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @param config New oracle configuration
     */
    function updateTokenPairConfig(
        address token0,
        address token1,
        OracleConfig calldata config
    ) external onlyRole(ADMIN_ROLE) {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        
        _validateConfig(config);
        
        tokenPairConfigs[pairKey].config = config;
        
        emit TokenPairConfigUpdated(pairKey, config);
    }

    /**
     * @dev Set default oracle configuration
     * @param config New default configuration
     */
    function setDefaultConfig(OracleConfig calldata config) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        _validateConfig(config);
        defaultConfig = config;
        
        emit DefaultConfigUpdated(config);
    }

    // =========== PRICE QUERIES ===========

    /**
     * @dev Get latest aggregated price for token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return aggregatedPrice Complete price information
     */
    function getPrice(address token0, address token1) 
        external 
        view 
        returns (AggregatedPrice memory aggregatedPrice) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        
        return latestPrices[pairKey];
    }

    /**
     * @dev Get latest price with on-demand update
     * @param token0 First token address
     * @param token1 Second token address
     * @return aggregatedPrice Fresh price information
     */
    function getLatestPrice(address token0, address token1) 
        external 
        nonReentrant 
        whenActive 
        returns (AggregatedPrice memory aggregatedPrice) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        
        _updatePrice(pairKey, token0, token1);
        
        return latestPrices[pairKey];
    }

    /**
     * @dev Get prices from all sources for comparison
     * @param token0 First token address
     * @param token1 Second token address
     * @return twapPrice TWAP price
     * @return chainlinkPrice Chainlink price
     * @return aggregatedPrice Combined price
     */
    function getAllPrices(address token0, address token1) 
        external 
        view 
        validPair(_getPairKey(token0, token1))
        returns (
            uint256 twapPrice,
            uint256 chainlinkPrice,
            AggregatedPrice memory aggregatedPrice
        ) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        aggregatedPrice = latestPrices[pairKey];
        twapPrice = aggregatedPrice.twapPrice;
        chainlinkPrice = aggregatedPrice.chainlinkPrice;
    }

    /**
     * @dev Check if price is fresh (within staleness threshold)
     * @param token0 First token address
     * @param token1 Second token address
     * @return isFresh True if price is fresh
     */
    function isPriceFresh(address token0, address token1) 
        external 
        view 
        returns (bool isFresh) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) return false;
        
        TokenPairConfig memory pairConfig = tokenPairConfigs[pairKey];
        AggregatedPrice memory price = latestPrices[pairKey];
        
        return block.timestamp <= price.timestamp + pairConfig.config.stalePriceThreshold;
    }

    /**
     * @dev Batch get prices for multiple pairs
     * @param token0s Array of first tokens
     * @param token1s Array of second tokens
     * @return prices Array of aggregated prices
     */
    function getBatchPrices(
        address[] calldata token0s,
        address[] calldata token1s
    ) external view returns (AggregatedPrice[] memory prices) {
        require(token0s.length == token1s.length, "Array length mismatch");
        
        prices = new AggregatedPrice[](token0s.length);
        
        for (uint256 i = 0; i < token0s.length; i++) {
            bytes32 pairKey = _getPairKey(token0s[i], token1s[i]);
            
            if (isPairSupported[pairKey]) {
                prices[i] = latestPrices[pairKey];
            } else {
                prices[i] = AggregatedPrice({
                    price: 0,
                    twapPrice: 0,
                    chainlinkPrice: 0,
                    timestamp: 0,
                    deviation: 0,
                    primarySource: PriceSource.FALLBACK,
                    isValid: false,
                    confidence: 0
                });
            }
        }
    }

    // =========== PRICE UPDATES ===========

    /**
     * @dev Update price for a specific token pair
     * @param token0 First token address
     * @param token1 Second token address
     */
    function updatePrice(address token0, address token1) 
        external 
        nonReentrant 
        whenActive 
        notInEmergency 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        
        _updatePrice(pairKey, token0, token1);
    }

    /**
     * @dev Batch update prices for multiple pairs
     * @param token0s Array of first tokens
     * @param token1s Array of second tokens
     */
    function batchUpdatePrices(
        address[] calldata token0s,
        address[] calldata token1s
    ) external nonReentrant onlyRole(OPERATOR_ROLE) whenActive {
        require(token0s.length == token1s.length, "Array length mismatch");
        
        for (uint256 i = 0; i < token0s.length; i++) {
            bytes32 pairKey = _getPairKey(token0s[i], token1s[i]);
            
            if (isPairSupported[pairKey]) {
                try this.updatePrice(token0s[i], token1s[i]) {
                    // Success
                } catch {
                    // Skip failed updates
                    continue;
                }
            }
        }
    }

    // =========== INTERNAL FUNCTIONS ===========

    /**
     * @dev Internal price update logic
     */
    function _updatePrice(bytes32 pairKey, address token0, address token1) internal {
        TokenPairConfig storage pairConfig = tokenPairConfigs[pairKey];
        OracleConfig memory config = pairConfig.config;
        
        uint256 twapPrice = 0;
        uint256 chainlinkPrice = 0;
        bool twapValid = false;
        bool chainlinkValid = false;
        
        // Get TWAP price if enabled
        if (config.useTWAP) {
            try twapOracle.getTWAPPrice(address(0), 3600) returns (uint256 price0, uint256) {
                twapPrice = price0;
                twapValid = true;
            } catch {
                twapValid = false;
            }
        }
        
        // Get Chainlink price if enabled
        if (config.useChainlink) {
            try chainlinkOracle.getLatestPrice(token0, token1) returns (
                ChainlinkOracle.PriceData memory data
            ) {
                if (data.isValid) {
                    chainlinkPrice = data.price;
                    chainlinkValid = true;
                }
            } catch {
                chainlinkValid = false;
            }
        }
        
        // Validate we have required sources
        if (config.requireBothSources && (!twapValid || !chainlinkValid)) {
            revert PriceOracle__NoValidPrice();
        }
        
        if (!twapValid && !chainlinkValid) {
            revert PriceOracle__NoValidPrice();
        }
        
        // Calculate aggregated price
        AggregatedPrice memory aggregatedPrice = _aggregatePrices(
            twapPrice,
            chainlinkPrice,
            twapValid,
            chainlinkValid,
            config
        );
        
        // Check price deviation if both sources available
        if (twapValid && chainlinkValid) {
            uint256 deviation = _calculateDeviation(twapPrice, chainlinkPrice);
            aggregatedPrice.deviation = deviation;
            
            if (deviation > config.maxDeviation) {
                emit PriceDeviationDetected(pairKey, twapPrice, chainlinkPrice, deviation);
                
                // Use emergency threshold check
                if (deviation > EMERGENCY_THRESHOLD) {
                    _triggerEmergencyMode(pairKey);
                    return;
                }
            }
        }
        
        // Validate confidence
        if (aggregatedPrice.confidence < config.confidenceThreshold) {
            revert PriceOracle__InsufficientConfidence();
        }
        
        // Store aggregated price
        latestPrices[pairKey] = aggregatedPrice;
        pairConfig.lastUpdate = block.timestamp;
        
        // Add to price history
        _addToPriceHistory(pairKey, aggregatedPrice.price);
        
        emit PriceUpdated(
            pairKey,
            aggregatedPrice.price,
            twapPrice,
            chainlinkPrice,
            aggregatedPrice.primarySource,
            aggregatedPrice.confidence
        );
    }

    /**
     * @dev Aggregate prices from multiple sources
     */
    function _aggregatePrices(
        uint256 twapPrice,
        uint256 chainlinkPrice,
        bool twapValid,
        bool chainlinkValid,
        OracleConfig memory config
    ) internal pure returns (AggregatedPrice memory) {
        uint256 finalPrice;
        PriceSource primarySource;
        uint256 confidence;
        
        if (twapValid && chainlinkValid) {
            // Calculate weighted average
            finalPrice = (twapPrice * config.twapWeight + chainlinkPrice * config.chainlinkWeight) / 10000;
            primarySource = PriceSource.COMBINED;
            confidence = 9000; // High confidence with both sources
        } else if (twapValid) {
            finalPrice = twapPrice;
            primarySource = PriceSource.TWAP;
            confidence = 7000; // Medium confidence with single source
        } else if (chainlinkValid) {
            finalPrice = chainlinkPrice;
            primarySource = PriceSource.CHAINLINK;
            confidence = 7000; // Medium confidence with single source
        } else {
            finalPrice = 0;
            primarySource = PriceSource.FALLBACK;
            confidence = 0;
        }
        
        return AggregatedPrice({
            price: finalPrice,
            twapPrice: twapPrice,
            chainlinkPrice: chainlinkPrice,
            timestamp: block.timestamp,
            deviation: 0, // Will be set by caller
            primarySource: primarySource,
            isValid: finalPrice > 0,
            confidence: confidence
        });
    }

    /**
     * @dev Calculate deviation between two prices
     */
    function _calculateDeviation(uint256 price1, uint256 price2) 
        internal 
        pure 
        returns (uint256) 
    {
        if (price1 == 0 || price2 == 0) return 0;
        
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;
        
        return (diff * 10000) / avg;
    }

    /**
     * @dev Add price to history
     */
    function _addToPriceHistory(bytes32 pairKey, uint256 price) internal {
        uint256 index = historyIndex[pairKey] % maxHistoryLength;
        priceHistory[pairKey][index] = price;
        historyIndex[pairKey] = index + 1;
    }

    /**
     * @dev Validate oracle configuration
     */
    function _validateConfig(OracleConfig memory config) internal pure {
        if (!config.useTWAP && !config.useChainlink) {
            revert PriceOracle__InvalidConfiguration();
        }
        
        if (config.twapWeight + config.chainlinkWeight != 10000) {
            revert PriceOracle__InvalidConfiguration();
        }
        
        if (config.maxDeviation > 5000) { // Max 50%
            revert PriceOracle__InvalidConfiguration();
        }
        
        if (config.confidenceThreshold > 10000) {
            revert PriceOracle__InvalidConfiguration();
        }
    }

    /**
     * @dev Generate pair key for token pair
     */
    function _getPairKey(address token0, address token1) 
        internal 
        pure 
        returns (bytes32) 
    {
        return token0 < token1 
            ? keccak256(abi.encodePacked(token0, token1))
            : keccak256(abi.encodePacked(token1, token0));
    }

    /**
     * @dev Trigger emergency mode for a specific pair
     */
    function _triggerEmergencyMode(bytes32 pairKey) internal {
        emergencyMode = true;
        
        // Set emergency price to the last valid price
        AggregatedPrice memory lastPrice = latestPrices[pairKey];
        if (lastPrice.isValid) {
            emergencyPrices[pairKey] = lastPrice.price;
            emergencyTimestamps[pairKey] = block.timestamp;
        }
        
        emit EmergencyModeToggled(true);
        emit EmergencyPriceSet(pairKey, emergencyPrices[pairKey]);
    }

    // =========== ADMIN FUNCTIONS ===========

    /**
     * @dev Set oracle status
     */
    function setOracleStatus(OracleStatus newStatus) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        OracleStatus oldStatus = status;
        status = newStatus;
        
        emit OracleStatusChanged(oldStatus, newStatus);
    }

    /**
     * @dev Exit emergency mode
     */
    function exitEmergencyMode() external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = false;
        emit EmergencyModeToggled(false);
    }

    /**
     * @dev Set emergency price for a pair
     */
    function setEmergencyPrice(
        address token0,
        address token1,
        uint256 price
    ) external onlyRole(EMERGENCY_ROLE) {
        bytes32 pairKey = _getPairKey(token0, token1);
        emergencyPrices[pairKey] = price;
        emergencyTimestamps[pairKey] = block.timestamp;
        
        emit EmergencyPriceSet(pairKey, price);
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
     * @dev Get all supported pairs
     */
    function getSupportedPairs() external view returns (bytes32[] memory) {
        return supportedPairs;
    }

    /**
     * @dev Get supported pairs count
     */
    function getSupportedPairsCount() external view returns (uint256) {
        return supportedPairs.length;
    }

    /**
     * @dev Get pair configuration
     */
    function getPairConfig(address token0, address token1) 
        external 
        view 
        returns (TokenPairConfig memory) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        return tokenPairConfigs[pairKey];
    }

    /**
     * @dev Get price history for a pair
     */
    function getPriceHistory(address token0, address token1, uint256 count) 
        external 
        view 
        returns (uint256[] memory prices) 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        if (!isPairSupported[pairKey]) revert PriceOracle__PairNotSupported();
        
        uint256[] memory history = priceHistory[pairKey];
        uint256 histIdx = historyIndex[pairKey];
        uint256 returnCount = count > histIdx ? histIdx : count;
        
        prices = new uint256[](returnCount);
        
        for (uint256 i = 0; i < returnCount; i++) {
            uint256 index = (histIdx + maxHistoryLength - 1 - i) % maxHistoryLength;
            prices[i] = history[index];
        }
    }

    /**
     * @dev Get oracle health status
     */
    function getOracleHealth() 
        external 
        view 
        returns (
            OracleStatus oracleStatus,
            bool emergency,
            uint256 activePairs,
            uint256 totalPairs
        ) 
    {
        return (
            status,
            emergencyMode,
            supportedPairs.length, // Simplified - in practice would count active pairs
            supportedPairs.length
        );
    }
} 