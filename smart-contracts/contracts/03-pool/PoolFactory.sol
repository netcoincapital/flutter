// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../libraries/Constants.sol";

/**
 * @title PoolFactory
 * @dev Factory برای ایجاد و مدیریت pools
 * @notice این کانترکت تمام pools را ایجاد و track می‌کند
 */
contract PoolFactory is Pausable {
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد pools
    uint256 public constant MAX_POOLS = 100000;
    
    /// @dev حداقل tick spacing
    int24 public constant MIN_TICK_SPACING = 1;
    
    /// @dev حداکثر tick spacing
    int24 public constant MAX_TICK_SPACING = 16384;
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات pool
    struct PoolInfo {
        address token0;                 // آدرس توکن اول
        address token1;                 // آدرس توکن دوم
        uint24 fee;                     // کارمزد pool
        int24 tickSpacing;              // فاصله tick
        address pool;                   // آدرس pool
        uint256 createdAt;              // زمان ایجاد
        bool active;                    // وضعیت فعال
        uint256 liquidity;              // کل نقدینگی
        uint256 volume24h;              // حجم 24 ساعته
        uint256 fees24h;                // کارمزد 24 ساعته
    }
    
    /// @dev تنظیمات fee tier
    struct FeeTier {
        uint24 fee;                     // کارمزد
        int24 tickSpacing;              // فاصله tick
        bool enabled;                   // فعال بودن
        string description;             // توضیحات
    }
    
    /// @dev پارامترهای deployment
    struct PoolDeploymentParams {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev mapping از fee به tick spacing
    mapping(uint24 => int24) public feeAmountTickSpacing;
    
    /// @dev mapping pools (token0 => token1 => fee => pool)
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
    
    /// @dev لیست تمام pools
    address[] public allPools;
    
    /// @dev mapping اطلاعات pools
    mapping(address => PoolInfo) public poolInfo;
    
    /// @dev token registry
    TokenRegistry public tokenRegistry;
    
    /// @dev fee tiers
    mapping(uint24 => FeeTier) public feeTiers;
    
    /// @dev لیست fee tiers
    uint24[] public allFeeTiers;
    
    /// @dev owner pools
    address public owner;
    
    /// @dev پارامترهای deployment فعلی
    PoolDeploymentParams public parameters;
    
    /// @dev آیا whitelisted pools فقط
    bool public whitelistMode = false;
    
    /// @dev mapping pools whitelisted
    mapping(address => bool) public whitelistedTokens;
    
    // ==================== EVENTS ====================
    
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool,
        uint256 poolCount
    );
    
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);
    event FeeAmountDisabled(uint24 indexed fee);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event TokenRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event WhitelistModeToggled(bool enabled);
    event TokenWhitelisted(address indexed token, bool whitelisted);
    event PoolStatusUpdated(address indexed pool, bool active);
    
    // ==================== ERRORS ====================
    
    error Factory__IdenticalAddresses();
    error Factory__ZeroAddress();
    error Factory__PoolExists();
    error Factory__FeeNotEnabled();
    error Factory__InvalidTickSpacing();
    error Factory__MaxPoolsReached();
    error Factory__TokenNotWhitelisted();
    error Factory__PoolNotExists();
    error Factory__Unauthorized();
    error Factory__InvalidFee();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address _tokenRegistry) {
        if (_tokenRegistry == address(0)) revert Factory__ZeroAddress();
        
        owner = msg.sender;
        tokenRegistry = TokenRegistry(_tokenRegistry);
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
        
        // تنظیم fee tiers پیش‌فرض
        _setupDefaultFeeTiers();
    }
    
    // ==================== POOL CREATION ====================
    
    /**
     * @dev ایجاد pool جدید
     * @param tokenA آدرس توکن اول
     * @param tokenB آدرس توکن دوم
     * @param fee کارمزد pool
     * @return pool آدرس pool ایجاد شده
     */
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external nonReentrant whenNotPaused returns (address pool) {
        if (tokenA == tokenB) revert Factory__IdenticalAddresses();
        
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert Factory__ZeroAddress();
        
        int24 tickSpacing = feeAmountTickSpacing[fee];
        if (tickSpacing == 0) revert Factory__FeeNotEnabled();
        
        if (getPool[token0][token1][fee] != address(0)) revert Factory__PoolExists();
        if (allPools.length >= MAX_POOLS) revert Factory__MaxPoolsReached();
        
        // بررسی whitelist در صورت فعال بودن
        if (whitelistMode) {
            if (!whitelistedTokens[token0] || !whitelistedTokens[token1]) {
                revert Factory__TokenNotWhitelisted();
            }
        }
        
        // بررسی token registry
        if (address(tokenRegistry) != address(0)) {
            require(tokenRegistry.isTokenUsable(token0), "Token0 not usable");
            require(tokenRegistry.isTokenUsable(token1), "Token1 not usable");
        }
        
        // تنظیم پارامترهای deployment
        parameters = PoolDeploymentParams({
            factory: address(this),
            token0: token0,
            token1: token1,
            fee: fee,
            tickSpacing: tickSpacing
        });
        
        // ایجاد pool با Create2
        bytes32 salt = keccak256(abi.encode(token0, token1, fee));
        pool = Create2.deploy(0, salt, type(LaxcePool).creationCode);
        
        // پاک کردن parameters
        delete parameters;
        
        // ثبت pool
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // populate mapping in the reverse direction
        allPools.push(pool);
        
        // ثبت اطلاعات pool
        poolInfo[pool] = PoolInfo({
            token0: token0,
            token1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            pool: pool,
            createdAt: block.timestamp,
            active: true,
            liquidity: 0,
            volume24h: 0,
            fees24h: 0
        });
        
        emit PoolCreated(token0, token1, fee, tickSpacing, pool, allPools.length);
    }
    
    // ==================== FEE MANAGEMENT ====================
    
    /**
     * @dev فعال کردن fee amount
     * @param fee مقدار کارمزد
     * @param tickSpacing فاصله tick
     */
    function enableFeeAmount(uint24 fee, int24 tickSpacing) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (fee >= 1000000) revert Factory__InvalidFee();
        if (tickSpacing <= 0 || tickSpacing > MAX_TICK_SPACING) {
            revert Factory__InvalidTickSpacing();
        }
        if (feeAmountTickSpacing[fee] != 0) revert Factory__FeeNotEnabled();
        
        feeAmountTickSpacing[fee] = tickSpacing;
        
        // اضافه کردن به fee tiers
        feeTiers[fee] = FeeTier({
            fee: fee,
            tickSpacing: tickSpacing,
            enabled: true,
            description: _getFeeDescription(fee)
        });
        
        allFeeTiers.push(fee);
        
        emit FeeAmountEnabled(fee, tickSpacing);
    }
    
    /**
     * @dev غیرفعال کردن fee amount
     * @param fee مقدار کارمزد
     */
    function disableFeeAmount(uint24 fee) external onlyValidRole(ADMIN_ROLE) {
        if (feeAmountTickSpacing[fee] == 0) revert Factory__FeeNotEnabled();
        
        delete feeAmountTickSpacing[fee];
        feeTiers[fee].enabled = false;
        
        // حذف از لیست
        for (uint256 i = 0; i < allFeeTiers.length; i++) {
            if (allFeeTiers[i] == fee) {
                allFeeTiers[i] = allFeeTiers[allFeeTiers.length - 1];
                allFeeTiers.pop();
                break;
            }
        }
        
        emit FeeAmountDisabled(fee);
    }
    
    // ==================== WHITELIST MANAGEMENT ====================
    
    /**
     * @dev تنظیم وضعیت whitelist mode
     * @param enabled فعال یا غیرفعال
     */
    function setWhitelistMode(bool enabled) external onlyValidRole(ADMIN_ROLE) {
        whitelistMode = enabled;
        emit WhitelistModeToggled(enabled);
    }
    
    /**
     * @dev whitelist کردن token
     * @param token آدرس توکن
     * @param whitelisted وضعیت whitelist
     */
    function setTokenWhitelist(address token, bool whitelisted) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (token == address(0)) revert Factory__ZeroAddress();
        
        whitelistedTokens[token] = whitelisted;
        emit TokenWhitelisted(token, whitelisted);
    }
    
    /**
     * @dev whitelist کردن چندین token
     * @param tokens لیست آدرس توکن‌ها
     * @param whitelisted وضعیت whitelist
     */
    function setTokenWhitelistBatch(address[] calldata tokens, bool whitelisted) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != address(0)) {
                whitelistedTokens[tokens[i]] = whitelisted;
                emit TokenWhitelisted(tokens[i], whitelisted);
            }
        }
    }
    
    // ==================== POOL MANAGEMENT ====================
    
    /**
     * @dev تنظیم وضعیت pool
     * @param pool آدرس pool
     * @param active وضعیت فعال
     */
    function setPoolStatus(address pool, bool active) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (poolInfo[pool].pool == address(0)) revert Factory__PoolNotExists();
        
        poolInfo[pool].active = active;
        emit PoolStatusUpdated(pool, active);
    }
    
    /**
     * @dev به‌روزرسانی آمار pool
     * @param pool آدرس pool
     * @param liquidity نقدینگی جدید
     * @param volume24h حجم 24 ساعته
     * @param fees24h کارمزد 24 ساعته
     */
    function updatePoolStats(
        address pool,
        uint256 liquidity,
        uint256 volume24h,
        uint256 fees24h
    ) external onlyValidRole(OPERATOR_ROLE) {
        if (poolInfo[pool].pool == address(0)) revert Factory__PoolNotExists();
        
        PoolInfo storage info = poolInfo[pool];
        info.liquidity = liquidity;
        info.volume24h = volume24h;
        info.fees24h = fees24h;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم owner
     * @param _owner owner جدید
     */
    function setOwner(address _owner) external onlyOwner {
        if (_owner == address(0)) revert Factory__ZeroAddress();
        
        address oldOwner = owner;
        owner = _owner;
        
        emit OwnerChanged(oldOwner, _owner);
    }
    
    /**
     * @dev تنظیم token registry
     * @param _tokenRegistry آدرس registry جدید
     */
    function setTokenRegistry(address _tokenRegistry) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        address oldRegistry = address(tokenRegistry);
        tokenRegistry = TokenRegistry(_tokenRegistry);
        
        emit TokenRegistryUpdated(oldRegistry, _tokenRegistry);
    }
    
    /**
     * @dev pause کردن factory
     */
    function pause() external onlyValidRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev unpause کردن factory
     */
    function unpause() external onlyValidRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت تعداد کل pools
     * @return تعداد pools
     */
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }
    
    /**
     * @dev دریافت لیست pools برای یک جفت توکن
     * @param tokenA آدرس توکن اول
     * @param tokenB آدرس توکن دوم
     * @return pools لیست آدرس pools
     */
    function getPoolsForPair(address tokenA, address tokenB) 
        external 
        view 
        returns (address[] memory pools) 
    {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        uint256 count = 0;
        for (uint256 i = 0; i < allFeeTiers.length; i++) {
            uint24 fee = allFeeTiers[i];
            if (getPool[token0][token1][fee] != address(0)) {
                count++;
            }
        }
        
        pools = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allFeeTiers.length; i++) {
            uint24 fee = allFeeTiers[i];
            address pool = getPool[token0][token1][fee];
            if (pool != address(0)) {
                pools[index] = pool;
                index++;
            }
        }
    }
    
    /**
     * @dev دریافت pools فعال
     * @param offset شروع از
     * @param limit حداکثر تعداد
     * @return pools لیست pools فعال
     */
    function getActivePools(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory pools) 
    {
        require(offset < allPools.length, "Offset out of bounds");
        
        uint256 end = offset.add(limit);
        if (end > allPools.length) {
            end = allPools.length;
        }
        
        uint256 count = 0;
        for (uint256 i = offset; i < end; i++) {
            if (poolInfo[allPools[i]].active) {
                count++;
            }
        }
        
        pools = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = offset; i < end; i++) {
            if (poolInfo[allPools[i]].active) {
                pools[index] = allPools[i];
                index++;
            }
        }
    }
    
    /**
     * @dev دریافت fee tiers فعال
     * @return لیست fee tiers
     */
    function getEnabledFeeTiers() external view returns (FeeTier[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < allFeeTiers.length; i++) {
            if (feeTiers[allFeeTiers[i]].enabled) {
                count++;
            }
        }
        
        FeeTier[] memory tiers = new FeeTier[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allFeeTiers.length; i++) {
            uint24 fee = allFeeTiers[i];
            if (feeTiers[fee].enabled) {
                tiers[index] = feeTiers[fee];
                index++;
            }
        }
        
        return tiers;
    }
    
    /**
     * @dev دریافت آمار کلی factory
     * @return آمار کامل
     */
    function getFactoryStats() external view returns (
        uint256 totalPools,
        uint256 activePools,
        uint256 totalLiquidity,
        uint256 totalVolume24h,
        uint256 totalFees24h,
        uint256 enabledFeeTiers
    ) {
        totalPools = allPools.length;
        enabledFeeTiers = allFeeTiers.length;
        
        for (uint256 i = 0; i < allPools.length; i++) {
            PoolInfo memory info = poolInfo[allPools[i]];
            if (info.active) {
                activePools++;
                totalLiquidity = totalLiquidity.add(info.liquidity);
                totalVolume24h = totalVolume24h.add(info.volume24h);
                totalFees24h = totalFees24h.add(info.fees24h);
            }
        }
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev تنظیم fee tiers پیش‌فرض
     */
    function _setupDefaultFeeTiers() internal {
        // 0.05% = 500
        feeAmountTickSpacing[500] = 10;
        feeTiers[500] = FeeTier({
            fee: 500,
            tickSpacing: 10,
            enabled: true,
            description: "0.05% - Very Low"
        });
        allFeeTiers.push(500);
        
        // 0.3% = 3000
        feeAmountTickSpacing[3000] = 60;
        feeTiers[3000] = FeeTier({
            fee: 3000,
            tickSpacing: 60,
            enabled: true,
            description: "0.3% - Low"
        });
        allFeeTiers.push(3000);
        
        // 1% = 10000
        feeAmountTickSpacing[10000] = 200;
        feeTiers[10000] = FeeTier({
            fee: 10000,
            tickSpacing: 200,
            enabled: true,
            description: "1% - Medium"
        });
        allFeeTiers.push(10000);
    }
    
    /**
     * @dev دریافت توضیحات fee
     * @param fee مقدار کارمزد
     * @return توضیحات
     */
    function _getFeeDescription(uint24 fee) internal pure returns (string memory) {
        if (fee <= 500) return "Ultra Low";
        if (fee <= 3000) return "Low";
        if (fee <= 10000) return "Medium";
        return "High";
    }
} 