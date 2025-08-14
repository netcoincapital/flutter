// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILaxceCore
 * @dev مجموعه تمام interfaces اصلی سیستم LAXCE DEX
 * @notice این interface شامل تمام متدهای اصلی که در Core Layer تعریف می‌شوند
 */

// ==================== ACCESS CONTROL INTERFACE ====================

/**
 * @dev Interface برای AccessControl
 */
interface IAccessControl {
    /// @dev رویدادها
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGrantedWithExpiration(bytes32 indexed role, address indexed account, uint256 expiresAt);
    event RoleExpired(bytes32 indexed role, address indexed account);
    
    /// @dev Functions
    function hasRole(bytes32 role, address account) external view returns (bool);
    function hasValidRole(address account, bytes32 role) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function grantRoleWithExpiration(bytes32 role, address account, uint256 duration) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
    function emergencyPause() external;
    function emergencyUnpause() external;
}

// ==================== PAUSABLE INTERFACE ====================

/**
 * @dev Interface برای Pausable functionality
 */
interface IPausable {
    /// @dev رویدادها
    event Paused(address account);
    event Unpaused(address account);
    
    /// @dev Functions
    function paused() external view returns (bool);
    function pause() external;
    function unpause() external;
}

// ==================== REENTRANCY GUARD INTERFACE ====================

/**
 * @dev Interface برای ReentrancyGuard
 */
interface IReentrancyGuard {
    /// @dev رویدادها
    event ReentrancyStatusChanged(address indexed contract_, uint256 oldStatus, uint256 newStatus);
    event ReentrancyAttemptBlocked(address indexed contract_, address indexed caller);
    
    /// @dev خطاها
    error ReentrancyGuardReentrantCall();
    error ReentrancyGuardNotInitialized();
}

// ==================== CORE SYSTEM INTERFACE ====================

/**
 * @dev Interface اصلی برای Core System
 */
interface ILaxceCore is IAccessControl, IPausable, IReentrancyGuard {
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات سیستم
    struct SystemInfo {
        string version;
        string name;
        address deployer;
        uint256 deploymentTime;
        bool initialized;
        bool paused;
    }
    
    /// @dev اطلاعات Role
    struct RoleInfo {
        bool hasRole;
        bool isValid;
        uint256 grantedAt;
        uint256 expiresAt;
        uint256 remainingTime;
    }
    
    // ==================== EVENTS ====================
    
    event SystemInitialized(address indexed deployer, uint256 timestamp);
    event SystemUpgraded(address indexed upgrader, string oldVersion, string newVersion);
    event EmergencyActionExecuted(address indexed executor, string action, bytes data);
    event ConfigurationUpdated(string key, bytes oldValue, bytes newValue);
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت اطلاعات سیستم
     */
    function getSystemInfo() external view returns (SystemInfo memory);
    
    /**
     * @dev دریافت نسخه سیستم
     */
    function getVersion() external view returns (string memory);
    
    /**
     * @dev بررسی مقداردهی اولیه
     */
    function isInitialized() external view returns (bool);
    
    /**
     * @dev دریافت اطلاعات role
     */
    function getRoleInfo(bytes32 role, address account) external view returns (RoleInfo memory);
    
    /**
     * @dev دریافت تمام roles یک account
     */
    function getAllRoles(address account) external view returns (bytes32[] memory);
    
    /**
     * @dev بررسی دسترسی به function خاص
     */
    function canExecute(address account, bytes4 selector) external view returns (bool);
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev مقداردهی اولیه سیستم
     */
    function initialize() external;
    
    /**
     * @dev به‌روزرسانی پیکربندی
     */
    function updateConfiguration(string calldata key, bytes calldata value) external;
    
    /**
     * @dev ارتقای سیستم
     */
    function upgradeSystem(string calldata newVersion) external;
    
    // ==================== EMERGENCY FUNCTIONS ====================
    
    /**
     * @dev اجرای عملیات اضطراری
     */
    function executeEmergencyAction(string calldata action, bytes calldata data) external;
    
    /**
     * @dev ریست کردن سیستم در شرایط اضطراری
     */
    function emergencyReset() external;
}

// ==================== TOKEN INTERFACE ====================

/**
 * @dev Interface پایه برای Token operations
 */
interface ITokenBase {
    /// @dev رویدادها
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    /// @dev Functions
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ==================== POOL INTERFACE ====================

/**
 * @dev Interface پایه برای Pool operations
 */
interface IPoolBase {
    /// @dev رویدادها
    event PoolCreated(address indexed token0, address indexed token1, uint24 fee, address pool);
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1);
    
    /// @dev Pool info struct
    struct PoolInfo {
        address token0;
        address token1;
        uint24 fee;
        uint256 liquidity;
        uint160 sqrtPriceX96;
        int24 tick;
        bool initialized;
    }
    
    /// @dev Functions
    function getPoolInfo() external view returns (PoolInfo memory);
    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min) external;
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min) external;
    function swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address to) external;
}

// ==================== ORACLE INTERFACE ====================

/**
 * @dev Interface برای Oracle operations
 */
interface IOracleBase {
    /// @dev رویدادها
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event TWAPUpdated(address indexed token, uint256 twap, uint256 period);
    
    /// @dev Price info struct
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
        uint256 blockNumber;
        bool valid;
    }
    
    /// @dev Functions
    function getPrice(address token) external view returns (uint256);
    function getTWAP(address token, uint256 period) external view returns (uint256);
    function getPriceInfo(address token) external view returns (PriceInfo memory);
    function updatePrice(address token, uint256 price) external;
    function isValidPrice(address token, uint256 maxAge) external view returns (bool);
}

// ==================== GOVERNANCE INTERFACE ====================

/**
 * @dev Interface برای Governance operations
 */
interface IGovernanceBase {
    /// @dev رویدادها
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    
    /// @dev Proposal struct
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool canceled;
    }
    
    /// @dev Functions
    function propose(string calldata description, bytes calldata data) external returns (uint256);
    function vote(uint256 proposalId, bool support) external;
    function execute(uint256 proposalId) external;
    function cancel(uint256 proposalId) external;
    function getProposal(uint256 proposalId) external view returns (Proposal memory);
}

// ==================== MAIN LAXCE CORE INTERFACE ====================

/**
 * @dev Interface جامع برای تمام سیستم LAXCE
 */
interface ILaxce is 
    ILaxceCore,
    ITokenBase,
    IPoolBase,
    IOracleBase,
    IGovernanceBase
{
    // ==================== INTEGRATION FUNCTIONS ====================
    
    /**
     * @dev اتصال تمام اجزا
     */
    function connectComponents() external;
    
    /**
     * @dev sync کردن تمام اجزا
     */
    function syncComponents() external;
    
    /**
     * @dev بررسی سلامت کل سیستم
     */
    function healthCheck() external view returns (bool);
    
    /**
     * @dev دریافت آمار کلی سیستم
     */
    function getSystemStats() external view returns (
        uint256 totalPools,
        uint256 totalVolume,
        uint256 totalLiquidity,
        uint256 totalUsers,
        uint256 totalTransactions
    );
}

// ==================== FACTORY INTERFACES ====================

/**
 * @dev Interface برای Factory patterns
 */
interface IFactory {
    event ContractCreated(address indexed creator, address indexed contractAddress, bytes32 salt);
    
    function create(bytes32 salt, bytes calldata bytecode) external returns (address);
    function getAddress(bytes32 salt, bytes calldata bytecode) external view returns (address);
    function isValidContract(address contractAddress) external view returns (bool);
}

/**
 * @dev Interface برای Pool Factory
 */
interface IPoolFactory is IFactory {
    function createPool(address token0, address token1, uint24 fee) external returns (address pool);
    function getPool(address token0, address token1, uint24 fee) external view returns (address);
    function allPoolsLength() external view returns (uint256);
}

// ==================== UTILITY INTERFACES ====================

/**
 * @dev Interface برای Math operations
 */
interface IMath {
    function sqrt(uint256 x) external pure returns (uint256);
    function min(uint256 a, uint256 b) external pure returns (uint256);
    function max(uint256 a, uint256 b) external pure returns (uint256);
    function mulDiv(uint256 a, uint256 b, uint256 denominator) external pure returns (uint256);
}

/**
 * @dev Interface برای Security operations
 */
interface ISecurity {
    function checkSlippage(uint256 expected, uint256 actual, uint256 maxSlippage) external pure returns (bool);
    function validateDeadline(uint256 deadline) external view returns (bool);
    function checkRateLimit(address user, bytes4 selector) external returns (bool);
}

/**
 * @dev Interface برای Events و Monitoring
 */
interface IEvents {
    event SystemEvent(string indexed eventType, address indexed actor, bytes data);
    event SecurityEvent(string indexed eventType, address indexed actor, string reason);
    event PerformanceEvent(string indexed metric, uint256 value, uint256 timestamp);
    
    function emitSystemEvent(string calldata eventType, bytes calldata data) external;
    function emitSecurityEvent(string calldata eventType, string calldata reason) external;
    function emitPerformanceEvent(string calldata metric, uint256 value) external;
}