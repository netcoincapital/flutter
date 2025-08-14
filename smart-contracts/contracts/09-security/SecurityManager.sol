// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../01-core/AccessControl.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/SecurityLib.sol";
import "../libraries/PauseLib.sol";
import "../libraries/Constants.sol";

/**
 * @title SecurityManager
 * @dev مدیریت مرکزی امنیت برای LAXCE DEX
 * @notice هماهنگ‌کننده تمام موارد امنیتی در سراسر DEX
 */
contract SecurityManager is AccessControl {
    
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;
    
    using PauseLib for PauseLib.PauseState;
    using PauseLib for PauseLib.CircuitBreaker;
    using PauseLib for PauseLib.AutoPauseCondition;
    
    // ==================== STORAGE ====================
    
    /// @dev محافظت از reentrancy
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev وضعیت pause کلی سیستم
    PauseLib.PauseState public systemPauseState;
    
    /// @dev Circuit breaker اصلی
    PauseLib.CircuitBreaker public mainCircuitBreaker;
    
    /// @dev شرایط auto-pause مختلف
    mapping(string => PauseLib.AutoPauseCondition) public autoPauseConditions;
    
    /// @dev Rate limiting برای کاربران
    mapping(address => SecurityLib.RateLimit) public rateLimits;
    
    /// @dev Price validation برای pools
    mapping(address => SecurityLib.PriceValidation) public priceValidations;
    
    /// @dev Contracts مجاز برای تعامل
    mapping(address => bool) public authorizedContracts;
    
    /// @dev Emergency contacts
    mapping(address => bool) public emergencyResponders;
    
    /// @dev MEV protection data
    mapping(address => uint256) public lastTxAmounts;
    mapping(address => uint256) public lastTxBlocks;
    
    /// @dev آمار امنیتی
    uint256 public totalSecurityEvents;
    uint256 public totalPauseEvents;
    uint256 public totalCircuitBreakerTriggers;
    
    // ==================== EVENTS ====================
    
    event SecurityEventDetected(
        address indexed source,
        string eventType,
        string description,
        uint256 severity
    );
    
    event ContractAuthorized(address indexed contractAddr, bool authorized);
    event EmergencyResponderAdded(address indexed responder);
    event EmergencyResponderRemoved(address indexed responder);
    event AutoPauseConditionUpdated(string name, uint256 threshold, bool enabled);
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier onlyAuthorizedContract() {
        require(authorizedContracts[msg.sender], "Contract not authorized");
        _;
    }
    
    modifier onlyEmergencyResponder() {
        require(
            emergencyResponders[msg.sender] || hasRole(EMERGENCY_ROLE, msg.sender),
            "Not emergency responder"
        );
        _;
    }
    
    modifier whenSystemNotPaused() {
        systemPauseState.requireNotPaused();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address owner) AccessControl(owner) {
        // Initialize reentrancy guard
        _reentrancyGuard.initialize();
        
        // Initialize main circuit breaker
        mainCircuitBreaker.initCircuitBreaker(5, 1 hours); // 5 triggers per hour
        
        // Initialize auto-pause conditions
        _initializeAutoPauseConditions();
        
        // Add owner as emergency responder
        emergencyResponders[owner] = true;
    }
    
    function _initializeAutoPauseConditions() internal {
                // Large price deviation
        autoPauseConditions["PRICE_DEVIATION"].configureAutoPause(
            "PRICE_DEVIATION",
            2500, // 25% price change
            true,
            30 minutes
        );
        
        // Unusual volume spike
        autoPauseConditions["VOLUME_SPIKE"].configureAutoPause(
            "VOLUME_SPIKE",
            1e24, // 1M USD equivalent (1e18 * 1e6)
            true,
            15 minutes
        );
        
        // Low liquidity warning
        autoPauseConditions["LOW_LIQUIDITY"].configureAutoPause(
            "LOW_LIQUIDITY",
            1e22, // 10K USD minimum (1e18 * 1e4)
            true,
            5 minutes
        );
    }
    
    // ==================== PAUSE MANAGEMENT ====================
    
    /**
     * @dev Emergency pause کل سیستم
     */
    function emergencyPauseSystem(string calldata reason) 
        external 
        onlyEmergencyResponder 
        nonReentrant 
    {
        systemPauseState.emergencyPause(msg.sender, reason);
        totalPauseEvents++;
        
        _emitSecurityEvent("EMERGENCY_PAUSE", reason, 10); // Highest severity
    }
    
    /**
     * @dev Timed pause کل سیستم
     */
    function timedPauseSystem(string calldata reason, uint256 duration)
        external
        onlyEmergencyResponder
        nonReentrant
    {
        systemPauseState.timedPause(msg.sender, reason, duration);
        totalPauseEvents++;
        
        _emitSecurityEvent("TIMED_PAUSE", reason, 8);
    }
    
    /**
     * @dev Unpause کل سیستم
     */
    function unpauseSystem() external onlyEmergencyResponder nonReentrant {
        systemPauseState.emergencyUnpause(msg.sender);
        
        _emitSecurityEvent("SYSTEM_UNPAUSED", "System resumed", 5);
    }
    
    // ==================== CIRCUIT BREAKER ====================
    
    /**
     * @dev Trigger circuit breaker manually
     */
    function triggerCircuitBreaker(string calldata reason) 
        external 
        onlyAuthorizedContract 
        returns (bool) 
    {
        bool paused = mainCircuitBreaker.triggerCircuitBreaker(
            systemPauseState, 
            reason
        );
        
        totalCircuitBreakerTriggers++;
        
        if (paused) {
            _emitSecurityEvent("CIRCUIT_BREAKER_PAUSE", reason, 9);
        } else {
            _emitSecurityEvent("CIRCUIT_BREAKER_TRIGGER", reason, 6);
        }
        
        return paused;
    }
    
    // ==================== VALIDATION FUNCTIONS ====================
    
    /**
     * @dev اعتبارسنجی slippage
     */
    function validateSlippage(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 amountOutMax,
        uint256 actualAmountOut,
        uint256 maxSlippageBps
    ) external view whenSystemNotPaused {
        SecurityLib.SlippageParams memory params = SecurityLib.SlippageParams({
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            amountOutMax: amountOutMax,
            maxSlippageBps: maxSlippageBps
        });
        
        SecurityLib.validateSlippage(params, actualAmountOut);
    }
    
    /**
     * @dev اعتبارسنجی swap parameters
     */
    function validateSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external view whenSystemNotPaused {
        SecurityLib.validateSwapParams(tokenIn, tokenOut, amountIn, amountOutMin, to);
    }
    
    /**
     * @dev بررسی rate limiting
     */
    function checkUserRateLimit(address user) external whenSystemNotPaused {
        SecurityLib.checkRateLimit(
            rateLimits,
            user,
            10, // 10 calls per window
            1 minutes
        );
    }
    
    /**
     * @dev اعتبارسنجی token
     */
    function validateToken(address token) external view returns (bool) {
        return SecurityLib.validateToken(token);
    }
    
    // ==================== PRICE PROTECTION ====================
    
    /**
     * @dev Validate price change
     */
    function validatePriceChange(
        address pool,
        uint256 newPrice
    ) external onlyAuthorizedContract {
        SecurityLib.validatePriceChange(
            priceValidations[pool],
            newPrice,
            2500 // 25% max deviation
        );
    }
    
    // ==================== MEV PROTECTION ====================
    
    /**
     * @dev Check for sandwich attacks
     */
    function checkSandwichAttack(
        address user,
        uint256 amountIn,
        uint256 amountOut
    ) external onlyAuthorizedContract whenSystemNotPaused {
        SecurityLib.detectSandwichAttack(
            user,
            amountIn,
            amountOut,
            lastTxAmounts,
            lastTxBlocks
        );
        
        // Update tracking
        lastTxAmounts[user] = amountIn;
        lastTxBlocks[user] = block.number;
    }
    
    // ==================== FLASH LOAN PROTECTION ====================
    
    /**
     * @dev Check for flash loan attacks
     */
    function checkFlashLoan(
        address token,
        uint256 balanceBefore
    ) external view onlyAuthorizedContract {
        SecurityLib.requireNoFlashLoan(token, balanceBefore);
    }
    
    // ==================== POOL HEALTH ====================
    
    /**
     * @dev Validate pool health
     */
    function validatePoolHealth(
        uint256 reserve0,
        uint256 reserve1,
        uint256 withdrawAmount0,
        uint256 withdrawAmount1
    ) external view onlyAuthorizedContract whenSystemNotPaused {
        SecurityLib.validatePoolHealth(
            reserve0,
            reserve1,
            withdrawAmount0,
            withdrawAmount1,
            1000 // Minimum 1000 wei liquidity
        );
    }
    
    // ==================== AUTO-PAUSE MONITORING ====================
    
    /**
     * @dev Monitor pool for auto-pause conditions
     */
    function monitorPool(
        address pool,
        uint256 volume24h,
        uint256 tvl,
        uint256 priceChange
    ) external onlyAuthorizedContract {
        // Check volume spike
        autoPauseConditions["VOLUME_SPIKE"].checkAutoPause(
            volume24h,
            systemPauseState
        );
        
        // Check low liquidity
        autoPauseConditions["LOW_LIQUIDITY"].checkAutoPause(
            tvl,
            systemPauseState
        );
        
        // Check price deviation
        autoPauseConditions["PRICE_DEVIATION"].checkAutoPause(
            priceChange,
            systemPauseState
        );
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev Authorize contract
     */
    function authorizeContract(address contractAddr, bool authorized) 
        external 
        onlyAdmin 
    {
        authorizedContracts[contractAddr] = authorized;
        emit ContractAuthorized(contractAddr, authorized);
    }
    
    /**
     * @dev Add emergency responder
     */
    function addEmergencyResponder(address responder) external onlyOwner {
        emergencyResponders[responder] = true;
        emit EmergencyResponderAdded(responder);
    }
    
    /**
     * @dev Remove emergency responder
     */
    function removeEmergencyResponder(address responder) external onlyOwner {
        emergencyResponders[responder] = false;
        emit EmergencyResponderRemoved(responder);
    }
    
    /**
     * @dev Configure circuit breaker
     */
    function configureCircuitBreaker(
        uint256 maxTriggers,
        uint256 windowDuration,
        bool isActive
    ) external onlyAdmin {
        mainCircuitBreaker.configureCircuitBreaker(maxTriggers, windowDuration, isActive);
    }
    
    /**
     * @dev Configure auto-pause condition
     */
    function configureAutoPause(
        string calldata name,
        uint256 threshold,
        bool isEnabled,
        uint256 cooldownPeriod
    ) external onlyAdmin {
        autoPauseConditions[name].configureAutoPause(
            name,
            threshold,
            isEnabled,
            cooldownPeriod
        );
        
        emit AutoPauseConditionUpdated(name, threshold, isEnabled);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev Get system pause info
     */
    function getSystemPauseInfo() 
        external 
        view 
        returns (
            bool isPaused,
            uint256 pausedAt,
            address pausedBy,
            string memory reason,
            uint256 timeUntilUnpause
        ) 
    {
        return systemPauseState.getPauseInfo();
    }
    
    /**
     * @dev Get circuit breaker stats
     */
    function getCircuitBreakerStats()
        external
        view
        returns (
            uint256 triggerCount,
            uint256 maxTriggers,
            uint256 windowTimeLeft,
            bool isActive
        )
    {
        return mainCircuitBreaker.getCircuitBreakerStats();
    }
    
    /**
     * @dev Get security statistics
     */
    function getSecurityStats()
        external
        view
        returns (
            uint256 totalEvents,
            uint256 totalPauses,
            uint256 totalCircuitBreakers,
            bool systemPaused
        )
    {
        return (
            totalSecurityEvents,
            totalPauseEvents,
            totalCircuitBreakerTriggers,
            systemPauseState.isPaused
        );
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev Emit security event
     */
    function _emitSecurityEvent(
        string memory eventType,
        string memory description,
        uint256 severity
    ) internal {
        totalSecurityEvents++;
        
        emit SecurityEventDetected(
            msg.sender,
            eventType,
            description,
            severity
        );
    }
} 