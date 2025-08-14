// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../01-core/AccessControl.sol";
import "./PriceOracle.sol";
import "./TWAPOracle.sol";
import "./ChainlinkOracle.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title OracleManager
 * @dev Central management contract for all oracle functionality
 * @dev Coordinates between TWAP, Chainlink, and PriceOracle contracts
 */
contract OracleManager is Pausable, LaxceAccessControl, Multicall {
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant MAX_ORACLES = 10;
    uint256 public constant UPDATE_BATCH_SIZE = 50;
    uint256 public constant HEALTH_CHECK_INTERVAL = 300; // 5 minutes
    uint256 public constant EMERGENCY_COOLDOWN = 3600; // 1 hour

    // =========== ENUMS ===========
    enum OracleType {
        TWAP,
        CHAINLINK,
        AGGREGATED,
        EXTERNAL
    }

    enum ManagerStatus {
        ACTIVE,
        MAINTENANCE,
        EMERGENCY,
        UPGRADING
    }

    // =========== STRUCTS ===========
    struct OracleInfo {
        address oracle;
        OracleType oracleType;
        bool isActive;
        uint256 priority;
        uint256 lastHealthCheck;
        bool isHealthy;
        string name;
    }

    struct HealthReport {
        address oracle;
        bool isHealthy;
        uint256 lastUpdate;
        uint256 activePairs;
        string status;
    }

    struct BatchUpdateRequest {
        address[] token0s;
        address[] token1s;
        bool forceUpdate;
        uint256 batchId;
    }

    struct PriceValidationConfig {
        uint256 maxDeviation;
        uint256 minConfidence;
        bool requireMultipleSources;
        uint256 stalePriceThreshold;
    }

    // =========== STATE VARIABLES ===========
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    // Core oracle contracts
    PriceOracle public immutable priceOracle;
    TWAPOracle public immutable twapOracle;
    ChainlinkOracle public immutable chainlinkOracle;
    
    // Oracle registry
    OracleInfo[] public registeredOracles;
    mapping(address => uint256) public oracleIndex;
    mapping(address => bool) public isOracleRegistered;
    
    // Manager configuration
    ManagerStatus public status = ManagerStatus.ACTIVE;
    PriceValidationConfig public validationConfig;
    
    // Update management
    uint256 public batchUpdateCounter = 0;
    mapping(uint256 => BatchUpdateRequest) public batchRequests;
    mapping(address => uint256) public lastPriceUpdate;
    
    // Health monitoring
    uint256 public lastGlobalHealthCheck;
    mapping(address => uint256) public lastOracleHealthCheck;
    uint256 public healthCheckInterval = HEALTH_CHECK_INTERVAL;
    
    // Emergency management
    bool public emergencyMode = false;
    uint256 public emergencyActivatedAt;
    mapping(address => bool) public emergencyOracles;
    
    // Automation
    bool public autoUpdateEnabled = true;
    uint256 public autoUpdateInterval = 300; // 5 minutes
    mapping(bytes32 => uint256) public lastAutoUpdate;

    // =========== EVENTS ===========
    event OracleRegistered(
        address indexed oracle,
        OracleType oracleType,
        string name,
        uint256 priority
    );
    
    event OracleStatusUpdated(address indexed oracle, bool isActive, bool isHealthy);
    event ManagerStatusChanged(ManagerStatus oldStatus, ManagerStatus newStatus);
    event BatchUpdateExecuted(uint256 indexed batchId, uint256 successful, uint256 failed);
    event HealthCheckCompleted(address indexed oracle, bool isHealthy);
    event EmergencyModeActivated(address indexed trigger, string reason);
    event EmergencyModeDeactivated(address indexed operator);
    event ValidationConfigUpdated(PriceValidationConfig config);
    event AutoUpdateConfigChanged(bool enabled, uint256 interval);

    // =========== ERRORS ===========
    error OracleManager__InvalidOracle();
    error OracleManager__OracleAlreadyRegistered();
    error OracleManager__OracleNotRegistered();
    error OracleManager__MaxOraclesReached();
    error OracleManager__InvalidConfiguration();
    error OracleManager__EmergencyModeActive();
    error OracleManager__InsufficientPermissions();
    error OracleManager__UpdateTooSoon();
    error OracleManager__BatchSizeExceeded();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier whenManagerActive() {
        require(status == ManagerStatus.ACTIVE, "Manager not active");
        _;
    }

    modifier validOracle(address oracle) {
        if (!isOracleRegistered[oracle]) revert OracleManager__OracleNotRegistered();
        _;
    }

    modifier notInEmergency() {
        if (emergencyMode) revert OracleManager__EmergencyModeActive();
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor(
        address _priceOracle,
        address _twapOracle,
        address _chainlinkOracle
    ) {
        if (_priceOracle == address(0) || 
            _twapOracle == address(0) || 
            _chainlinkOracle == address(0)) {
            revert OracleManager__InvalidOracle();
        }

        priceOracle = PriceOracle(_priceOracle);
        twapOracle = TWAPOracle(_twapOracle);
        chainlinkOracle = ChainlinkOracle(_chainlinkOracle);
        
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // Initialize validation config
        validationConfig = PriceValidationConfig({
            maxDeviation: 1000, // 10%
            minConfidence: 7000, // 70%
            requireMultipleSources: false,
            stalePriceThreshold: 3600 // 1 hour
        });
        
        // Register core oracles
        _registerCoreOracles();
    }

    // =========== ORACLE REGISTRATION ===========

    /**
     * @dev Register a new oracle
     * @param oracle Oracle contract address
     * @param oracleType Type of oracle
     * @param name Human readable name
     * @param priority Priority level (higher = more important)
     */
    function registerOracle(
        address oracle,
        OracleType oracleType,
        string calldata name,
        uint256 priority
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        if (oracle == address(0)) revert OracleManager__InvalidOracle();
        if (isOracleRegistered[oracle]) revert OracleManager__OracleAlreadyRegistered();
        if (registeredOracles.length >= MAX_ORACLES) revert OracleManager__MaxOraclesReached();

        OracleInfo memory oracleInfo = OracleInfo({
            oracle: oracle,
            oracleType: oracleType,
            isActive: true,
            priority: priority,
            lastHealthCheck: 0,
            isHealthy: true,
            name: name
        });
        
        registeredOracles.push(oracleInfo);
        oracleIndex[oracle] = registeredOracles.length - 1;
        isOracleRegistered[oracle] = true;
        
        emit OracleRegistered(oracle, oracleType, name, priority);
    }

    /**
     * @dev Update oracle status
     * @param oracle Oracle address
     * @param isActive Whether oracle is active
     */
    function setOracleStatus(address oracle, bool isActive) 
        external 
        onlyRole(OPERATOR_ROLE) 
        validOracle(oracle) 
    {
        uint256 index = oracleIndex[oracle];
        registeredOracles[index].isActive = isActive;
        
        emit OracleStatusUpdated(oracle, isActive, registeredOracles[index].isHealthy);
    }

    /**
     * @dev Remove oracle from registry
     * @param oracle Oracle address to remove
     */
    function removeOracle(address oracle) 
        external 
        onlyRole(ADMIN_ROLE) 
        validOracle(oracle) 
    {
        uint256 index = oracleIndex[oracle];
        uint256 lastIndex = registeredOracles.length - 1;
        
        // Move last oracle to the removed position
        if (index != lastIndex) {
            registeredOracles[index] = registeredOracles[lastIndex];
            oracleIndex[registeredOracles[index].oracle] = index;
        }
        
        // Remove last element
        registeredOracles.pop();
        delete oracleIndex[oracle];
        delete isOracleRegistered[oracle];
    }

    // =========== PRICE MANAGEMENT ===========

    /**
     * @dev Get aggregated price for token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return price Aggregated price information
     */
    function getPrice(address token0, address token1) 
        external 
        view 
        whenManagerActive 
        returns (PriceOracle.AggregatedPrice memory price) 
    {
        return priceOracle.getPrice(token0, token1);
    }

    /**
     * @dev Get latest price with validation
     * @param token0 First token address
     * @param token1 Second token address
     * @return price Validated price information
     */
    function getValidatedPrice(address token0, address token1) 
        external 
        view 
        whenManagerActive 
        returns (PriceOracle.AggregatedPrice memory price) 
    {
        price = priceOracle.getPrice(token0, token1);
        
        // Validate price
        if (!price.isValid) revert OracleManager__InvalidOracle();
        if (price.confidence < validationConfig.minConfidence) {
            revert OracleManager__InvalidConfiguration();
        }
        
        // Check staleness
        if (block.timestamp > price.timestamp + validationConfig.stalePriceThreshold) {
            revert OracleManager__UpdateTooSoon();
        }
    }

    /**
     * @dev Update price for token pair
     * @param token0 First token address
     * @param token1 Second token address
     */
    function updatePrice(address token0, address token1) 
        external 
        nonReentrant 
        whenManagerActive 
        notInEmergency 
    {
        bytes32 pairKey = _getPairKey(token0, token1);
        
        // Check update frequency
        if (block.timestamp < lastPriceUpdate[pairKey] + autoUpdateInterval) {
            revert OracleManager__UpdateTooSoon();
        }
        
        // Update price through PriceOracle
        priceOracle.updatePrice(token0, token1);
        lastPriceUpdate[pairKey] = block.timestamp;
    }

    /**
     * @dev Batch update prices for multiple pairs
     * @param token0s Array of first tokens
     * @param token1s Array of second tokens
     * @param forceUpdate Whether to ignore update frequency limits
     * @return batchId Batch identifier for tracking
     */
    function batchUpdatePrices(
        address[] calldata token0s,
        address[] calldata token1s,
        bool forceUpdate
    ) external nonReentrant onlyRole(OPERATOR_ROLE) whenManagerActive returns (uint256 batchId) {
        require(token0s.length == token1s.length, "Array length mismatch");
        if (token0s.length > UPDATE_BATCH_SIZE) revert OracleManager__BatchSizeExceeded();
        
        batchId = ++batchUpdateCounter;
        
        // Store batch request
        batchRequests[batchId] = BatchUpdateRequest({
            token0s: token0s,
            token1s: token1s,
            forceUpdate: forceUpdate,
            batchId: batchId
        });
        
        uint256 successful = 0;
        uint256 failed = 0;
        
        for (uint256 i = 0; i < token0s.length; i++) {
            bytes32 pairKey = _getPairKey(token0s[i], token1s[i]);
            
            // Check if update is needed
            if (!forceUpdate && 
                block.timestamp < lastPriceUpdate[pairKey] + autoUpdateInterval) {
                failed++;
                continue;
            }
            
            try priceOracle.updatePrice(token0s[i], token1s[i]) {
                lastPriceUpdate[pairKey] = block.timestamp;
                successful++;
            } catch {
                failed++;
            }
        }
        
        emit BatchUpdateExecuted(batchId, successful, failed);
    }

    // =========== HEALTH MONITORING ===========

    /**
     * @dev Perform health check on all registered oracles
     */
    function performGlobalHealthCheck() 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
    {
        lastGlobalHealthCheck = block.timestamp;
        
        for (uint256 i = 0; i < registeredOracles.length; i++) {
            address oracle = registeredOracles[i].oracle;
            _performOracleHealthCheck(oracle);
        }
    }

    /**
     * @dev Perform health check on specific oracle
     * @param oracle Oracle address
     */
    function performOracleHealthCheck(address oracle) 
        external 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
        validOracle(oracle) 
    {
        _performOracleHealthCheck(oracle);
    }

    /**
     * @dev Get health report for all oracles
     * @return reports Array of health reports
     */
    function getHealthReport() 
        external 
        view 
        returns (HealthReport[] memory reports) 
    {
        reports = new HealthReport[](registeredOracles.length);
        
        for (uint256 i = 0; i < registeredOracles.length; i++) {
            OracleInfo memory info = registeredOracles[i];
            
            reports[i] = HealthReport({
                oracle: info.oracle,
                isHealthy: info.isHealthy,
                lastUpdate: info.lastHealthCheck,
                activePairs: _getOracleActivePairs(info.oracle),
                status: info.isActive ? "Active" : "Inactive"
            });
        }
    }

    /**
     * @dev Check if auto-update is needed
     * @param token0 First token address
     * @param token1 Second token address
     * @return needsUpdate True if update is needed
     */
    function needsAutoUpdate(address token0, address token1) 
        external 
        view 
        returns (bool needsUpdate) 
    {
        if (!autoUpdateEnabled) return false;
        
        bytes32 pairKey = _getPairKey(token0, token1);
        return block.timestamp >= lastAutoUpdate[pairKey] + autoUpdateInterval;
    }

    // =========== EMERGENCY MANAGEMENT ===========

    /**
     * @dev Activate emergency mode
     * @param reason Reason for emergency activation
     */
    function activateEmergencyMode(string calldata reason) 
        external 
        onlyRole(EMERGENCY_ROLE) 
    {
        emergencyMode = true;
        emergencyActivatedAt = block.timestamp;
        status = ManagerStatus.EMERGENCY;
        
        emit EmergencyModeActivated(msg.sender, reason);
        emit ManagerStatusChanged(ManagerStatus.ACTIVE, ManagerStatus.EMERGENCY);
    }

    /**
     * @dev Deactivate emergency mode
     */
    function deactivateEmergencyMode() 
        external 
        onlyRole(EMERGENCY_ROLE) 
    {
        require(emergencyMode, "Emergency mode not active");
        require(
            block.timestamp >= emergencyActivatedAt + EMERGENCY_COOLDOWN,
            "Emergency cooldown not met"
        );
        
        emergencyMode = false;
        emergencyActivatedAt = 0;
        status = ManagerStatus.ACTIVE;
        
        emit EmergencyModeDeactivated(msg.sender);
        emit ManagerStatusChanged(ManagerStatus.EMERGENCY, ManagerStatus.ACTIVE);
    }

    /**
     * @dev Set emergency oracle status
     * @param oracle Oracle address
     * @param isEmergency Whether oracle is in emergency mode
     */
    function setEmergencyOracle(address oracle, bool isEmergency) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        validOracle(oracle) 
    {
        emergencyOracles[oracle] = isEmergency;
    }

    // =========== CONFIGURATION ===========

    /**
     * @dev Set manager status
     * @param newStatus New manager status
     */
    function setManagerStatus(ManagerStatus newStatus) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        ManagerStatus oldStatus = status;
        status = newStatus;
        
        emit ManagerStatusChanged(oldStatus, newStatus);
    }

    /**
     * @dev Set validation configuration
     * @param config New validation configuration
     */
    function setValidationConfig(PriceValidationConfig calldata config) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        if (config.maxDeviation > 5000) revert OracleManager__InvalidConfiguration(); // Max 50%
        if (config.minConfidence > 10000) revert OracleManager__InvalidConfiguration(); // Max 100%
        
        validationConfig = config;
        
        emit ValidationConfigUpdated(config);
    }

    /**
     * @dev Set auto-update configuration
     * @param enabled Whether auto-update is enabled
     * @param interval Update interval in seconds
     */
    function setAutoUpdateConfig(bool enabled, uint256 interval) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        autoUpdateEnabled = enabled;
        autoUpdateInterval = interval;
        
        emit AutoUpdateConfigChanged(enabled, interval);
    }

    /**
     * @dev Set health check interval
     * @param interval New health check interval
     */
    function setHealthCheckInterval(uint256 interval) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        healthCheckInterval = interval;
    }

    // =========== INTERNAL FUNCTIONS ===========

    /**
     * @dev Register core oracles during initialization
     */
    function _registerCoreOracles() internal {
        // Register PriceOracle
        registeredOracles.push(OracleInfo({
            oracle: address(priceOracle),
            oracleType: OracleType.AGGREGATED,
            isActive: true,
            priority: 100,
            lastHealthCheck: 0,
            isHealthy: true,
            name: "Price Oracle"
        }));
        oracleIndex[address(priceOracle)] = 0;
        isOracleRegistered[address(priceOracle)] = true;
        
        // Register TWAPOracle
        registeredOracles.push(OracleInfo({
            oracle: address(twapOracle),
            oracleType: OracleType.TWAP,
            isActive: true,
            priority: 80,
            lastHealthCheck: 0,
            isHealthy: true,
            name: "TWAP Oracle"
        }));
        oracleIndex[address(twapOracle)] = 1;
        isOracleRegistered[address(twapOracle)] = true;
        
        // Register ChainlinkOracle
        registeredOracles.push(OracleInfo({
            oracle: address(chainlinkOracle),
            oracleType: OracleType.CHAINLINK,
            isActive: true,
            priority: 90,
            lastHealthCheck: 0,
            isHealthy: true,
            name: "Chainlink Oracle"
        }));
        oracleIndex[address(chainlinkOracle)] = 2;
        isOracleRegistered[address(chainlinkOracle)] = true;
    }

    /**
     * @dev Perform health check on specific oracle
     */
    function _performOracleHealthCheck(address oracle) internal {
        uint256 index = oracleIndex[oracle];
        bool isHealthy = true;
        
        // Perform health check based on oracle type
        OracleType oracleType = registeredOracles[index].oracleType;
        
        if (oracleType == OracleType.AGGREGATED) {
            // Check PriceOracle health
            try PriceOracle(oracle).getOracleHealth() returns (
                PriceOracle.OracleStatus oracleStatus,
                bool emergency,
                uint256,
                uint256
            ) {
                isHealthy = (oracleStatus == PriceOracle.OracleStatus.ACTIVE) && !emergency;
            } catch {
                isHealthy = false;
            }
        } else if (oracleType == OracleType.CHAINLINK) {
            // Check ChainlinkOracle health - simplified check
            try ChainlinkOracle(oracle).getAllFeedKeys() returns (bytes32[] memory) {
                isHealthy = true; // If we can call this function, oracle is responsive
            } catch {
                isHealthy = false;
            }
        } else if (oracleType == OracleType.TWAP) {
            // Check TWAPOracle health
            try TWAPOracle(oracle).getSupportedPoolsCount() returns (uint256 count) {
                isHealthy = count > 0; // At least one pool should be supported
            } catch {
                isHealthy = false;
            }
        }
        
        // Update oracle health status
        registeredOracles[index].isHealthy = isHealthy;
        registeredOracles[index].lastHealthCheck = block.timestamp;
        lastOracleHealthCheck[oracle] = block.timestamp;
        
        emit HealthCheckCompleted(oracle, isHealthy);
        emit OracleStatusUpdated(oracle, registeredOracles[index].isActive, isHealthy);
    }

    /**
     * @dev Get number of active pairs for an oracle
     */
    function _getOracleActivePairs(address oracle) internal view returns (uint256) {
        // Simplified implementation - in practice would query each oracle type differently
        if (oracle == address(priceOracle)) {
            return priceOracle.getSupportedPairsCount();
        } else if (oracle == address(twapOracle)) {
            return twapOracle.getSupportedPoolsCount();
        } else if (oracle == address(chainlinkOracle)) {
            return chainlinkOracle.getAllFeedKeys().length;
        }
        return 0;
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

    // =========== ADMIN FUNCTIONS ===========

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
     * @dev Get all registered oracles
     */
    function getRegisteredOracles() external view returns (OracleInfo[] memory) {
        return registeredOracles;
    }

    /**
     * @dev Get oracle information
     */
    function getOracleInfo(address oracle) 
        external 
        view 
        validOracle(oracle) 
        returns (OracleInfo memory) 
    {
        uint256 index = oracleIndex[oracle];
        return registeredOracles[index];
    }

    /**
     * @dev Get manager configuration
     */
    function getManagerConfig() 
        external 
        view 
        returns (
            ManagerStatus managerStatus,
            bool emergency,
            PriceValidationConfig memory validation,
            bool autoUpdate,
            uint256 autoInterval
        ) 
    {
        return (
            status,
            emergencyMode,
            validationConfig,
            autoUpdateEnabled,
            autoUpdateInterval
        );
    }

    /**
     * @dev Get batch request information
     */
    function getBatchRequest(uint256 batchId) 
        external 
        view 
        returns (BatchUpdateRequest memory) 
    {
        return batchRequests[batchId];
    }

    /**
     * @dev Get system statistics
     */
    function getSystemStats() 
        external 
        view 
        returns (
            uint256 totalOracles,
            uint256 activeOracles,
            uint256 healthyOracles,
            uint256 lastGlobalCheck,
            uint256 totalBatches
        ) 
    {
        uint256 active = 0;
        uint256 healthy = 0;
        
        for (uint256 i = 0; i < registeredOracles.length; i++) {
            if (registeredOracles[i].isActive) active++;
            if (registeredOracles[i].isHealthy) healthy++;
        }
        
        return (
            registeredOracles.length,
            active,
            healthy,
            lastGlobalHealthCheck,
            batchUpdateCounter
        );
    }
} 