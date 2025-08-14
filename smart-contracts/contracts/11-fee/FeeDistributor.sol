// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";
import "../libraries/FullMath.sol";

/**
 * @title FeeDistributor
 * @dev توزیع fees بین LP token holders
 */
contract FeeDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    struct LPReward {
        uint256 totalRewards;       // کل rewards دریافتی
        uint256 pendingRewards;     // rewards در انتظار claim
        uint256 lastClaimTime;      // آخرین زمان claim
        uint256 rewardPerTokenPaid; // reward per token پرداخت شده
    }

    struct PoolRewardData {
        uint256 totalDistributed;   // کل fee توزیع شده
        uint256 rewardPerToken;     // reward per LP token
        uint256 lastUpdateTime;     // آخرین به‌روزرسانی
        uint256 rewardRate;         // نرخ reward per second
        uint256 periodFinish;       // پایان دوره reward
        mapping(address => LPReward) lpRewards; // LP => reward data
    }

    // Events
    event FeesDistributed(
        address indexed pool,
        address indexed token,
        uint256 amount,
        uint256 rewardPerToken
    );

    event RewardClaimed(
        address indexed user,
        address indexed pool,
        address indexed token,
        uint256 amount
    );

    event RewardAdded(
        address indexed pool,
        address indexed token,
        uint256 reward,
        uint256 duration
    );

    // State variables
    mapping(address => mapping(address => PoolRewardData)) public poolRewards; // pool => token => data
    mapping(address => bool) public authorizedDistributors;
    mapping(address => address) public poolLPTokens; // pool => LP token address
    
    uint256 public constant REWARD_DURATION = 7 days; // مدت توزیع rewards
    uint256 public constant MIN_CLAIM_INTERVAL = 1 hours; // حداقل فاصله بین claim ها
    uint256 public constant PRECISION = 1e18;

    error UnauthorizedDistributor();
    error InvalidPool();
    error InvalidToken();
    error NoRewardsToClaim();
    error ClaimTooFrequent();
    error InsufficientLPBalance();

    modifier onlyAuthorizedDistributor() {
        if (!authorizedDistributors[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedDistributor();
        }
        _;
    }

    modifier updateReward(address pool, address token, address user) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        poolData.rewardPerToken = _rewardPerToken(pool, token);
        poolData.lastUpdateTime = _lastTimeRewardApplicable(pool, token);
        
        if (user != address(0)) {
            LPReward storage userReward = poolData.lpRewards[user];
            userReward.pendingRewards = _earned(pool, token, user);
            userReward.rewardPerTokenPaid = poolData.rewardPerToken;
        }
        _;
    }

    constructor() Ownable(msg.sender) {
        authorizedDistributors[msg.sender] = true;
    }

    /**
     * @dev توزیع fees بین LP token holders
     * @param pool آدرس pool
     * @param token آدرس reward token
     * @param amount مقدار fee برای توزیع
     */
    function distributeLPFees(
        address pool,
        address token,
        uint256 amount
    ) external onlyAuthorizedDistributor nonReentrant updateReward(pool, token, address(0)) {
        if (pool == address(0) || token == address(0)) revert InvalidPool();
        if (amount == 0) return;

        // دریافت token از caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        PoolRewardData storage poolData = poolRewards[pool][token];
        
        if (block.timestamp >= poolData.periodFinish) {
            // شروع دوره جدید
            poolData.rewardRate = amount / REWARD_DURATION;
        } else {
            // ادامه دوره فعلی
            uint256 remaining = poolData.periodFinish - block.timestamp;
            uint256 leftover = remaining * poolData.rewardRate;
            poolData.rewardRate = (amount + leftover) / REWARD_DURATION;
        }

        poolData.lastUpdateTime = block.timestamp;
        poolData.periodFinish = block.timestamp + REWARD_DURATION;
        poolData.totalDistributed += amount;

        emit FeesDistributed(pool, token, amount, poolData.rewardPerToken);
        emit RewardAdded(pool, token, amount, REWARD_DURATION);
    }

    /**
     * @dev claim rewards توسط LP token holder
     * @param pool آدرس pool
     * @param token آدرس reward token
     */
    function claimReward(
        address pool,
        address token
    ) external nonReentrant updateReward(pool, token, msg.sender) {
        LPReward storage userReward = poolRewards[pool][token].lpRewards[msg.sender];
        
        if (userReward.pendingRewards == 0) revert NoRewardsToClaim();
        if (block.timestamp < userReward.lastClaimTime + MIN_CLAIM_INTERVAL) {
            revert ClaimTooFrequent();
        }

        uint256 reward = userReward.pendingRewards;
        userReward.pendingRewards = 0;
        userReward.totalRewards += reward;
        userReward.lastClaimTime = block.timestamp;

        IERC20(token).safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, pool, token, reward);
    }

    /**
     * @dev claim rewards از چندین pool و token
     * @param pools آرایه pools
     * @param tokens آرایه tokens
     */
    function claimMultipleRewards(
        address[] calldata pools,
        address[] calldata tokens
    ) external nonReentrant {
        require(pools.length == tokens.length, "Array length mismatch");
        
        for (uint256 i = 0; i < pools.length; i++) {
            _claimRewardInternal(pools[i], tokens[i], msg.sender);
        }
    }

    /**
     * @dev ثبت LP token برای pool
     * @param pool آدرس pool
     * @param lpToken آدرس LP token
     */
    function registerPoolLPToken(address pool, address lpToken) external onlyOwner {
        if (pool == address(0) || lpToken == address(0)) revert InvalidPool();
        poolLPTokens[pool] = lpToken;
    }

    /**
     * @dev اضافه کردن authorized distributor
     * @param distributor آدرس distributor
     */
    function addAuthorizedDistributor(address distributor) external onlyOwner {
        if (distributor == address(0)) revert InvalidToken();
        authorizedDistributors[distributor] = true;
    }

    /**
     * @dev حذف authorized distributor
     * @param distributor آدرس distributor
     */
    function removeAuthorizedDistributor(address distributor) external onlyOwner {
        authorizedDistributors[distributor] = false;
    }

    /**
     * @dev دریافت pending rewards کاربر
     * @param pool آدرس pool
     * @param token آدرس token
     * @param user آدرس کاربر
     * @return amount مقدار pending reward
     */
    function getPendingReward(
        address pool,
        address token,
        address user
    ) external view returns (uint256 amount) {
        return _earned(pool, token, user);
    }

    /**
     * @dev دریافت اطلاعات reward کاربر
     * @param pool آدرس pool
     * @param token آدرس token
     * @param user آدرس کاربر
     */
    function getUserRewardInfo(
        address pool,
        address token,
        address user
    ) external view returns (
        uint256 totalRewards,
        uint256 pendingRewards,
        uint256 lastClaimTime,
        uint256 rewardPerTokenPaid
    ) {
        LPReward storage userReward = poolRewards[pool][token].lpRewards[user];
        return (
            userReward.totalRewards,
            _earned(pool, token, user),
            userReward.lastClaimTime,
            userReward.rewardPerTokenPaid
        );
    }

    /**
     * @dev دریافت اطلاعات pool reward
     * @param pool آدرس pool
     * @param token آدرس token
     */
    function getPoolRewardInfo(
        address pool,
        address token
    ) external view returns (
        uint256 totalDistributed,
        uint256 rewardPerToken,
        uint256 rewardRate,
        uint256 periodFinish,
        uint256 lastUpdateTime
    ) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        return (
            poolData.totalDistributed,
            _rewardPerToken(pool, token),
            poolData.rewardRate,
            poolData.periodFinish,
            poolData.lastUpdateTime
        );
    }

    /**
     * @dev محاسبه reward per token
     */
    function _rewardPerToken(address pool, address token) internal view returns (uint256) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        address lpToken = poolLPTokens[pool];
        
        if (lpToken == address(0)) return poolData.rewardPerToken;
        
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        if (totalSupply == 0) {
            return poolData.rewardPerToken;
        }

        return poolData.rewardPerToken + (
            (_lastTimeRewardApplicable(pool, token) - poolData.lastUpdateTime) *
            poolData.rewardRate *
            PRECISION /
            totalSupply
        );
    }

    /**
     * @dev محاسبه earned rewards
     */
    function _earned(address pool, address token, address user) internal view returns (uint256) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        LPReward storage userReward = poolData.lpRewards[user];
        address lpToken = poolLPTokens[pool];
        
        if (lpToken == address(0)) return userReward.pendingRewards;
        
        uint256 userBalance = IERC20(lpToken).balanceOf(user);
        return userBalance *
            (_rewardPerToken(pool, token) - userReward.rewardPerTokenPaid) /
            PRECISION +
            userReward.pendingRewards;
    }

    /**
     * @dev آخرین زمان قابل اعمال reward
     */
    function _lastTimeRewardApplicable(address pool, address token) internal view returns (uint256) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        return block.timestamp < poolData.periodFinish ? block.timestamp : poolData.periodFinish;
    }

    /**
     * @dev claim reward داخلی
     */
    function _claimRewardInternal(address pool, address token, address user) internal 
        updateReward(pool, token, user) {
        LPReward storage userReward = poolRewards[pool][token].lpRewards[user];
        
        if (userReward.pendingRewards == 0) return;
        if (block.timestamp < userReward.lastClaimTime + MIN_CLAIM_INTERVAL) return;

        uint256 reward = userReward.pendingRewards;
        userReward.pendingRewards = 0;
        userReward.totalRewards += reward;
        userReward.lastClaimTime = block.timestamp;

        IERC20(token).safeTransfer(user, reward);

        emit RewardClaimed(user, pool, token, reward);
    }

    /**
     * @dev emergency withdrawal برای owner
     * @param token آدرس token
     * @param amount مقدار
     * @param to آدرس مقصد
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev محاسبه APY برای pool
     * @param pool آدرس pool
     * @param token آدرس reward token
     * @return apy نرخ APY (در basis points)
     */
    function calculateAPY(address pool, address token) external view returns (uint256 apy) {
        PoolRewardData storage poolData = poolRewards[pool][token];
        address lpToken = poolLPTokens[pool];
        
        if (lpToken == address(0) || poolData.rewardRate == 0) return 0;
        
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        if (totalSupply == 0) return 0;
        
        // محاسبه ساده APY
        // APY = (rewardRate * 365 days * 100) / totalSupply
        uint256 yearlyRewards = poolData.rewardRate * 365 days;
        apy = (yearlyRewards * Constants.BASIS_POINTS) / totalSupply;
    }

    /**
     * @dev دریافت تعداد pools فعال برای token
     * @param token آدرس token
     * @return count تعداد pools
     */
    function getActivePoolsCount(address token) external view returns (uint256 count) {
        // این تابع نیاز به پیاده‌سازی mapping اضافی دارد
        // فعلاً ساده‌سازی شده است
        return 0;
    }
}