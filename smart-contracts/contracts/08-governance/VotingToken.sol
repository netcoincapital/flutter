// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VotingToken
 * @dev توکن رای‌گیری برای DAO
 */
contract VotingToken is ERC20, ERC20Permit, ERC20Votes, Ownable, ReentrancyGuard {
    
    struct VestingSchedule {
        uint256 totalAmount;        // کل مقدار vesting
        uint256 releasedAmount;     // مقدار آزاد شده
        uint256 startTime;          // زمان شروع
        uint256 duration;           // مدت vesting
        uint256 cliffDuration;      // مدت cliff
        bool revoked;               // آیا لغو شده
    }

    struct StakeInfo {
        uint256 amount;             // مقدار stake شده
        uint256 lockEndTime;        // پایان lock
        uint256 multiplier;         // ضریب voting power
        bool autoExtend;            // تمدید خودکار
    }

    // Events
    event TokensLocked(address indexed user, uint256 amount, uint256 lockEndTime, uint256 multiplier);
    event TokensUnlocked(address indexed user, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 duration);
    event VestingRevoked(address indexed beneficiary, uint256 unvestedAmount);
    event DelegationChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    // State variables
    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(address => StakeInfo) public stakeInfo;
    mapping(uint256 => uint256) public lockMultipliers; // lock duration => multiplier
    
    uint256 public constant MAX_SUPPLY = 1000000000 * 10**18; // 1 billion tokens
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18; // 100 million initial
    
    // Lock periods and multipliers
    uint256 public constant WEEK = 7 days;
    uint256 public constant MONTH = 30 days;
    uint256 public constant YEAR = 365 days;
    
    // Vesting settings
    uint256 public constant MIN_VESTING_DURATION = 30 days;
    uint256 public constant MAX_VESTING_DURATION = 4 * YEAR;
    
    // Staking rewards
    uint256 public stakingRewardRate = 500; // 5% APR
    mapping(address => uint256) public lastRewardTime;
    mapping(address => uint256) public accumulatedRewards;
    
    bool public vestingEnabled = true;
    bool public stakingEnabled = true;

    error InvalidAmount();
    error InsufficientBalance();
    error TokensLocked();
    error VestingNotEnabled();
    error StakingNotEnabled();
    error InvalidLockPeriod();
    error VestingAlreadyExists();
    error NoVestingSchedule();

    constructor() 
        ERC20("LAXCE Governance Token", "vLAXCE") 
        ERC20Permit("LAXCE Governance Token")
        Ownable(msg.sender)
    {
        // Mint initial supply
        _mint(msg.sender, INITIAL_SUPPLY);
        
        // Initialize lock multipliers
        lockMultipliers[0] = 100;           // No lock: 1x
        lockMultipliers[WEEK] = 110;        // 1 week: 1.1x
        lockMultipliers[MONTH] = 125;       // 1 month: 1.25x
        lockMultipliers[3 * MONTH] = 150;   // 3 months: 1.5x
        lockMultipliers[6 * MONTH] = 200;   // 6 months: 2x
        lockMultipliers[YEAR] = 300;        // 1 year: 3x
        lockMultipliers[2 * YEAR] = 400;    // 2 years: 4x
        lockMultipliers[4 * YEAR] = 500;    // 4 years: 5x
    }

    /**
     * @dev Lock tokens برای افزایش voting power
     * @param amount مقدار token
     * @param lockDuration مدت lock
     * @param autoExtend تمدید خودکار
     */
    function lockTokens(
        uint256 amount,
        uint256 lockDuration,
        bool autoExtend
    ) external nonReentrant {
        if (!stakingEnabled) revert StakingNotEnabled();
        if (amount == 0) revert InvalidAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (lockMultipliers[lockDuration] == 0) revert InvalidLockPeriod();

        StakeInfo storage stake = stakeInfo[msg.sender];
        
        // اگر قبلاً stake کرده، ابتدا reward را claim کن
        if (stake.amount > 0) {
            _claimStakingRewards(msg.sender);
        }

        // انتقال tokens به contract
        _transfer(msg.sender, address(this), amount);

        // به‌روزرسانی stake info
        stake.amount += amount;
        stake.lockEndTime = block.timestamp + lockDuration;
        stake.multiplier = lockMultipliers[lockDuration];
        stake.autoExtend = autoExtend;

        // به‌روزرسانی reward tracking
        lastRewardTime[msg.sender] = block.timestamp;

        emit TokensLocked(msg.sender, amount, stake.lockEndTime, stake.multiplier);
    }

    /**
     * @dev Unlock tokens بعد از پایان lock period
     */
    function unlockTokens() external nonReentrant {
        StakeInfo storage stake = stakeInfo[msg.sender];
        
        if (stake.amount == 0) revert InvalidAmount();
        if (block.timestamp < stake.lockEndTime && !stake.autoExtend) revert TokensLocked();

        // Claim rewards
        _claimStakingRewards(msg.sender);

        uint256 amount = stake.amount;
        
        // Reset stake info
        stake.amount = 0;
        stake.lockEndTime = 0;
        stake.multiplier = 100;
        stake.autoExtend = false;

        // برگرداندن tokens
        _transfer(address(this), msg.sender, amount);

        emit TokensUnlocked(msg.sender, amount);
    }

    /**
     * @dev Claim staking rewards
     */
    function claimStakingRewards() external nonReentrant {
        _claimStakingRewards(msg.sender);
    }

    /**
     * @dev ایجاد vesting schedule
     * @param beneficiary آدرس beneficiary
     * @param amount مقدار کل
     * @param duration مدت vesting
     * @param cliffDuration mدت cliff
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 duration,
        uint256 cliffDuration
    ) external onlyOwner {
        if (!vestingEnabled) revert VestingNotEnabled();
        if (beneficiary == address(0)) revert InvalidAmount();
        if (amount == 0) revert InvalidAmount();
        if (duration < MIN_VESTING_DURATION || duration > MAX_VESTING_DURATION) revert InvalidAmount();
        if (cliffDuration > duration) revert InvalidAmount();
        if (vestingSchedules[beneficiary].totalAmount > 0) revert VestingAlreadyExists();

        // Mint tokens for vesting
        _mint(address(this), amount);

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            duration: duration,
            cliffDuration: cliffDuration,
            revoked: false
        });

        emit VestingScheduleCreated(beneficiary, amount, duration);
    }

    /**
     * @dev Release vested tokens
     */
    function releaseVestedTokens() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        
        if (schedule.totalAmount == 0) revert NoVestingSchedule();
        if (schedule.revoked) revert NoVestingSchedule();

        uint256 releasableAmount = _calculateReleasableAmount(msg.sender);
        if (releasableAmount == 0) revert InvalidAmount();

        schedule.releasedAmount += releasableAmount;
        _transfer(address(this), msg.sender, releasableAmount);
    }

    /**
     * @dev لغو vesting schedule (فقط owner)
     * @param beneficiary آدرس beneficiary
     */
    function revokeVesting(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        if (schedule.revoked) revert NoVestingSchedule();
        if (schedule.totalAmount == 0) revert NoVestingSchedule();

        uint256 releasableAmount = _calculateReleasableAmount(beneficiary);
        if (releasableAmount > 0) {
            schedule.releasedAmount += releasableAmount;
            _transfer(address(this), beneficiary, releasableAmount);
        }

        uint256 unvestedAmount = schedule.totalAmount - schedule.releasedAmount;
        schedule.revoked = true;

        // Burn unvested tokens
        if (unvestedAmount > 0) {
            _burn(address(this), unvestedAmount);
        }

        emit VestingRevoked(beneficiary, unvestedAmount);
    }

    /**
     * @dev محاسبه voting power کاربر
     * @param account آدرس کاربر
     * @return power voting power
     */
    function getVotingPower(address account) external view returns (uint256 power) {
        uint256 balance = balanceOf(account);
        StakeInfo storage stake = stakeInfo[account];
        
        // Base voting power از balance
        power = balance;
        
        // اضافه کردن bonus از staked tokens
        if (stake.amount > 0) {
            uint256 bonusPower = (stake.amount * stake.multiplier) / 100;
            power += bonusPower - stake.amount; // فقط bonus اضافه می‌کنیم
        }
    }

    /**
     * @dev دریافت releasable amount برای vesting
     * @param beneficiary آدرس beneficiary
     * @return amount مقدار قابل release
     */
    function getReleasableAmount(address beneficiary) external view returns (uint256 amount) {
        return _calculateReleasableAmount(beneficiary);
    }

    /**
     * @dev دریافت staking rewards
     * @param account آدرス کاربر
     * @return rewards pending rewards
     */
    function getPendingRewards(address account) external view returns (uint256 rewards) {
        StakeInfo storage stake = stakeInfo[account];
        if (stake.amount == 0) return 0;

        uint256 timeDiff = block.timestamp - lastRewardTime[account];
        rewards = (stake.amount * stakingRewardRate * timeDiff) / (365 days * 10000); // APR calculation
        rewards += accumulatedRewards[account];
    }

    /**
     * @dev تنظیم staking reward rate
     * @param rate نرخ جدید (basis points)
     */
    function setStakingRewardRate(uint256 rate) external onlyOwner {
        require(rate <= 2000, "Rate too high"); // حداکثر 20%
        stakingRewardRate = rate;
    }

    /**
     * @dev فعال/غیرفعال کردن vesting
     * @param enabled وضعیت
     */
    function setVestingEnabled(bool enabled) external onlyOwner {
        vestingEnabled = enabled;
    }

    /**
     * @dev فعال/غیرفعال کردن staking
     * @param enabled وضعیت
     */
    function setStakingEnabled(bool enabled) external onlyOwner {
        stakingEnabled = enabled;
    }

    /**
     * @dev Mint additional tokens (با محدودیت)
     * @param to آدرس مقصد
     * @param amount مقدار
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @dev محاسبه releasable amount داخلی
     */
    function _calculateReleasableAmount(address beneficiary) internal view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        if (schedule.revoked || block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }

        uint256 elapsed = block.timestamp - schedule.startTime;
        if (elapsed >= schedule.duration) {
            return schedule.totalAmount - schedule.releasedAmount;
        }

        uint256 vestedAmount = (schedule.totalAmount * elapsed) / schedule.duration;
        return vestedAmount - schedule.releasedAmount;
    }

    /**
     * @dev Claim staking rewards داخلی
     */
    function _claimStakingRewards(address account) internal {
        StakeInfo storage stake = stakeInfo[account];
        if (stake.amount == 0) return;

        uint256 timeDiff = block.timestamp - lastRewardTime[account];
        uint256 rewards = (stake.amount * stakingRewardRate * timeDiff) / (365 days * 10000);
        rewards += accumulatedRewards[account];

        if (rewards > 0) {
            accumulatedRewards[account] = 0;
            lastRewardTime[account] = block.timestamp;
            
            // Mint reward tokens
            if (totalSupply() + rewards <= MAX_SUPPLY) {
                _mint(account, rewards);
            } else {
                // اگر supply کافی نیست، در accumulated ذخیره کن
                accumulatedRewards[account] = rewards;
            }
        }
    }

    // Override required functions for multiple inheritance
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}