// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../01-core/AccessControl.sol";
import "../02-token/LAXCE.sol";
import "../02-token/LPToken.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title LiquidityMining
 * @dev سیستم مدیریت mining نقدینگی با قابلیت‌های پیشرفته
 * @notice این کانترکت برای reward دادن به فراهم‌کنندگان نقدینگی استفاده می‌شود
 */
contract LiquidityMining is Pausable, LaxceAccessControl {
    using SafeERC20 for IERC20;
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد pools که می‌توانند فعال باشند
    uint256 public constant MAX_POOLS = 100;
    
    /// @dev حداکثر multiplier برای boost
    uint256 public constant MAX_BOOST_MULTIPLIER = 10000; // 100x
    
    /// @dev مدت زمان پیش‌فرض برای mining (30 روز)
    uint256 public constant DEFAULT_MINING_PERIOD = 30 days;
    
    /// @dev حداکثر APR (1000%)
    uint256 public constant MAX_APR = 100000; // 1000%
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات pool برای mining
    struct PoolInfo {
        IERC20 lpToken;                 // آدرس LP token
        uint256 allocPoint;             // امتیاز تخصیص برای این pool
        uint256 lastRewardBlock;        // آخرین block که reward محاسبه شده
        uint256 accRewardPerShare;      // reward انباشته per share (Q128)
        uint256 totalStaked;            // کل مقدار stake شده
        uint256 minStakeAmount;         // حداقل مقدار stake
        uint256 lockupPeriod;           // مدت زمان قفل بودن
        uint256 boostMultiplier;        // ضریب تقویت
        bool isActive;                  // آیا pool فعال است
        string poolName;                // نام pool
    }
    
    /// @dev اطلاعات کاربر در هر pool
    struct UserInfo {
        uint256 amount;                 // مقدار stake شده توسط کاربر
        uint256 rewardDebt;             // debt reward (Q128)
        uint256 pendingRewards;         // reward های در انتظار
        uint256 lastStakeTime;          // زمان آخرین stake
        uint256 lockEndTime;            // زمان پایان قفل
        uint256 boostLevel;             // سطح boost کاربر
        uint256 totalRewarded;          // کل reward دریافت شده
    }
    
    /// @dev اطلاعات boost
    struct BoostInfo {
        uint256 requiredLaxceAmount;    // مقدار LAXCE مورد نیاز
        uint256 multiplier;             // ضریب افزایش (basis points)
        uint256 duration;               // مدت زمان boost
        bool isActive;                  // آیا فعال است
    }
    
    /// @dev اطلاعات epoch برای reward distribution
    struct EpochInfo {
        uint256 startBlock;             // block شروع
        uint256 endBlock;               // block پایان
        uint256 rewardPerBlock;         // reward per block
        uint256 totalAllocPoint;        // کل allocation points
        bool isActive;                  // آیا فعال است
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev reentrancy guard instance
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس توکن LAXCE
    LAXCE public immutable laxceToken;
    
    /// @dev اطلاعات تمام pools
    PoolInfo[] public poolInfo;
    
    /// @dev mapping poolId => userId => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    /// @dev mapping برای boost levels
    mapping(uint256 => BoostInfo) public boostInfo;
    
    /// @dev epoch فعلی
    EpochInfo public currentEpoch;
    
    /// @dev تاریخچه epoch ها
    mapping(uint256 => EpochInfo) public epochHistory;
    
    /// @dev شمارنده epoch
    uint256 public epochCounter;
    
    /// @dev کل allocation points در همه pools
    uint256 public totalAllocPoint;
    
    /// @dev reward per block برای کل سیستم
    uint256 public rewardPerBlock;
    
    /// @dev pool reward مخزن
    uint256 public rewardPool;
    
    /// @dev emergency mode
    bool public emergencyMode;
    
    /// @dev treasury address for fees
    address public treasury;
    
    /// @dev performance fee (basis points)
    uint256 public performanceFee = 200; // 2%
    
    /// @dev withdrawal fee (basis points)
    uint256 public withdrawalFee = 50; // 0.5%
    
    /// @dev minimum boost LAXCE amount
    uint256 public minBoostAmount = 1000 ether;
    
    /// @dev total boost levels
    uint256 public totalBoostLevels = 5;
    
    // ==================== EVENTS ====================
    
    event PoolAdded(
        uint256 indexed pid,
        address indexed lpToken,
        uint256 allocPoint,
        uint256 minStakeAmount
    );
    
    event PoolUpdated(
        uint256 indexed pid,
        uint256 allocPoint,
        uint256 minStakeAmount
    );
    
    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    
    event BoostActivated(
        address indexed user,
        uint256 indexed pid,
        uint256 boostLevel,
        uint256 multiplier
    );
    
    event EpochStarted(
        uint256 indexed epochId,
        uint256 startBlock,
        uint256 endBlock,
        uint256 rewardPerBlock
    );
    
    event RewardPoolFunded(uint256 amount);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyModeToggled(bool enabled);
    
    // ==================== ERRORS ====================
    
    error LiquidityMining__InvalidPool();
    error LiquidityMining__PoolNotActive();
    error LiquidityMining__InsufficientAmount();
    error LiquidityMining__StillLocked();
    error LiquidityMining__InvalidBoostLevel();
    error LiquidityMining__InsufficientLaxceBalance();
    error LiquidityMining__EmergencyMode();
    error LiquidityMining__InvalidFee();
    error LiquidityMining__MaxPoolsReached();
    error LiquidityMining__InvalidAllocation();
    error LiquidityMining__InvalidEpoch();
    error LiquidityMining__InsufficientRewardPool();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validPool(uint256 _pid) {
        if (_pid >= poolInfo.length) revert LiquidityMining__InvalidPool();
        _;
    }
    
    modifier activePool(uint256 _pid) {
        if (!poolInfo[_pid].isActive) revert LiquidityMining__PoolNotActive();
        _;
    }
    
    modifier notEmergency() {
        if (emergencyMode) revert LiquidityMining__EmergencyMode();
        _;
    }
    
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert LiquidityMining__InsufficientAmount();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _laxceToken,
        address _treasury,
        uint256 _rewardPerBlock
    ) {
        laxceToken = LAXCE(_laxceToken);
        treasury = _treasury;
        rewardPerBlock = _rewardPerBlock;
        
        _reentrancyGuard.initialize();
        
        // گرنت نقش‌های پیش‌فرض
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // راه‌اندازی boost levels پیش‌فرض
        _setupDefaultBoostLevels();
        
        // شروع epoch اول
        _startNewEpoch(block.number, block.number + DEFAULT_MINING_PERIOD / 12); // ~30 days
    }
    
    // ==================== MAIN FUNCTIONS ====================
    
    /**
     * @notice اضافه کردن pool جدید
     * @param _lpToken آدرس LP token
     * @param _allocPoint امتیاز تخصیص
     * @param _minStakeAmount حداقل مقدار stake
     * @param _lockupPeriod مدت زمان قفل
     * @param _poolName نام pool
     */
    function addPool(
        address _lpToken,
        uint256 _allocPoint,
        uint256 _minStakeAmount,
        uint256 _lockupPeriod,
        string calldata _poolName
    ) external onlyRole(OPERATOR_ROLE) notEmergency {
        if (poolInfo.length >= MAX_POOLS) revert LiquidityMining__MaxPoolsReached();
        
        // بروزرسانی تمام pools
        massUpdatePools();
        
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        
        poolInfo.push(PoolInfo({
            lpToken: IERC20(_lpToken),
            allocPoint: _allocPoint,
            lastRewardBlock: block.number,
            accRewardPerShare: 0,
            totalStaked: 0,
            minStakeAmount: _minStakeAmount,
            lockupPeriod: _lockupPeriod,
            boostMultiplier: 10000, // 1x as default
            isActive: true,
            poolName: _poolName
        }));
        
        emit PoolAdded(poolInfo.length - 1, _lpToken, _allocPoint, _minStakeAmount);
    }
    
    /**
     * @notice بروزرسانی تنظیمات pool
     * @param _pid شناسه pool
     * @param _allocPoint امتیاز تخصیص جدید
     * @param _minStakeAmount حداقل مقدار stake جدید
     */
    function updatePool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _minStakeAmount
    ) external onlyRole(OPERATOR_ROLE) validPool(_pid) {
        massUpdatePools();
        
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].minStakeAmount = _minStakeAmount;
        
        emit PoolUpdated(_pid, _allocPoint, _minStakeAmount);
    }
    
    /**
     * @notice stake کردن LP tokens
     * @param _pid شناسه pool
     * @param _amount مقدار برای stake
     */
    function deposit(uint256 _pid, uint256 _amount)
        external
        nonReentrant
        validPool(_pid)
        activePool(_pid)
        validAmount(_amount)
        notEmergency
        whenNotPaused
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        if (_amount < pool.minStakeAmount && user.amount == 0) {
            revert LiquidityMining__InsufficientAmount();
        }
        
        updatePoolRewards(_pid);
        
        // محاسبه pending rewards
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                user.pendingRewards = user.pendingRewards.add(pending);
            }
        }
        
        // انتقال LP tokens
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        // بروزرسانی اطلاعات کاربر
        user.amount = user.amount.add(_amount);
        user.lastStakeTime = block.timestamp;
        user.lockEndTime = block.timestamp.add(pool.lockupPeriod);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        
        // بروزرسانی کل stake شده در pool
        pool.totalStaked = pool.totalStaked.add(_amount);
        
        emit Deposit(msg.sender, _pid, _amount);
    }
    
    /**
     * @notice withdraw کردن LP tokens
     * @param _pid شناسه pool
     * @param _amount مقدار برای withdraw
     */
    function withdraw(uint256 _pid, uint256 _amount)
        external
        nonReentrant
        validPool(_pid)
        validAmount(_amount)
        whenNotPaused
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        if (user.amount < _amount) revert LiquidityMining__InsufficientAmount();
        if (block.timestamp < user.lockEndTime) revert LiquidityMining__StillLocked();
        
        updatePoolRewards(_pid);
        
        // محاسبه pending rewards
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        
        // بروزرسانی اطلاعات کاربر
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        
        // بروزرسانی کل stake شده در pool
        pool.totalStaked = pool.totalStaked.sub(_amount);
        
        // محاسبه withdrawal fee
        uint256 feeAmount = _amount.mul(withdrawalFee).div(10000);
        uint256 withdrawAmount = _amount.sub(feeAmount);
        
        // انتقال tokens
        if (feeAmount > 0) {
            pool.lpToken.safeTransfer(treasury, feeAmount);
        }
        pool.lpToken.safeTransfer(msg.sender, withdrawAmount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    /**
     * @notice claim کردن rewards
     * @param _pid شناسه pool
     */
    function claimRewards(uint256 _pid)
        external
        nonReentrant
        validPool(_pid)
        whenNotPaused
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        updatePoolRewards(_pid);
        
        // محاسبه total rewards
        uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        uint256 totalRewards = user.pendingRewards.add(pending);
        
        if (totalRewards > 0) {
            // اعمال boost
            uint256 boostedRewards = _applyBoost(msg.sender, _pid, totalRewards);
            
            // محاسبه performance fee
            uint256 feeAmount = boostedRewards.mul(performanceFee).div(10000);
            uint256 userRewards = boostedRewards.sub(feeAmount);
            
            // انتقال rewards
            if (feeAmount > 0) {
                laxceToken.transfer(treasury, feeAmount);
            }
            laxceToken.transfer(msg.sender, userRewards);
            
            // بروزرسانی اطلاعات کاربر
            user.pendingRewards = 0;
            user.totalRewarded = user.totalRewarded.add(userRewards);
            user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
            
            emit RewardsClaimed(msg.sender, _pid, userRewards);
        }
    }
    
    /**
     * @notice فعال‌سازی boost
     * @param _pid شناسه pool
     * @param _boostLevel سطح boost
     */
    function activateBoost(uint256 _pid, uint256 _boostLevel)
        external
        nonReentrant
        validPool(_pid)
        whenNotPaused
    {
        if (_boostLevel == 0 || _boostLevel > totalBoostLevels) {
            revert LiquidityMining__InvalidBoostLevel();
        }
        
        BoostInfo storage boost = boostInfo[_boostLevel];
        if (!boost.isActive) revert LiquidityMining__InvalidBoostLevel();
        
        // بررسی موجودی LAXCE
        uint256 laxceBalance = laxceToken.balanceOf(msg.sender);
        if (laxceBalance < boost.requiredLaxceAmount) {
            revert LiquidityMining__InsufficientLaxceBalance();
        }
        
        UserInfo storage user = userInfo[_pid][msg.sender];
        user.boostLevel = _boostLevel;
        
        emit BoostActivated(msg.sender, _pid, _boostLevel, boost.multiplier);
    }
    
    /**
     * @notice بروزرسانی rewards برای یک pool
     * @param _pid شناسه pool
     */
    function updatePoolRewards(uint256 _pid) public validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        
        if (pool.totalStaked == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        // محاسبه reward برای این pool
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 reward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        
        // بررسی کافی بودن reward pool
        if (reward > rewardPool) {
            reward = rewardPool;
        }
        
        if (reward > 0) {
            pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(1e12).div(pool.totalStaked));
            rewardPool = rewardPool.sub(reward);
        }
        
        pool.lastRewardBlock = block.number;
    }
    
    /**
     * @notice بروزرسانی همه pools
     */
    function massUpdatePools() public {
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            updatePoolRewards(pid);
        }
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev اعمال boost به rewards
     */
    function _applyBoost(address _user, uint256 _pid, uint256 _amount) internal view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        
        if (user.boostLevel == 0) {
            return _amount;
        }
        
        BoostInfo storage boost = boostInfo[user.boostLevel];
        return _amount.mul(boost.multiplier).div(10000);
    }
    
    /**
     * @dev راه‌اندازی boost levels پیش‌فرض
     */
    function _setupDefaultBoostLevels() internal {
        // Level 1: 1.2x boost, requires 1,000 LAXCE
        boostInfo[1] = BoostInfo({
            requiredLaxceAmount: 1000 ether,
            multiplier: 12000, // 1.2x
            duration: 30 days,
            isActive: true
        });
        
        // Level 2: 1.5x boost, requires 5,000 LAXCE
        boostInfo[2] = BoostInfo({
            requiredLaxceAmount: 5000 ether,
            multiplier: 15000, // 1.5x
            duration: 30 days,
            isActive: true
        });
        
        // Level 3: 2x boost, requires 10,000 LAXCE
        boostInfo[3] = BoostInfo({
            requiredLaxceAmount: 10000 ether,
            multiplier: 20000, // 2x
            duration: 30 days,
            isActive: true
        });
        
        // Level 4: 3x boost, requires 25,000 LAXCE
        boostInfo[4] = BoostInfo({
            requiredLaxceAmount: 25000 ether,
            multiplier: 30000, // 3x
            duration: 30 days,
            isActive: true
        });
        
        // Level 5: 5x boost, requires 50,000 LAXCE
        boostInfo[5] = BoostInfo({
            requiredLaxceAmount: 50000 ether,
            multiplier: 50000, // 5x
            duration: 30 days,
            isActive: true
        });
    }
    
    /**
     * @dev شروع epoch جدید
     */
    function _startNewEpoch(uint256 _startBlock, uint256 _endBlock) internal {
        epochCounter++;
        
        currentEpoch = EpochInfo({
            startBlock: _startBlock,
            endBlock: _endBlock,
            rewardPerBlock: rewardPerBlock,
            totalAllocPoint: totalAllocPoint,
            isActive: true
        });
        
        epochHistory[epochCounter] = currentEpoch;
        
        emit EpochStarted(epochCounter, _startBlock, _endBlock, rewardPerBlock);
    }
    
    // ==================== EMERGENCY FUNCTIONS ====================
    
    /**
     * @notice emergency withdraw (بدون reward)
     * @param _pid شناسه pool
     */
    function emergencyWithdraw(uint256 _pid) external nonReentrant validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
        
        pool.totalStaked = pool.totalStaked.sub(amount);
        pool.lpToken.safeTransfer(msg.sender, amount);
        
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice تامین reward pool
     * @param _amount مقدار برای اضافه کردن
     */
    function fundRewardPool(uint256 _amount) external onlyRole(OPERATOR_ROLE) {
        laxceToken.transferFrom(msg.sender, address(this), _amount);
        rewardPool = rewardPool.add(_amount);
        
        emit RewardPoolFunded(_amount);
    }
    
    /**
     * @notice تنظیم reward per block
     * @param _rewardPerBlock reward جدید per block
     */
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyRole(OPERATOR_ROLE) {
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
    }
    
    /**
     * @notice تنظیم performance fee
     * @param _performanceFee کارمزد جدید (basis points)
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyRole(OPERATOR_ROLE) {
        if (_performanceFee > 1000) revert LiquidityMining__InvalidFee(); // حداکثر 10%
        
        uint256 oldFee = performanceFee;
        performanceFee = _performanceFee;
        
        emit PerformanceFeeUpdated(oldFee, _performanceFee);
    }
    
    /**
     * @notice تنظیم withdrawal fee
     * @param _withdrawalFee کارمزد جدید (basis points)
     */
    function setWithdrawalFee(uint256 _withdrawalFee) external onlyRole(OPERATOR_ROLE) {
        if (_withdrawalFee > 500) revert LiquidityMining__InvalidFee(); // حداکثر 5%
        
        uint256 oldFee = withdrawalFee;
        withdrawalFee = _withdrawalFee;
        
        emit WithdrawalFeeUpdated(oldFee, _withdrawalFee);
    }
    
    /**
     * @notice تنظیم treasury
     * @param _treasury آدرس treasury جدید
     */
    function setTreasury(address _treasury) external onlyRole(OPERATOR_ROLE) {
        address oldTreasury = treasury;
        treasury = _treasury;
        
        emit TreasuryUpdated(oldTreasury, _treasury);
    }
    
    /**
     * @notice تغییر وضعیت pool
     * @param _pid شناسه pool
     * @param _isActive وضعیت جدید
     */
    function setPoolActive(uint256 _pid, bool _isActive) external onlyRole(OPERATOR_ROLE) validPool(_pid) {
        poolInfo[_pid].isActive = _isActive;
    }
    
    /**
     * @notice تنظیم boost level
     * @param _level سطح boost
     * @param _requiredAmount مقدار LAXCE مورد نیاز
     * @param _multiplier ضریب
     * @param _duration مدت زمان
     * @param _isActive وضعیت فعال بودن
     */
    function setBoostLevel(
        uint256 _level,
        uint256 _requiredAmount,
        uint256 _multiplier,
        uint256 _duration,
        bool _isActive
    ) external onlyRole(OPERATOR_ROLE) {
        boostInfo[_level] = BoostInfo({
            requiredLaxceAmount: _requiredAmount,
            multiplier: _multiplier,
            duration: _duration,
            isActive: _isActive
        });
    }
    
    /**
     * @notice تغییر وضعیت emergency mode
     * @param _enabled آیا فعال باشد
     */
    function setEmergencyMode(bool _enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeToggled(_enabled);
    }
    
    /**
     * @notice شروع epoch جدید
     * @param _startBlock block شروع
     * @param _endBlock block پایان
     * @param _rewardPerBlock reward per block
     */
    function startNewEpoch(
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardPerBlock
    ) external onlyRole(OPERATOR_ROLE) {
        if (_startBlock >= _endBlock) revert LiquidityMining__InvalidEpoch();
        
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;
        _startNewEpoch(_startBlock, _endBlock);
    }
    
    /**
     * @notice توقف اضطراری
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice لغو توقف
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice دریافت تعداد pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    
    /**
     * @notice محاسبه pending rewards
     * @param _pid شناسه pool
     * @param _user آدرس کاربر
     * @return pending مقدار reward در انتظار
     */
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256 pending) {
        if (_pid >= poolInfo.length) return 0;
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        
        uint256 accRewardPerShare = pool.accRewardPerShare;
        
        if (block.number > pool.lastRewardBlock && pool.totalStaked != 0) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 reward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(reward.mul(1e12).div(pool.totalStaked));
        }
        
        pending = user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
        
        // اعمال boost
        pending = _applyBoost(_user, _pid, pending);
    }
    
    /**
     * @notice دریافت اطلاعات کاربر
     * @param _pid شناسه pool
     * @param _user آدرس کاربر
     */
    function getUserInfo(uint256 _pid, address _user) external view returns (UserInfo memory) {
        return userInfo[_pid][_user];
    }
    
    /**
     * @notice دریافت اطلاعات pool
     * @param _pid شناسه pool
     */
    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory) {
        if (_pid >= poolInfo.length) revert LiquidityMining__InvalidPool();
        return poolInfo[_pid];
    }
    
    /**
     * @notice دریافت آمار کلی
     */
    function getGlobalStats() external view returns (
        uint256 totalPools,
        uint256 totalStaked,
        uint256 totalRewardDistributed,
        uint256 currentRewardPool
    ) {
        totalPools = poolInfo.length;
        currentRewardPool = rewardPool;
        
        for (uint256 i = 0; i < poolInfo.length; i++) {
            totalStaked = totalStaked.add(poolInfo[i].totalStaked);
        }
        
        // محاسبه total reward distributed از تفاوت initial و current pool
        // این محاسبه در implementation واقعی باید دقیق‌تر باشد
    }
    
    /**
     * @notice محاسبه APR برای pool
     * @param _pid شناسه pool
     */
    function getPoolAPR(uint256 _pid) external view returns (uint256) {
        if (_pid >= poolInfo.length) return 0;
        
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.totalStaked == 0 || totalAllocPoint == 0) return 0;
        
        // محاسبه APR ساده (در implementation واقعی باید دقیق‌تر باشد)
        uint256 yearlyRewards = rewardPerBlock.mul(365 days).div(12 seconds); // assuming 12s block time
        uint256 poolYearlyRewards = yearlyRewards.mul(pool.allocPoint).div(totalAllocPoint);
        
        return poolYearlyRewards.mul(10000).div(pool.totalStaked); // در basis points
    }
} 