// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../01-core/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title LPToken
 * @dev توکن LP برای ارائه‌دهندگان نقدینگی با قابلیت‌های mining و rewards
 * @notice این توکن برای مدیریت LP positions و توزیع rewards استفاده می‌شود
 */
contract LPToken is 
    ERC20, 
    ERC20Burnable, 
    Pausable, 
    LaxceAccessControl 
{
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر supply برای LP Token
    uint256 public constant MAX_SUPPLY = type(uint256).max;
    
    /// @dev حداقل مقدار liquidity
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    
    /// @dev کارمزد withdraw پیش‌فرض (0.5%)
    uint256 public constant DEFAULT_WITHDRAW_FEE = 500; // 0.5%
    
    /// @dev حداکثر کارمزد withdraw (2%)
    uint256 public constant MAX_WITHDRAW_FEE = 2000; // 2%
    
    /// @dev مدت زمان پیش‌فرض برای LP mining (30 روز)
    uint256 public constant DEFAULT_MINING_PERIOD = 30 days;
    
    /// @dev حداکثر trading mining multiplier (5x)
    uint256 public constant MAX_TRADING_MULTIPLIER = 50000; // 5x
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات LP mining
    struct MiningInfo {
        uint256 amount;             // مقدار LP staked
        uint256 startTime;          // زمان شروع mining
        uint256 endTime;            // زمان پایان mining
        uint256 rewardDebt;         // بدهی reward محاسبه شده
        uint256 multiplier;         // ضریب پاداش
        bool active;                // وضعیت فعال بودن
    }
    
    /// @dev اطلاعات pool
    struct PoolInfo {
        address token0;             // آدرس توکن اول
        address token1;             // آدرس توکن دوم
        uint24 fee;                 // کارمزد pool
        uint256 totalLiquidity;     // کل نقدینگی
        uint256 accRewardPerShare;  // تجمعی reward per share
        uint256 lastRewardTime;     // آخرین زمان محاسبه reward
        uint256 allocPoint;         // نقطه allocation برای reward
        bool active;                // وضعیت فعال بودن pool
    }
    
    /// @dev اطلاعات trading mining
    struct TradingMiningInfo {
        uint256 totalVolume;        // کل حجم trading
        uint256 rewardEarned;       // reward کسب شده
        uint256 lastTradeTime;      // آخرین زمان trade
        uint256 multiplier;         // ضریب فعلی
    }
    
    /// @dev اطلاعات کارمزد withdraw
    struct WithdrawFeeInfo {
        uint256 feeRate;            // نرخ کارمزد
        uint256 collectedFees;      // کارمزدهای جمع‌آوری شده
        address feeRecipient;       // دریافت‌کننده کارمزد
        bool enabled;               // فعال بودن
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس pool مربوطه
    address public pool;
    
    /// @dev آدرس LAXCE token
    IERC20 public laxceToken;
    
    /// @dev mapping برای LP mining
    mapping(address => MiningInfo) public lpMining;
    
    /// @dev mapping برای trading mining
    mapping(address => TradingMiningInfo) public tradingMining;
    
    /// @dev اطلاعات pool
    PoolInfo public poolInfo;
    
    /// @dev اطلاعات کارمزد withdraw
    WithdrawFeeInfo public withdrawFeeInfo;
    
    /// @dev کل reward per second برای LP mining
    uint256 public rewardPerSecond;
    
    /// @dev کل supply staked شده
    uint256 public totalStaked;
    
    /// @dev pool reward برای توزیع
    uint256 public rewardPool;
    
    /// @dev آیا trading mining فعال است
    bool public tradingMiningEnabled = true;
    
    /// @dev حداقل volume برای trading mining
    uint256 public minTradingVolume = 1000 * Constants.DECIMAL_BASE;
    
    /// @dev آدرس factory
    address public factory;
    
    /// @dev آدرس router
    address public router;
    
    // ==================== EVENTS ====================
    
    event LiquidityAdded(address indexed provider, uint256 amount, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 lpTokens);
    event MiningStarted(address indexed user, uint256 amount, uint256 duration);
    event MiningEnded(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TradingMiningReward(address indexed user, uint256 volume, uint256 reward);
    event WithdrawFeeCollected(address indexed user, uint256 fee);
    event PoolInfoUpdated(address token0, address token1, uint24 fee);
    event RewardPerSecondUpdated(uint256 oldRate, uint256 newRate);
    event TradingMiningToggled(bool enabled);
    event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
    
    // ==================== ERRORS ====================
    
    error LPToken__InvalidPool();
    error LPToken__InsufficientLiquidity();
    error LPToken__MiningNotActive();
    error LPToken__MiningAlreadyActive();
    error LPToken__InsufficientStaked();
    error LPToken__ZeroAmount();
    error LPToken__ZeroAddress();
    error LPToken__InvalidFeeRate();
    error LPToken__PoolNotActive();
    error LPToken__InsufficientRewards();
    error LPToken__TradingMiningDisabled();
    error LPToken__BelowMinVolume();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validAddress(address addr) {
        if (addr == address(0)) revert LPToken__ZeroAddress();
        _;
    }
    
    modifier onlyPoolOrRouter() {
        require(msg.sender == pool || msg.sender == router, "Not authorized");
        _;
    }
    
    modifier poolActive() {
        if (!poolInfo.active) revert LPToken__PoolNotActive();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        string memory name,
        string memory symbol,
        address _pool,
        address _token0,
        address _token1,
        uint24 _fee,
        address _laxceToken,
        address _factory,
        address _router
    ) 
        ERC20(name, symbol) 
        validAddress(_pool)
        validAddress(_token0)
        validAddress(_token1)
        validAddress(_laxceToken)
        validAddress(_factory)
        validAddress(_router)
    {
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
        
        // تنظیم آدرس‌ها
        pool = _pool;
        laxceToken = IERC20(_laxceToken);
        factory = _factory;
        router = _router;
        
        // تنظیم اطلاعات pool
        poolInfo = PoolInfo({
            token0: _token0,
            token1: _token1,
            fee: _fee,
            totalLiquidity: 0,
            accRewardPerShare: 0,
            lastRewardTime: block.timestamp,
            allocPoint: 1000, // پیش‌فرض
            active: true
        });
        
        // تنظیم withdraw fee
        withdrawFeeInfo = WithdrawFeeInfo({
            feeRate: DEFAULT_WITHDRAW_FEE,
            collectedFees: 0,
            feeRecipient: msg.sender,
            enabled: true
        });
        
        // تنظیم reward rate پیش‌فرض (1 LAXCE per second)
        rewardPerSecond = 1 * Constants.DECIMAL_BASE;
    }
    
    // ==================== LP MINING FUNCTIONS ====================
    
    /**
     * @dev شروع LP mining
     * @param amount مقدار LP token برای stake
     * @param duration مدت زمان mining
     */
    function startMining(
        uint256 amount,
        uint256 duration
    ) external nonReentrant whenNotPaused poolActive {
        if (amount == 0) revert LPToken__ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert LPToken__InsufficientLiquidity();
        if (lpMining[msg.sender].active) revert LPToken__MiningAlreadyActive();
        if (duration < 1 days) revert LPToken__ZeroAmount();
        
        // محاسبه multiplier بر اساس duration
        uint256 multiplier = _calculateMiningMultiplier(duration);
        
        // به‌روزرسانی pool
        _updatePool();
        
        // تنظیم mining info
        lpMining[msg.sender] = MiningInfo({
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp.add(duration),
            rewardDebt: amount.mul(poolInfo.accRewardPerShare).div(Constants.DECIMAL_BASE),
            multiplier: multiplier,
            active: true
        });
        
        // انتقال LP tokens
        _transfer(msg.sender, address(this), amount);
        totalStaked = totalStaked.add(amount);
        
        emit MiningStarted(msg.sender, amount, duration);
    }
    
    /**
     * @dev پایان LP mining و دریافت rewards
     */
    function endMining() external nonReentrant {
        MiningInfo storage info = lpMining[msg.sender];
        
        if (!info.active) revert LPToken__MiningNotActive();
        if (block.timestamp < info.endTime) revert LPToken__MiningNotActive();
        
        // به‌روزرسانی pool
        _updatePool();
        
        // محاسبه rewards
        uint256 pending = info.amount
            .mul(poolInfo.accRewardPerShare)
            .div(Constants.DECIMAL_BASE)
            .sub(info.rewardDebt);
        
        // اعمال multiplier
        uint256 rewards = pending.mul(info.multiplier).div(Constants.FEE_BASE);
        
        // برگرداندن LP tokens
        _transfer(address(this), msg.sender, info.amount);
        totalStaked = totalStaked.sub(info.amount);
        
        // پرداخت rewards
        if (rewards > 0 && rewardPool >= rewards) {
            rewardPool = rewardPool.sub(rewards);
            laxceToken.transfer(msg.sender, rewards);
        }
        
        // پاک کردن mining info
        delete lpMining[msg.sender];
        
        emit MiningEnded(msg.sender, info.amount, rewards);
    }
    
    /**
     * @dev دریافت pending rewards
     * @param user آدرس کاربر
     * @return مقدار pending rewards
     */
    function getPendingRewards(address user) external view returns (uint256) {
        MiningInfo storage info = lpMining[user];
        
        if (!info.active) return 0;
        
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        
        if (block.timestamp > poolInfo.lastRewardTime && totalStaked > 0) {
            uint256 timeElapsed = block.timestamp.sub(poolInfo.lastRewardTime);
            uint256 reward = timeElapsed.mul(rewardPerSecond);
            accRewardPerShare = accRewardPerShare.add(
                reward.mul(Constants.DECIMAL_BASE).div(totalStaked)
            );
        }
        
        uint256 pending = info.amount
            .mul(accRewardPerShare)
            .div(Constants.DECIMAL_BASE)
            .sub(info.rewardDebt);
        
        return pending.mul(info.multiplier).div(Constants.FEE_BASE);
    }
    
    // ==================== TRADING MINING FUNCTIONS ====================
    
    /**
     * @dev ثبت trading volume برای mining
     * @param user آدرس trader
     * @param volume حجم trade
     */
    function recordTradingVolume(
        address user,
        uint256 volume
    ) external onlyPoolOrRouter {
        if (!tradingMiningEnabled) return;
        if (volume < minTradingVolume) return;
        
        TradingMiningInfo storage info = tradingMining[user];
        
        // به‌روزرسانی آمار
        info.totalVolume = info.totalVolume.add(volume);
        info.lastTradeTime = block.timestamp;
        
        // محاسبه multiplier بر اساس حجم
        uint256 newMultiplier = _calculateTradingMultiplier(info.totalVolume);
        info.multiplier = newMultiplier;
        
        // محاسبه reward
        uint256 baseReward = volume.div(10000); // 0.01% از volume
        uint256 reward = baseReward.mul(newMultiplier).div(Constants.FEE_BASE);
        
        if (reward > 0 && rewardPool >= reward) {
            info.rewardEarned = info.rewardEarned.add(reward);
            rewardPool = rewardPool.sub(reward);
            
            // پرداخت فوری reward
            laxceToken.transfer(user, reward);
            
            emit TradingMiningReward(user, volume, reward);
        }
    }
    
    /**
     * @dev دریافت اطلاعات trading mining
     * @param user آدرس کاربر
     * @return اطلاعات trading mining
     */
    function getTradingMiningInfo(address user) 
        external 
        view 
        returns (TradingMiningInfo memory) 
    {
        return tradingMining[user];
    }
    
    // ==================== LIQUIDITY FUNCTIONS ====================
    
    /**
     * @dev mint LP tokens هنگام اضافه کردن liquidity
     * @param to آدرس دریافت‌کننده
     * @param amount مقدار LP tokens
     */
    function mint(address to, uint256 amount) 
        external 
        onlyPoolOrRouter 
        validAddress(to) 
    {
        if (amount == 0) revert LPToken__ZeroAmount();
        
        // به‌روزرسانی total liquidity
        poolInfo.totalLiquidity = poolInfo.totalLiquidity.add(amount);
        
        _mint(to, amount);
        
        emit LiquidityAdded(to, amount, amount);
    }
    
    /**
     * @dev burn LP tokens هنگام حذف liquidity
     * @param from آدرس دارنده
     * @param amount مقدار LP tokens
     */
    function burn(address from, uint256 amount) 
        external 
        onlyPoolOrRouter 
        validAddress(from) 
    {
        if (amount == 0) revert LPToken__ZeroAmount();
        if (balanceOf(from) < amount) revert LPToken__InsufficientLiquidity();
        
        // محاسبه withdraw fee
        uint256 fee = 0;
        if (withdrawFeeInfo.enabled) {
            fee = amount.mul(withdrawFeeInfo.feeRate).div(Constants.FEE_BASE);
            
            if (fee > 0) {
                // انتقال fee
                _transfer(from, withdrawFeeInfo.feeRecipient, fee);
                withdrawFeeInfo.collectedFees = withdrawFeeInfo.collectedFees.add(fee);
                
                emit WithdrawFeeCollected(from, fee);
            }
        }
        
        // burn مقدار اصلی منهای fee
        uint256 burnAmount = amount.sub(fee);
        
        // به‌روزرسانی total liquidity
        poolInfo.totalLiquidity = poolInfo.totalLiquidity.sub(burnAmount);
        
        _burn(from, burnAmount);
        
        emit LiquidityRemoved(from, burnAmount, amount);
    }
    
    // ==================== REWARD FUNCTIONS ====================
    
    /**
     * @dev افزودن reward به pool
     * @param amount مقدار reward
     */
    function addReward(uint256 amount) 
        external 
        onlyValidRole(TREASURY_ROLE) 
    {
        if (amount == 0) revert LPToken__ZeroAmount();
        
        laxceToken.transferFrom(msg.sender, address(this), amount);
        rewardPool = rewardPool.add(amount);
    }
    
    /**
     * @dev تنظیم reward per second
     * @param newRate نرخ جدید
     */
    function setRewardPerSecond(uint256 newRate) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        // به‌روزرسانی pool قبل از تغییر
        _updatePool();
        
        uint256 oldRate = rewardPerSecond;
        rewardPerSecond = newRate;
        
        emit RewardPerSecondUpdated(oldRate, newRate);
    }
    
    /**
     * @dev فعال/غیرفعال کردن trading mining
     * @param enabled وضعیت جدید
     */
    function setTradingMiningEnabled(bool enabled) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        tradingMiningEnabled = enabled;
        emit TradingMiningToggled(enabled);
    }
    
    /**
     * @dev تنظیم حداقل volume برای trading mining
     * @param newMinVolume حداقل volume جدید
     */
    function setMinTradingVolume(uint256 newMinVolume) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        minTradingVolume = newMinVolume;
    }
    
    // ==================== FEE FUNCTIONS ====================
    
    /**
     * @dev تنظیم withdraw fee
     * @param newFeeRate نرخ کارمزد جدید
     */
    function setWithdrawFee(uint256 newFeeRate) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        if (newFeeRate > MAX_WITHDRAW_FEE) revert LPToken__InvalidFeeRate();
        
        uint256 oldFee = withdrawFeeInfo.feeRate;
        withdrawFeeInfo.feeRate = newFeeRate;
        
        emit WithdrawFeeUpdated(oldFee, newFeeRate);
    }
    
    /**
     * @dev تنظیم دریافت‌کننده withdraw fee
     * @param newRecipient آدرس جدید
     */
    function setWithdrawFeeRecipient(address newRecipient) 
        external 
        onlyValidRole(ADMIN_ROLE) 
        validAddress(newRecipient) 
    {
        withdrawFeeInfo.feeRecipient = newRecipient;
    }
    
    /**
     * @dev فعال/غیرفعال کردن withdraw fee
     * @param enabled وضعیت جدید
     */
    function setWithdrawFeeEnabled(bool enabled) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        withdrawFeeInfo.enabled = enabled;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم pool router
     * @param newRouter آدرس router جدید
     */
    function setRouter(address newRouter) 
        external 
        onlyValidRole(ADMIN_ROLE) 
        validAddress(newRouter) 
    {
        router = newRouter;
    }
    
    /**
     * @dev pause کردن کانترکت
     */
    function pause() external onlyValidRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev unpause کردن کانترکت
     */
    function unpause() external onlyValidRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev تنظیم allocation point برای pool
     * @param newAllocPoint نقطه allocation جدید
     */
    function setAllocPoint(uint256 newAllocPoint) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        _updatePool();
        poolInfo.allocPoint = newAllocPoint;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت اطلاعات mining کاربر
     * @param user آدرس کاربر
     * @return اطلاعات mining
     */
    function getMiningInfo(address user) 
        external 
        view 
        returns (MiningInfo memory) 
    {
        return lpMining[user];
    }
    
    /**
     * @dev بررسی امکان پایان mining
     * @param user آدرس کاربر
     * @return true اگر امکان پایان mining وجود داشته باشد
     */
    function canEndMining(address user) external view returns (bool) {
        MiningInfo storage info = lpMining[user];
        return info.active && block.timestamp >= info.endTime;
    }
    
    /**
     * @dev دریافت آمار کلی pool
     * @return آمار pool
     */
    function getPoolStats() external view returns (
        uint256 totalSupply_,
        uint256 totalLiquidity_,
        uint256 totalStaked_,
        uint256 rewardPool_,
        uint256 rewardPerSecond_
    ) {
        totalSupply_ = totalSupply();
        totalLiquidity_ = poolInfo.totalLiquidity;
        totalStaked_ = totalStaked;
        rewardPool_ = rewardPool;
        rewardPerSecond_ = rewardPerSecond;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev به‌روزرسانی pool rewards
     */
    function _updatePool() internal {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }
        
        if (totalStaked == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp.sub(poolInfo.lastRewardTime);
        uint256 reward = timeElapsed.mul(rewardPerSecond);
        
        poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(
            reward.mul(Constants.DECIMAL_BASE).div(totalStaked)
        );
        
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    /**
     * @dev محاسبه multiplier برای LP mining
     * @param duration مدت زمان mining
     * @return multiplier
     */
    function _calculateMiningMultiplier(uint256 duration) 
        internal 
        pure 
        returns (uint256) 
    {
        // Base multiplier = 1x (10000 basis points)
        // Max multiplier = 3x (30000 basis points) برای 1 سال
        uint256 baseMultiplier = Constants.FEE_BASE;
        uint256 maxMultiplier = 3 * Constants.FEE_BASE;
        uint256 maxDuration = 365 days;
        
        if (duration >= maxDuration) {
            return maxMultiplier;
        }
        
        uint256 multiplier = baseMultiplier.add(
            duration.mul(maxMultiplier.sub(baseMultiplier)).div(maxDuration)
        );
        
        return multiplier;
    }
    
    /**
     * @dev محاسبه multiplier برای trading mining
     * @param totalVolume کل حجم trading
     * @return multiplier
     */
    function _calculateTradingMultiplier(uint256 totalVolume) 
        internal 
        pure 
        returns (uint256) 
    {
        // Base multiplier = 1x
        // +0.1x برای هر 100,000 volume
        // Max multiplier = 5x
        
        uint256 baseMultiplier = Constants.FEE_BASE;
        uint256 volumeStep = 100000 * Constants.DECIMAL_BASE;
        uint256 multiplierIncrease = 1000; // 0.1x = 1000 basis points
        
        uint256 steps = totalVolume.div(volumeStep);
        uint256 multiplier = baseMultiplier.add(steps.mul(multiplierIncrease));
        
        if (multiplier > MAX_TRADING_MULTIPLIER) {
            multiplier = MAX_TRADING_MULTIPLIER;
        }
        
        return multiplier;
    }
    
    // ==================== OVERRIDES ====================
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
} 