// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../01-core/AccessControl.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";

/**
 * @title LAXCE
 * @dev توکن اصلی پلتفرم LAXCE DEX با قابلیت‌های پیشرفته
 * @notice این توکن شامل قابلیت‌های governance، fee discount، locking و revenue sharing است
 */
contract LAXCE is 
    ERC20, 
    ERC20Burnable, 
    ERC20Votes, 
    ERC20Permit, 
    Pausable, 
    LaxceAccessControl 
{

    using Address for address;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر supply (1 میلیارد توکن)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev تعداد اولیه توکن‌ها (500 میلیون)
    uint256 public constant INITIAL_SUPPLY = 500_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev سهم team (20%)
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev سهم treasury (15%)
    uint256 public constant TREASURY_ALLOCATION = 150_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev سهم marketing (10%)
    uint256 public constant MARKETING_ALLOCATION = 100_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev سهم liquidity bootstrap (15%)
    uint256 public constant LIQUIDITY_ALLOCATION = 150_000_000 * Constants.DECIMAL_BASE;
    
    /// @dev حداکثر تخفیف fee (50%)
    uint256 public constant MAX_FEE_DISCOUNT = 5000; // 50%
    
    /// @dev حداقل مدت lock (7 روز)
    uint256 public constant MIN_LOCK_DURATION = 7 days;
    
    /// @dev حداکثر مدت lock (4 سال)
    uint256 public constant MAX_LOCK_DURATION = 4 * 365 days;
    
    // ==================== STRUCTS ====================
    
    /// @dev اطلاعات lock شده توکن‌ها
    struct LockInfo {
        uint256 amount;         // مقدار lock شده
        uint256 lockTime;       // زمان lock
        uint256 unlockTime;     // زمان unlock
        uint256 multiplier;     // ضریب voting power
        bool autoExtend;        // تمدید خودکار
        uint256 lastRewardTime; // آخرین زمان دریافت reward
    }
    
    /// @dev اطلاعات fee discount
    struct DiscountInfo {
        uint256 minBalance;     // حداقل balance برای تخفیف
        uint256 discountRate;   // درصد تخفیف
        bool active;            // فعال بودن
    }
    
    /// @dev اطلاعات revenue sharing
    struct RevenueInfo {
        uint256 totalRewards;   // کل rewards
        uint256 claimedRewards; // rewards دریافت شده
        uint256 lastUpdateTime; // آخرین به‌روزرسانی
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev محافظت از reentrancy
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev mapping برای lock شده توکن‌ها
    mapping(address => LockInfo[]) public userLocks;
    
    /// @dev mapping برای fee discounts
    mapping(uint256 => DiscountInfo) public feeDiscounts;
    
    /// @dev mapping برای revenue sharing
    mapping(address => RevenueInfo) public revenueSharing;
    
    /// @dev کل توکن‌های lock شده
    uint256 public totalLocked;
    
    /// @dev کل voting power
    uint256 public totalVotingPower;
    
    /// @dev آدرس treasury
    address public treasury;
    
    /// @dev آدرس team wallet
    address public teamWallet;
    
    /// @dev آدرس marketing wallet
    address public marketingWallet;
    
    /// @dev نرخ پاداش سالانه (APR)
    uint256 public rewardAPR = 1000; // 10%
    
    /// @dev pool پاداش‌ها
    uint256 public rewardPool;
    
    /// @dev آیا phase اولیه تمام شده
    bool public initialPhaseCompleted;
    
    /// @dev آخرین زمان distribution rewards
    uint256 public lastRewardDistribution;
    
    /// @dev تعداد tier های fee discount
    uint256 public discountTiersCount;
    
    // ==================== EVENTS ====================
    
    event TokensLocked(address indexed user, uint256 amount, uint256 duration, uint256 multiplier);
    event TokensUnlocked(address indexed user, uint256 amount, uint256 lockIndex);
    event LockExtended(address indexed user, uint256 lockIndex, uint256 newUnlockTime);
    event RewardsDistributed(uint256 totalAmount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event FeeDiscountUpdated(uint256 tier, uint256 minBalance, uint256 discountRate);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event RewardAPRUpdated(uint256 oldAPR, uint256 newAPR);
    event InitialPhaseCompleted(uint256 timestamp);
    
    // ==================== ERRORS ====================
    
    error LAXCE__InsufficientBalance();
    error LAXCE__InvalidLockDuration();
    error LAXCE__LockNotFound();
    error LAXCE__LockNotExpired();
    error LAXCE__ZeroAmount();
    error LAXCE__ZeroAddress();
    error LAXCE__ExceedsMaxSupply();
    error LAXCE__InitialPhaseNotCompleted();
    error LAXCE__InvalidDiscountRate();
    error LAXCE__TierNotFound();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validAddress(address addr) {
        if (addr == address(0)) revert LAXCE__ZeroAddress();
        _;
    }
    
    modifier initialPhaseComplete() {
        if (!initialPhaseCompleted) revert LAXCE__InitialPhaseNotCompleted();
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _treasury,
        address _teamWallet,
        address _marketingWallet
    ) 
        ERC20("LAXCE", "LAXCE") 
        ERC20Permit("LAXCE") 
        validAddress(_treasury)
        validAddress(_teamWallet)
        validAddress(_marketingWallet)
    {
        // تنظیم آدرس‌ها
        treasury = _treasury;
        teamWallet = _teamWallet;
        marketingWallet = _marketingWallet;
        
        // مقداردهی اولیه reentrancy guard
        _reentrancyGuard.initialize();
        
        // mint کردن initial supply
        _mint(msg.sender, INITIAL_SUPPLY);
        
        // تنظیم زمان آخرین distribution
        lastRewardDistribution = block.timestamp;
        
        // تنظیم fee discount tiers
        _setupInitialDiscountTiers();
        
        emit InitialPhaseCompleted(block.timestamp);
    }
    
    // ==================== LOCK FUNCTIONS ====================
    
    /**
     * @dev lock کردن توکن‌ها برای voting power و rewards
     * @param amount مقدار توکن برای lock
     * @param duration مدت زمان lock (ثانیه)
     * @param autoExtend تمدید خودکار یا نه
     */
    function lockTokens(
        uint256 amount,
        uint256 duration,
        bool autoExtend
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert LAXCE__ZeroAmount();
        if (duration < MIN_LOCK_DURATION || duration > MAX_LOCK_DURATION) {
            revert LAXCE__InvalidLockDuration();
        }
        if (balanceOf(msg.sender) < amount) revert LAXCE__InsufficientBalance();
        
        // محاسبه multiplier بر اساس duration
        uint256 multiplier = _calculateLockMultiplier(duration);
        
        // ایجاد lock جدید
        LockInfo memory newLock = LockInfo({
            amount: amount,
            lockTime: block.timestamp,
            unlockTime: block.timestamp + duration,
            multiplier: multiplier,
            autoExtend: autoExtend,
            lastRewardTime: block.timestamp
        });
        
        // اضافه کردن به لیست locks کاربر
        userLocks[msg.sender].push(newLock);
        
        // به‌روزرسانی آمار کلی
        totalLocked = totalLocked.add(amount);
        totalVotingPower = totalVotingPower.add(amount.mul(multiplier).div(Constants.FEE_BASE));
        
        // انتقال توکن‌ها
        _transfer(msg.sender, address(this), amount);
        
        emit TokensLocked(msg.sender, amount, duration, multiplier);
    }
    
    /**
     * @dev unlock کردن توکن‌ها
     * @param lockIndex ایندکس lock
     */
    function unlockTokens(uint256 lockIndex) external nonReentrant {
        LockInfo[] storage locks = userLocks[msg.sender];
        
        if (lockIndex >= locks.length) revert LAXCE__LockNotFound();
        
        LockInfo storage lockInfo = locks[lockIndex];
        
        if (block.timestamp < lockInfo.unlockTime) {
            revert LAXCE__LockNotExpired();
        }
        
        uint256 amount = lockInfo.amount;
        uint256 multiplier = lockInfo.multiplier;
        
        // کسر از آمار کلی
        totalLocked = totalLocked.sub(amount);
        totalVotingPower = totalVotingPower.sub(amount.mul(multiplier).div(Constants.FEE_BASE));
        
        // حذف lock از لیست
        locks[lockIndex] = locks[locks.length - 1];
        locks.pop();
        
        // بازگشت توکن‌ها
        _transfer(address(this), msg.sender, amount);
        
        emit TokensUnlocked(msg.sender, amount, lockIndex);
    }
    
    /**
     * @dev تمدید lock
     * @param lockIndex ایندکس lock
     * @param additionalDuration مدت اضافی
     */
    function extendLock(
        uint256 lockIndex,
        uint256 additionalDuration
    ) external nonReentrant {
        LockInfo[] storage locks = userLocks[msg.sender];
        
        if (lockIndex >= locks.length) revert LAXCE__LockNotFound();
        
        LockInfo storage lockInfo = locks[lockIndex];
        
        uint256 newUnlockTime = lockInfo.unlockTime.add(additionalDuration);
        uint256 totalDuration = newUnlockTime.sub(lockInfo.lockTime);
        
        if (totalDuration > MAX_LOCK_DURATION) {
            revert LAXCE__InvalidLockDuration();
        }
        
        // محاسبه multiplier جدید
        uint256 oldMultiplier = lockInfo.multiplier;
        uint256 newMultiplier = _calculateLockMultiplier(totalDuration);
        
        // به‌روزرسانی voting power
        uint256 amount = lockInfo.amount;
        totalVotingPower = totalVotingPower
            .sub(amount.mul(oldMultiplier).div(Constants.FEE_BASE))
            .add(amount.mul(newMultiplier).div(Constants.FEE_BASE));
        
        // به‌روزرسانی lock
        lockInfo.unlockTime = newUnlockTime;
        lockInfo.multiplier = newMultiplier;
        
        emit LockExtended(msg.sender, lockIndex, newUnlockTime);
    }
    
    // ==================== REWARD FUNCTIONS ====================
    
    /**
     * @dev توزیع rewards به holders
     */
    function distributeRewards() external onlyValidRole(ADMIN_ROLE) {
        if (totalLocked == 0) return;
        
        uint256 timeSinceLastDistribution = block.timestamp.sub(lastRewardDistribution);
        uint256 annualReward = totalLocked.mul(rewardAPR).div(Constants.FEE_BASE);
        uint256 rewardAmount = annualReward.mul(timeSinceLastDistribution).div(365 days);
        
        // بررسی موجودی reward pool
        if (rewardPool < rewardAmount) {
            rewardAmount = rewardPool;
        }
        
        if (rewardAmount > 0) {
            rewardPool = rewardPool.sub(rewardAmount);
            lastRewardDistribution = block.timestamp;
            
            emit RewardsDistributed(rewardAmount, block.timestamp);
        }
    }
    
    /**
     * @dev claim کردن rewards
     */
    function claimRewards() external nonReentrant {
        uint256 rewards = _calculateUserRewards(msg.sender);
        
        if (rewards > 0) {
            revenueSharing[msg.sender].claimedRewards = 
                revenueSharing[msg.sender].claimedRewards.add(rewards);
            revenueSharing[msg.sender].lastUpdateTime = block.timestamp;
            
            _transfer(address(this), msg.sender, rewards);
            
            emit RewardsClaimed(msg.sender, rewards);
        }
    }
    
    /**
     * @dev محاسبه rewards یک کاربر
     * @param user آدرس کاربر
     * @return مقدار rewards
     */
    function getUserRewards(address user) external view returns (uint256) {
        return _calculateUserRewards(user);
    }
    
    // ==================== FEE DISCOUNT FUNCTIONS ====================
    
    /**
     * @dev محاسبه تخفیف fee برای کاربر
     * @param user آدرس کاربر
     * @return درصد تخفیف (basis points)
     */
    function getFeeDiscount(address user) external view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        uint256 lockedBalance = _getTotalLockedBalance(user);
        uint256 effectiveBalance = userBalance.add(lockedBalance);
        
        uint256 maxDiscount = 0;
        
        // پیدا کردن بالاترین tier قابل اعمال
        for (uint256 i = 0; i < discountTiersCount; i++) {
            DiscountInfo storage tier = feeDiscounts[i];
            if (tier.active && effectiveBalance >= tier.minBalance) {
                if (tier.discountRate > maxDiscount) {
                    maxDiscount = tier.discountRate;
                }
            }
        }
        
        return maxDiscount;
    }
    
    /**
     * @dev تنظیم tier جدید برای fee discount
     * @param tier شماره tier
     * @param minBalance حداقل balance
     * @param discountRate درصد تخفیف
     */
    function setFeeDiscountTier(
        uint256 tier,
        uint256 minBalance,
        uint256 discountRate
    ) external onlyValidRole(ADMIN_ROLE) {
        if (discountRate > MAX_FEE_DISCOUNT) revert LAXCE__InvalidDiscountRate();
        
        feeDiscounts[tier] = DiscountInfo({
            minBalance: minBalance,
            discountRate: discountRate,
            active: true
        });
        
        if (tier >= discountTiersCount) {
            discountTiersCount = tier + 1;
        }
        
        emit FeeDiscountUpdated(tier, minBalance, discountRate);
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev mint کردن توکن‌های جدید
     * @param to آدرس دریافت‌کننده
     * @param amount مقدار
     */
    function mint(address to, uint256 amount) 
        external 
        onlyValidRole(ADMIN_ROLE) 
        validAddress(to) 
    {
        if (totalSupply().add(amount) > MAX_SUPPLY) {
            revert LAXCE__ExceedsMaxSupply();
        }
        
        _mint(to, amount);
    }
    
    /**
     * @dev افزودن به reward pool
     * @param amount مقدار
     */
    function addToRewardPool(uint256 amount) 
        external 
        onlyValidRole(TREASURY_ROLE) 
    {
        if (amount == 0) revert LAXCE__ZeroAmount();
        
        _transfer(msg.sender, address(this), amount);
        rewardPool = rewardPool.add(amount);
    }
    
    /**
     * @dev تنظیم نرخ پاداش
     * @param newAPR نرخ جدید (basis points)
     */
    function setRewardAPR(uint256 newAPR) 
        external 
        onlyValidRole(ADMIN_ROLE) 
    {
        uint256 oldAPR = rewardAPR;
        rewardAPR = newAPR;
        
        emit RewardAPRUpdated(oldAPR, newAPR);
    }
    
    /**
     * @dev تنظیم آدرس treasury
     * @param newTreasury آدرس جدید
     */
    function setTreasury(address newTreasury) 
        external 
        onlyValidRole(OWNER_ROLE) 
        validAddress(newTreasury) 
    {
        address oldTreasury = treasury;
        treasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
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
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت تعداد locks یک کاربر
     * @param user آدرس کاربر
     * @return تعداد locks
     */
    function getUserLocksCount(address user) external view returns (uint256) {
        return userLocks[user].length;
    }
    
    /**
     * @dev دریافت اطلاعات lock خاص
     * @param user آدرس کاربر
     * @param lockIndex ایندکس lock
     * @return اطلاعات lock
     */
    function getLockInfo(address user, uint256 lockIndex) 
        external 
        view 
        returns (LockInfo memory) 
    {
        if (lockIndex >= userLocks[user].length) revert LAXCE__LockNotFound();
        return userLocks[user][lockIndex];
    }
    
    /**
     * @dev دریافت voting power کاربر
     * @param user آدرس کاربر
     * @return voting power
     */
    function getVotingPower(address user) external view returns (uint256) {
        uint256 votingPower = 0;
        LockInfo[] storage locks = userLocks[user];
        
        for (uint256 i = 0; i < locks.length; i++) {
            LockInfo storage lockInfo = locks[i];
            votingPower = votingPower.add(
                lockInfo.amount.mul(lockInfo.multiplier).div(Constants.FEE_BASE)
            );
        }
        
        return votingPower;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev محاسبه multiplier بر اساس مدت lock
     * @param duration مدت lock
     * @return multiplier
     */
    function _calculateLockMultiplier(uint256 duration) internal pure returns (uint256) {
        // Base multiplier = 1x (10000 basis points)
        // Max multiplier = 4x (40000 basis points) برای 4 سال
        uint256 baseMultiplier = Constants.FEE_BASE;
        uint256 maxMultiplier = 4 * Constants.FEE_BASE;
        
        uint256 multiplier = baseMultiplier.add(
            duration.mul(maxMultiplier.sub(baseMultiplier)).div(MAX_LOCK_DURATION)
        );
        
        return multiplier;
    }
    
    /**
     * @dev محاسبه rewards کاربر
     * @param user آدرس کاربر
     * @return مقدار rewards
     */
    function _calculateUserRewards(address user) internal view returns (uint256) {
        uint256 userVotingPower = 0;
        LockInfo[] storage locks = userLocks[user];
        
        for (uint256 i = 0; i < locks.length; i++) {
            LockInfo storage lockInfo = locks[i];
            userVotingPower = userVotingPower.add(
                lockInfo.amount.mul(lockInfo.multiplier).div(Constants.FEE_BASE)
            );
        }
        
        if (totalVotingPower == 0) return 0;
        
        uint256 userShare = userVotingPower.mul(Constants.FEE_BASE).div(totalVotingPower);
        uint256 totalRewards = revenueSharing[user].totalRewards;
        uint256 claimedRewards = revenueSharing[user].claimedRewards;
        
        return totalRewards.mul(userShare).div(Constants.FEE_BASE).sub(claimedRewards);
    }
    
    /**
     * @dev دریافت کل balance lock شده کاربر
     * @param user آدرس کاربر
     * @return کل balance lock شده
     */
    function _getTotalLockedBalance(address user) internal view returns (uint256) {
        uint256 totalLocked_ = 0;
        LockInfo[] storage locks = userLocks[user];
        
        for (uint256 i = 0; i < locks.length; i++) {
            totalLocked_ = totalLocked_.add(locks[i].amount);
        }
        
        return totalLocked_;
    }
    
    /**
     * @dev تنظیم اولیه discount tiers
     */
    function _setupInitialDiscountTiers() internal {
        // Tier 0: 1000 LAXCE = 5% discount
        feeDiscounts[0] = DiscountInfo({
            minBalance: 1000 * Constants.DECIMAL_BASE,
            discountRate: 500, // 5%
            active: true
        });
        
        // Tier 1: 5000 LAXCE = 15% discount
        feeDiscounts[1] = DiscountInfo({
            minBalance: 5000 * Constants.DECIMAL_BASE,
            discountRate: 1500, // 15%
            active: true
        });
        
        // Tier 2: 25000 LAXCE = 30% discount
        feeDiscounts[2] = DiscountInfo({
            minBalance: 25000 * Constants.DECIMAL_BASE,
            discountRate: 3000, // 30%
            active: true
        });
        
        // Tier 3: 100000 LAXCE = 50% discount
        feeDiscounts[3] = DiscountInfo({
            minBalance: 100000 * Constants.DECIMAL_BASE,
            discountRate: 5000, // 50%
            active: true
        });
        
        discountTiersCount = 4;
    }
    
    // ==================== OVERRIDES ====================
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
    
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }
    
    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }
    
    function _burn(
        address from,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._burn(from, amount);
    }
} 