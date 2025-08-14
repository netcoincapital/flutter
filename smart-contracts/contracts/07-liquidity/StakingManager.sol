// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../01-core/AccessControl.sol";
import "../02-token/LAXCE.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title StakingManager
 * @dev سیستم مدیریت staking توکن LAXCE با tiers مختلف و multipliers زمانی
 * @notice این کانترکت برای staking LAXCE و دریافت voting power و rewards استفاده می‌شود
 */
contract StakingManager is Pausable, LaxceAccessControl {
    using SafeERC20 for IERC20;
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد staking tiers
    uint256 public constant MAX_TIERS = 10;
    
    /// @dev حداکثر lock period (4 سال)
    uint256 public constant MAX_LOCK_PERIOD = 4 * 365 days;
    
    /// @dev حداقل lock period (1 روز)
    uint256 public constant MIN_LOCK_PERIOD = 1 days;
    
    /// @dev حداکثر APR (500%)
    uint256 public constant MAX_APR = 50000;
    
    /// @dev basis points denominator
    uint256 public constant BASIS_POINTS = 10000;
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات staking tier
    struct StakingTier {
        string name;                    // نام tier
        uint256 minAmount;              // حداقل مقدار stake
        uint256 maxAmount;              // حداکثر مقدار stake (0 = unlimited)
        uint256 lockPeriod;             // مدت زمان قفل (seconds)
        uint256 baseAPR;                // نرخ بازده پایه (basis points)
        uint256 votingMultiplier;       // ضریب voting power (basis points)
        uint256 rewardMultiplier;       // ضریب rewards (basis points)
        bool isActive;                  // آیا tier فعال است
        uint256 totalStaked;            // کل مقدار stake شده در این tier
        uint256 maxCapacity;            // حداکثر ظرفیت tier
    }
    
    /// @dev اطلاعات stake کاربر
    struct UserStake {
        uint256 amount;                 // مقدار stake شده
        uint256 tierId;                 // شناسه tier
        uint256 stakeTime;              // زمان stake
        uint256 unlockTime;             // زمان unlock
        uint256 lastRewardTime;         // زمان آخرین محاسبه reward
        uint256 accruedRewards;         // rewards انباشته شده
        uint256 votingPower;            // قدرت رای
        bool isActive;                  // آیا stake فعال است
    }
    
    /// @dev اطلاعات penalty برای early unstake
    struct PenaltyInfo {
        uint256 penaltyRate;            // نرخ penalty (basis points)
        uint256 gracePeriod;            // دوره مهلت بدون penalty
        address penaltyRecipient;       // دریافت کننده penalty
    }
    
    /// @dev اطلاعات epoch برای reward distribution
    struct EpochInfo {
        uint256 startTime;              // زمان شروع epoch
        uint256 endTime;                // زمان پایان epoch
        uint256 rewardPerSecond;        // reward per second
        uint256 totalStaked;            // کل مقدار stake شده
        uint256 totalRewards;           // کل rewards این epoch
        bool isActive;                  // آیا epoch فعال است
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev reentrancy guard instance
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس توکن LAXCE
    LAXCE public immutable laxceToken;
    
    /// @dev اطلاعات همه tiers
    StakingTier[] public tiers;
    
    /// @dev mapping userId => stakeId => UserStake
    mapping(address => mapping(uint256 => UserStake)) public userStakes;
    
    /// @dev mapping userId => تعداد stakes
    mapping(address => uint256) public userStakeCount;
    
    /// @dev epoch فعلی
    EpochInfo public currentEpoch;
    
    /// @dev تاریخچه epochs
    mapping(uint256 => EpochInfo) public epochHistory;
    
    /// @dev شمارنده epoch
    uint256 public epochCounter;
    
    /// @dev اطلاعات penalty
    PenaltyInfo public penaltyInfo;
    
    /// @dev کل مقدار stake شده
    uint256 public totalStaked;
    
    /// @dev کل voting power
    uint256 public totalVotingPower;
    
    /// @dev reward pool
    uint256 public rewardPool;
    
    /// @dev treasury address
    address public treasury;
    
    /// @dev emergency mode
    bool public emergencyMode;
    
    /// @dev compound enabled
    bool public compoundEnabled = true;
    
    /// @dev auto-extend enabled
    bool public autoExtendEnabled = true;
    
    /// @dev governance integration
    address public governanceContract;
    
    // ==================== EVENTS ====================
    
    event TierAdded(
        uint256 indexed tierId,
        string name,
        uint256 minAmount,
        uint256 lockPeriod,
        uint256 baseAPR
    );
    
    event TierUpdated(uint256 indexed tierId, bool isActive);
    
    event Staked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 indexed tierId,
        uint256 amount,
        uint256 unlockTime
    );
    
    event Unstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 penalty
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount
    );
    
    event Compounded(
        address indexed user,
        uint256 indexed stakeId,
        uint256 rewardAmount,
        uint256 newStakeAmount
    );
    
    event StakeExtended(
        address indexed user,
        uint256 indexed stakeId,
        uint256 newUnlockTime,
        uint256 newTierId
    );
    
    event EpochStarted(
        uint256 indexed epochId,
        uint256 startTime,
        uint256 endTime,
        uint256 rewardPerSecond
    );
    
    event VotingPowerUpdated(address indexed user, uint256 newVotingPower);
    event RewardPoolFunded(uint256 amount);
    event PenaltyInfoUpdated(uint256 penaltyRate, uint256 gracePeriod);
    event EmergencyModeToggled(bool enabled);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    
    // ==================== ERRORS ====================
    
    error StakingManager__InvalidTier();
    error StakingManager__TierNotActive();
    error StakingManager__InsufficientAmount();
    error StakingManager__AmountTooHigh();
    error StakingManager__InvalidStakeId();
    error StakingManager__StakeNotActive();
    error StakingManager__StillLocked();
    error StakingManager__EmergencyMode();
    error StakingManager__InvalidLockPeriod();
    error StakingManager__TierCapacityExceeded();
    error StakingManager__NoRewardsAvailable();
    error StakingManager__InvalidEpoch();
    error StakingManager__MaxTiersReached();
    error StakingManager__InsufficientRewardPool();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validTier(uint256 _tierId) {
        if (_tierId >= tiers.length) revert StakingManager__InvalidTier();
        _;
    }
    
    modifier activeTier(uint256 _tierId) {
        if (!tiers[_tierId].isActive) revert StakingManager__TierNotActive();
        _;
    }
    
    modifier validStake(address _user, uint256 _stakeId) {
        if (_stakeId >= userStakeCount[_user]) revert StakingManager__InvalidStakeId();
        if (!userStakes[_user][_stakeId].isActive) revert StakingManager__StakeNotActive();
        _;
    }
    
    modifier notEmergency() {
        if (emergencyMode) revert StakingManager__EmergencyMode();
        _;
    }
    
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert StakingManager__InsufficientAmount();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _laxceToken,
        address _treasury
    ) {
        laxceToken = LAXCE(_laxceToken);
        treasury = _treasury;
        
        _reentrancyGuard.initialize();
        
        // گرنت نقش‌های پیش‌فرض
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // تنظیم penalty پیش‌فرض
        penaltyInfo = PenaltyInfo({
            penaltyRate: 1000, // 10%
            gracePeriod: 7 days,
            penaltyRecipient: _treasury
        });
        
        // راه‌اندازی tiers پیش‌فرض
        _setupDefaultTiers();
        
        // شروع epoch اول
        _startNewEpoch(block.timestamp, block.timestamp + 30 days, 1 ether);
    }
    
    // ==================== TIER MANAGEMENT ====================
    
    /**
     * @notice اضافه کردن tier جدید
     * @param _name نام tier
     * @param _minAmount حداقل مقدار stake
     * @param _maxAmount حداکثر مقدار stake
     * @param _lockPeriod مدت زمان قفل
     * @param _baseAPR نرخ بازده پایه
     * @param _votingMultiplier ضریب voting power
     * @param _rewardMultiplier ضریب rewards
     * @param _maxCapacity حداکثر ظرفیت
     */
    function addTier(
        string calldata _name,
        uint256 _minAmount,
        uint256 _maxAmount,
        uint256 _lockPeriod,
        uint256 _baseAPR,
        uint256 _votingMultiplier,
        uint256 _rewardMultiplier,
        uint256 _maxCapacity
    ) external onlyRole(OPERATOR_ROLE) notEmergency {
        if (tiers.length >= MAX_TIERS) revert StakingManager__MaxTiersReached();
        if (_lockPeriod < MIN_LOCK_PERIOD || _lockPeriod > MAX_LOCK_PERIOD) {
            revert StakingManager__InvalidLockPeriod();
        }
        if (_baseAPR > MAX_APR) revert StakingManager__InsufficientAmount();
        
        tiers.push(StakingTier({
            name: _name,
            minAmount: _minAmount,
            maxAmount: _maxAmount,
            lockPeriod: _lockPeriod,
            baseAPR: _baseAPR,
            votingMultiplier: _votingMultiplier,
            rewardMultiplier: _rewardMultiplier,
            isActive: true,
            totalStaked: 0,
            maxCapacity: _maxCapacity
        }));
        
        emit TierAdded(tiers.length - 1, _name, _minAmount, _lockPeriod, _baseAPR);
    }
    
    /**
     * @notice بروزرسانی tier
     * @param _tierId شناسه tier
     * @param _isActive وضعیت فعال بودن
     * @param _baseAPR نرخ بازده جدید
     * @param _maxCapacity ظرفیت جدید
     */
    function updateTier(
        uint256 _tierId,
        bool _isActive,
        uint256 _baseAPR,
        uint256 _maxCapacity
    ) external onlyRole(OPERATOR_ROLE) validTier(_tierId) {
        if (_baseAPR > MAX_APR) revert StakingManager__InsufficientAmount();
        
        StakingTier storage tier = tiers[_tierId];
        tier.isActive = _isActive;
        tier.baseAPR = _baseAPR;
        tier.maxCapacity = _maxCapacity;
        
        emit TierUpdated(_tierId, _isActive);
    }
    
    // ==================== STAKING FUNCTIONS ====================
    
    /**
     * @notice stake کردن LAXCE tokens
     * @param _tierId شناسه tier
     * @param _amount مقدار برای stake
     */
    function stake(uint256 _tierId, uint256 _amount)
        external
        nonReentrant
        validTier(_tierId)
        activeTier(_tierId)
        validAmount(_amount)
        notEmergency
        whenNotPaused
    {
        StakingTier storage tier = tiers[_tierId];
        
        // بررسی محدودیت‌ها
        if (_amount < tier.minAmount) revert StakingManager__InsufficientAmount();
        if (tier.maxAmount > 0 && _amount > tier.maxAmount) revert StakingManager__AmountTooHigh();
        if (tier.maxCapacity > 0 && tier.totalStaked.add(_amount) > tier.maxCapacity) {
            revert StakingManager__TierCapacityExceeded();
        }
        
        // انتقال tokens
        laxceToken.transferFrom(msg.sender, address(this), _amount);
        
        // محاسبه voting power
        uint256 votingPower = _amount.mul(tier.votingMultiplier).div(BASIS_POINTS);
        
        // ایجاد stake جدید
        uint256 stakeId = userStakeCount[msg.sender];
        uint256 unlockTime = block.timestamp.add(tier.lockPeriod);
        
        userStakes[msg.sender][stakeId] = UserStake({
            amount: _amount,
            tierId: _tierId,
            stakeTime: block.timestamp,
            unlockTime: unlockTime,
            lastRewardTime: block.timestamp,
            accruedRewards: 0,
            votingPower: votingPower,
            isActive: true
        });
        
        userStakeCount[msg.sender]++;
        
        // بروزرسانی آمار کلی
        tier.totalStaked = tier.totalStaked.add(_amount);
        totalStaked = totalStaked.add(_amount);
        totalVotingPower = totalVotingPower.add(votingPower);
        
        // integration با governance
        if (governanceContract != address(0)) {
            _updateGovernanceVotingPower(msg.sender);
        }
        
        emit Staked(msg.sender, stakeId, _tierId, _amount, unlockTime);
        emit VotingPowerUpdated(msg.sender, _getUserTotalVotingPower(msg.sender));
    }
    
    /**
     * @notice unstake کردن tokens
     * @param _stakeId شناسه stake
     */
    function unstake(uint256 _stakeId)
        external
        nonReentrant
        validStake(msg.sender, _stakeId)
        whenNotPaused
    {
        UserStake storage userStake = userStakes[msg.sender][_stakeId];
        StakingTier storage tier = tiers[userStake.tierId];
        
        // محاسبه pending rewards
        uint256 pendingRewards = _calculatePendingRewards(msg.sender, _stakeId);
        
        uint256 penalty = 0;
        uint256 unstakeAmount = userStake.amount;
        
        // محاسبه penalty اگر early unstake
        if (block.timestamp < userStake.unlockTime) {
            uint256 timePassed = block.timestamp.sub(userStake.stakeTime);
            if (timePassed < penaltyInfo.gracePeriod) {
                penalty = unstakeAmount.mul(penaltyInfo.penaltyRate).div(BASIS_POINTS);
                unstakeAmount = unstakeAmount.sub(penalty);
            }
        }
        
        // بروزرسانی آمار
        tier.totalStaked = tier.totalStaked.sub(userStake.amount);
        totalStaked = totalStaked.sub(userStake.amount);
        totalVotingPower = totalVotingPower.sub(userStake.votingPower);
        
        // غیرفعال کردن stake
        userStake.isActive = false;
        
        // انتقال tokens
        if (penalty > 0) {
            laxceToken.transfer(penaltyInfo.penaltyRecipient, penalty);
        }
        laxceToken.transfer(msg.sender, unstakeAmount);
        
        // انتقال rewards
        if (pendingRewards > 0) {
            _claimRewards(msg.sender, _stakeId, pendingRewards);
        }
        
        // بروزرسانی governance voting power
        if (governanceContract != address(0)) {
            _updateGovernanceVotingPower(msg.sender);
        }
        
        emit Unstaked(msg.sender, _stakeId, userStake.amount, penalty);
        emit VotingPowerUpdated(msg.sender, _getUserTotalVotingPower(msg.sender));
    }
    
    /**
     * @notice claim کردن rewards
     * @param _stakeId شناسه stake
     */
    function claimRewards(uint256 _stakeId)
        external
        nonReentrant
        validStake(msg.sender, _stakeId)
        whenNotPaused
    {
        uint256 pendingRewards = _calculatePendingRewards(msg.sender, _stakeId);
        if (pendingRewards == 0) revert StakingManager__NoRewardsAvailable();
        
        _claimRewards(msg.sender, _stakeId, pendingRewards);
    }
    
    /**
     * @notice compound کردن rewards
     * @param _stakeId شناسه stake
     */
    function compound(uint256 _stakeId)
        external
        nonReentrant
        validStake(msg.sender, _stakeId)
        notEmergency
        whenNotPaused
    {
        if (!compoundEnabled) revert StakingManager__EmergencyMode();
        
        UserStake storage userStake = userStakes[msg.sender][_stakeId];
        StakingTier storage tier = tiers[userStake.tierId];
        
        uint256 pendingRewards = _calculatePendingRewards(msg.sender, _stakeId);
        if (pendingRewards == 0) revert StakingManager__NoRewardsAvailable();
        
        // اضافه کردن rewards به stake amount
        userStake.amount = userStake.amount.add(pendingRewards);
        userStake.lastRewardTime = block.timestamp;
        userStake.accruedRewards = 0;
        
        // محاسبه voting power جدید
        uint256 additionalVotingPower = pendingRewards.mul(tier.votingMultiplier).div(BASIS_POINTS);
        userStake.votingPower = userStake.votingPower.add(additionalVotingPower);
        
        // بروزرسانی آمار کلی
        tier.totalStaked = tier.totalStaked.add(pendingRewards);
        totalStaked = totalStaked.add(pendingRewards);
        totalVotingPower = totalVotingPower.add(additionalVotingPower);
        
        // بروزرسانی governance voting power
        if (governanceContract != address(0)) {
            _updateGovernanceVotingPower(msg.sender);
        }
        
        emit Compounded(msg.sender, _stakeId, pendingRewards, userStake.amount);
        emit VotingPowerUpdated(msg.sender, _getUserTotalVotingPower(msg.sender));
    }
    
    /**
     * @notice تمدید stake
     * @param _stakeId شناسه stake
     * @param _newTierId tier جدید
     */
    function extendStake(uint256 _stakeId, uint256 _newTierId)
        external
        nonReentrant
        validStake(msg.sender, _stakeId)
        validTier(_newTierId)
        activeTier(_newTierId)
        notEmergency
        whenNotPaused
    {
        if (!autoExtendEnabled) revert StakingManager__EmergencyMode();
        
        UserStake storage userStake = userStakes[msg.sender][_stakeId];
        StakingTier storage oldTier = tiers[userStake.tierId];
        StakingTier storage newTier = tiers[_newTierId];
        
        // بررسی محدودیت‌های tier جدید
        if (userStake.amount < newTier.minAmount) revert StakingManager__InsufficientAmount();
        if (newTier.maxAmount > 0 && userStake.amount > newTier.maxAmount) {
            revert StakingManager__AmountTooHigh();
        }
        
        // claim pending rewards
        uint256 pendingRewards = _calculatePendingRewards(msg.sender, _stakeId);
        if (pendingRewards > 0) {
            _claimRewards(msg.sender, _stakeId, pendingRewards);
        }
        
        // محاسبه voting power جدید
        uint256 oldVotingPower = userStake.votingPower;
        uint256 newVotingPower = userStake.amount.mul(newTier.votingMultiplier).div(BASIS_POINTS);
        
        // بروزرسانی stake
        userStake.tierId = _newTierId;
        userStake.unlockTime = block.timestamp.add(newTier.lockPeriod);
        userStake.lastRewardTime = block.timestamp;
        userStake.votingPower = newVotingPower;
        
        // بروزرسانی آمار tiers
        oldTier.totalStaked = oldTier.totalStaked.sub(userStake.amount);
        newTier.totalStaked = newTier.totalStaked.add(userStake.amount);
        
        // بروزرسانی voting power کلی
        totalVotingPower = totalVotingPower.sub(oldVotingPower).add(newVotingPower);
        
        // بروزرسانی governance voting power
        if (governanceContract != address(0)) {
            _updateGovernanceVotingPower(msg.sender);
        }
        
        emit StakeExtended(msg.sender, _stakeId, userStake.unlockTime, _newTierId);
        emit VotingPowerUpdated(msg.sender, _getUserTotalVotingPower(msg.sender));
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev محاسبه pending rewards
     */
    function _calculatePendingRewards(address _user, uint256 _stakeId) internal view returns (uint256) {
        UserStake storage userStake = userStakes[_user][_stakeId];
        if (!userStake.isActive) return 0;
        
        StakingTier storage tier = tiers[userStake.tierId];
        
        uint256 timePassed = block.timestamp.sub(userStake.lastRewardTime);
        uint256 baseReward = userStake.amount.mul(tier.baseAPR).mul(timePassed).div(365 days).div(BASIS_POINTS);
        
        // اعمال reward multiplier
        uint256 totalReward = baseReward.mul(tier.rewardMultiplier).div(BASIS_POINTS);
        
        return totalReward.add(userStake.accruedRewards);
    }
    
    /**
     * @dev claim کردن rewards
     */
    function _claimRewards(address _user, uint256 _stakeId, uint256 _amount) internal {
        UserStake storage userStake = userStakes[_user][_stakeId];
        
        userStake.lastRewardTime = block.timestamp;
        userStake.accruedRewards = 0;
        
        // بررسی کافی بودن reward pool
        if (_amount > rewardPool) {
            _amount = rewardPool;
        }
        
        if (_amount > 0) {
            rewardPool = rewardPool.sub(_amount);
            laxceToken.transfer(_user, _amount);
            
            emit RewardsClaimed(_user, _stakeId, _amount);
        }
    }
    
    /**
     * @dev دریافت کل voting power کاربر
     */
    function _getUserTotalVotingPower(address _user) internal view returns (uint256) {
        uint256 totalVP = 0;
        for (uint256 i = 0; i < userStakeCount[_user]; i++) {
            if (userStakes[_user][i].isActive) {
                totalVP = totalVP.add(userStakes[_user][i].votingPower);
            }
        }
        return totalVP;
    }
    
    /**
     * @dev بروزرسانی voting power در governance
     */
    function _updateGovernanceVotingPower(address _user) internal {
        // در implementation واقعی، اینجا باید voting power در governance contract بروزرسانی شود
        // IGovernance(governanceContract).updateVotingPower(_user, _getUserTotalVotingPower(_user));
    }
    
    /**
     * @dev راه‌اندازی tiers پیش‌فرض
     */
    function _setupDefaultTiers() internal {
        // Tier 0: Flexible - 7 days lock, 5% APR
        tiers.push(StakingTier({
            name: "Flexible",
            minAmount: 100 ether,
            maxAmount: 0, // unlimited
            lockPeriod: 7 days,
            baseAPR: 500, // 5%
            votingMultiplier: 10000, // 1x
            rewardMultiplier: 10000, // 1x
            isActive: true,
            totalStaked: 0,
            maxCapacity: 0 // unlimited
        }));
        
        // Tier 1: Short Term - 30 days lock, 8% APR
        tiers.push(StakingTier({
            name: "Short Term",
            minAmount: 500 ether,
            maxAmount: 0,
            lockPeriod: 30 days,
            baseAPR: 800, // 8%
            votingMultiplier: 12000, // 1.2x
            rewardMultiplier: 11000, // 1.1x
            isActive: true,
            totalStaked: 0,
            maxCapacity: 0
        }));
        
        // Tier 2: Medium Term - 90 days lock, 12% APR
        tiers.push(StakingTier({
            name: "Medium Term",
            minAmount: 1000 ether,
            maxAmount: 0,
            lockPeriod: 90 days,
            baseAPR: 1200, // 12%
            votingMultiplier: 15000, // 1.5x
            rewardMultiplier: 13000, // 1.3x
            isActive: true,
            totalStaked: 0,
            maxCapacity: 0
        }));
        
        // Tier 3: Long Term - 180 days lock, 18% APR
        tiers.push(StakingTier({
            name: "Long Term",
            minAmount: 2500 ether,
            maxAmount: 0,
            lockPeriod: 180 days,
            baseAPR: 1800, // 18%
            votingMultiplier: 20000, // 2x
            rewardMultiplier: 15000, // 1.5x
            isActive: true,
            totalStaked: 0,
            maxCapacity: 0
        }));
        
        // Tier 4: Extended - 365 days lock, 25% APR
        tiers.push(StakingTier({
            name: "Extended",
            minAmount: 5000 ether,
            maxAmount: 0,
            lockPeriod: 365 days,
            baseAPR: 2500, // 25%
            votingMultiplier: 30000, // 3x
            rewardMultiplier: 20000, // 2x
            isActive: true,
            totalStaked: 0,
            maxCapacity: 0
        }));
    }
    
    /**
     * @dev شروع epoch جدید
     */
    function _startNewEpoch(uint256 _startTime, uint256 _endTime, uint256 _rewardPerSecond) internal {
        epochCounter++;
        
        currentEpoch = EpochInfo({
            startTime: _startTime,
            endTime: _endTime,
            rewardPerSecond: _rewardPerSecond,
            totalStaked: totalStaked,
            totalRewards: 0,
            isActive: true
        });
        
        epochHistory[epochCounter] = currentEpoch;
        
        emit EpochStarted(epochCounter, _startTime, _endTime, _rewardPerSecond);
    }
    
    // ==================== EMERGENCY FUNCTIONS ====================
    
    /**
     * @notice emergency unstake (ممکن است penalty داشته باشد)
     * @param _stakeId شناسه stake
     */
    function emergencyUnstake(uint256 _stakeId) external nonReentrant validStake(msg.sender, _stakeId) {
        UserStake storage userStake = userStakes[msg.sender][_stakeId];
        StakingTier storage tier = tiers[userStake.tierId];
        
        uint256 penalty = userStake.amount.mul(penaltyInfo.penaltyRate).div(BASIS_POINTS);
        uint256 unstakeAmount = userStake.amount.sub(penalty);
        
        // بروزرسانی آمار
        tier.totalStaked = tier.totalStaked.sub(userStake.amount);
        totalStaked = totalStaked.sub(userStake.amount);
        totalVotingPower = totalVotingPower.sub(userStake.votingPower);
        
        // غیرفعال کردن stake
        userStake.isActive = false;
        
        // انتقال tokens
        if (penalty > 0) {
            laxceToken.transfer(penaltyInfo.penaltyRecipient, penalty);
        }
        laxceToken.transfer(msg.sender, unstakeAmount);
        
        emit Unstaked(msg.sender, _stakeId, userStake.amount, penalty);
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
     * @notice تنظیم penalty info
     * @param _penaltyRate نرخ penalty
     * @param _gracePeriod دوره مهلت
     * @param _penaltyRecipient دریافت کننده penalty
     */
    function setPenaltyInfo(
        uint256 _penaltyRate,
        uint256 _gracePeriod,
        address _penaltyRecipient
    ) external onlyRole(OPERATOR_ROLE) {
        penaltyInfo = PenaltyInfo({
            penaltyRate: _penaltyRate,
            gracePeriod: _gracePeriod,
            penaltyRecipient: _penaltyRecipient
        });
        
        emit PenaltyInfoUpdated(_penaltyRate, _gracePeriod);
    }
    
    /**
     * @notice تنظیم compound و auto-extend
     * @param _compoundEnabled آیا compound فعال باشد
     * @param _autoExtendEnabled آیا auto-extend فعال باشد
     */
    function setFeatures(bool _compoundEnabled, bool _autoExtendEnabled) external onlyRole(OPERATOR_ROLE) {
        compoundEnabled = _compoundEnabled;
        autoExtendEnabled = _autoExtendEnabled;
    }
    
    /**
     * @notice تنظیم governance contract
     * @param _governanceContract آدرس کانترکت governance
     */
    function setGovernanceContract(address _governanceContract) external onlyRole(OPERATOR_ROLE) {
        governanceContract = _governanceContract;
    }
    
    /**
     * @notice شروع epoch جدید
     * @param _startTime زمان شروع
     * @param _endTime زمان پایان
     * @param _rewardPerSecond reward per second
     */
    function startNewEpoch(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rewardPerSecond
    ) external onlyRole(OPERATOR_ROLE) {
        if (_startTime >= _endTime) revert StakingManager__InvalidEpoch();
        
        _startNewEpoch(_startTime, _endTime, _rewardPerSecond);
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
     * @notice تغییر وضعیت emergency mode
     * @param _enabled آیا فعال باشد
     */
    function setEmergencyMode(bool _enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeToggled(_enabled);
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
     * @notice دریافت تعداد tiers
     */
    function tiersLength() external view returns (uint256) {
        return tiers.length;
    }
    
    /**
     * @notice دریافت اطلاعات tier
     * @param _tierId شناسه tier
     */
    function getTierInfo(uint256 _tierId) external view returns (StakingTier memory) {
        if (_tierId >= tiers.length) revert StakingManager__InvalidTier();
        return tiers[_tierId];
    }
    
    /**
     * @notice دریافت اطلاعات stake کاربر
     * @param _user آدرس کاربر
     * @param _stakeId شناسه stake
     */
    function getUserStake(address _user, uint256 _stakeId) external view returns (UserStake memory) {
        if (_stakeId >= userStakeCount[_user]) revert StakingManager__InvalidStakeId();
        return userStakes[_user][_stakeId];
    }
    
    /**
     * @notice محاسبه pending rewards
     * @param _user آدرس کاربر
     * @param _stakeId شناسه stake
     */
    function pendingRewards(address _user, uint256 _stakeId) external view returns (uint256) {
        return _calculatePendingRewards(_user, _stakeId);
    }
    
    /**
     * @notice دریافت کل voting power کاربر
     * @param _user آدرس کاربر
     */
    function getUserVotingPower(address _user) external view returns (uint256) {
        return _getUserTotalVotingPower(_user);
    }
    
    /**
     * @notice دریافت آمار کلی
     */
    function getGlobalStats() external view returns (
        uint256 totalStakedAmount,
        uint256 totalActiveStakes,
        uint256 totalVotingPowerAmount,
        uint256 currentRewardPool
    ) {
        totalStakedAmount = totalStaked;
        totalVotingPowerAmount = totalVotingPower;
        currentRewardPool = rewardPool;
        
        // محاسبه تعداد stakes فعال
        // در implementation واقعی باید tracker جداگانه‌ای داشته باشیم
    }
    
    /**
     * @notice دریافت APR واقعی tier
     * @param _tierId شناسه tier
     */
    function getTierAPR(uint256 _tierId) external view returns (uint256) {
        if (_tierId >= tiers.length) return 0;
        
        StakingTier storage tier = tiers[_tierId];
        return tier.baseAPR.mul(tier.rewardMultiplier).div(BASIS_POINTS);
    }
} 