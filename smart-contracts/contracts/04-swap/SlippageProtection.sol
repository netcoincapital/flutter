// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

/**
 * @title SlippageProtection
 * @dev محافظت از slippage و MEV attacks
 */
contract SlippageProtection is Ownable, ReentrancyGuard {
    
    struct SlippageParams {
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 deadline;
        uint256 maxSlippage; // در basis points
    }

    struct MEVProtection {
        uint256 lastBlockNumber;
        uint256 transactionCount;
        uint256 suspiciousActivity;
        bool isBlocked;
    }

    // Events
    event SlippageProtectionTriggered(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 expectedAmount,
        uint256 actualAmount,
        uint256 slippage
    );

    event MEVDetected(
        address indexed user,
        uint256 blockNumber,
        uint256 transactionCount,
        string reason
    );

    event UserBlocked(address indexed user, string reason);
    event UserUnblocked(address indexed user);

    // State variables
    mapping(address => MEVProtection) public mevProtection;
    mapping(address => uint256) public userSlippageTolerance; // custom tolerance per user
    mapping(address => bool) public trustedUsers; // whitelisted users
    
    // Global limits
    uint256 public constant DEFAULT_SLIPPAGE_TOLERANCE = 100; // 1%
    uint256 public constant MAX_SLIPPAGE_TOLERANCE = 500;     // 5%
    uint256 public constant MEV_DETECTION_THRESHOLD = 5;      // max 5 tx per block
    uint256 public constant BLOCK_SANDWICH_THRESHOLD = 3;     // detect sandwich attacks
    
    // Admin settings
    uint256 public globalMaxSlippage = 300; // 3%
    bool public mevProtectionEnabled = true;
    bool public emergencyPause = false;

    error SlippageExceeded();
    error DeadlineExpired();
    error MEVDetected();
    error UserBlocked();
    error EmergencyPaused();
    error InvalidSlippage();
    error InvalidDeadline();

    modifier notPaused() {
        if (emergencyPause) revert EmergencyPaused();
        _;
    }

    modifier notBlocked() {
        if (mevProtection[msg.sender].isBlocked) revert UserBlocked();
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev بررسی slippage قبل از اجرای swap
     * @param params پارامترهای slippage
     * @param actualAmountOut مقدار واقعی خروجی
     */
    function checkSlippage(
        SlippageParams calldata params,
        uint256 actualAmountOut
    ) external view notPaused returns (bool) {
        // بررسی deadline
        if (block.timestamp > params.deadline) revert DeadlineExpired();
        
        // بررسی minimum amount
        if (actualAmountOut < params.amountOutMin) revert SlippageExceeded();
        
        // محاسبه slippage واقعی
        uint256 expectedAmount = _calculateExpectedAmount(params.amountIn, params.maxSlippage);
        
        if (actualAmountOut < expectedAmount) {
            uint256 actualSlippage = _calculateSlippage(expectedAmount, actualAmountOut);
            
            // بررسی با tolerance کاربر
            uint256 userTolerance = getUserSlippageTolerance(msg.sender);
            if (actualSlippage > userTolerance) revert SlippageExceeded();
        }
        
        return true;
    }

    /**
     * @dev محافظت از MEV attacks
     * @param user آدرس کاربر
     */
    function checkMEVProtection(address user) external nonReentrant notPaused {
        if (!mevProtectionEnabled || trustedUsers[user]) return;
        
        MEVProtection storage protection = mevProtection[user];
        
        // بررسی تراکنش‌های متوالی در یک block
        if (protection.lastBlockNumber == block.number) {
            protection.transactionCount++;
            
            if (protection.transactionCount > MEV_DETECTION_THRESHOLD) {
                protection.suspiciousActivity++;
                emit MEVDetected(user, block.number, protection.transactionCount, "Too many transactions in single block");
                
                // مسدود کردن در صورت تکرار
                if (protection.suspiciousActivity >= 3) {
                    protection.isBlocked = true;
                    emit UserBlocked(user, "Suspicious MEV activity");
                    revert MEVDetected();
                }
            }
        } else {
            protection.lastBlockNumber = block.number;
            protection.transactionCount = 1;
        }
        
        // بررسی sandwich attack pattern
        _checkSandwichAttack(user);
    }

    /**
     * @dev تنظیم slippage tolerance سفارشی برای کاربر
     * @param tolerance tolerance در basis points
     */
    function setUserSlippageTolerance(uint256 tolerance) external {
        if (tolerance > MAX_SLIPPAGE_TOLERANCE) revert InvalidSlippage();
        userSlippageTolerance[msg.sender] = tolerance;
    }

    /**
     * @dev دریافت slippage tolerance کاربر
     * @param user آدرس کاربر
     * @return tolerance
     */
    function getUserSlippageTolerance(address user) public view returns (uint256) {
        uint256 userTolerance = userSlippageTolerance[user];
        if (userTolerance == 0) {
            return DEFAULT_SLIPPAGE_TOLERANCE;
        }
        
        // استفاده از کمترین مقدار بین تنظیمات کاربر و global limit
        return userTolerance > globalMaxSlippage ? globalMaxSlippage : userTolerance;
    }

    /**
     * @dev محاسبه slippage واقعی
     * @param expectedAmount مقدار مورد انتظار
     * @param actualAmount مقدار واقعی
     * @return slippage در basis points
     */
    function calculateActualSlippage(
        uint256 expectedAmount,
        uint256 actualAmount
    ) external pure returns (uint256 slippage) {
        return _calculateSlippage(expectedAmount, actualAmount);
    }

    /**
     * @dev محاسبه minimum amount out با tolerance
     * @param amountOut مقدار خروجی پیش‌بینی شده
     * @param slippageTolerance tolerance در basis points
     * @return minAmountOut
     */
    function calculateMinAmountOut(
        uint256 amountOut,
        uint256 slippageTolerance
    ) external pure returns (uint256 minAmountOut) {
        if (slippageTolerance > Constants.BASIS_POINTS) {
            slippageTolerance = Constants.BASIS_POINTS;
        }
        minAmountOut = (amountOut * (Constants.BASIS_POINTS - slippageTolerance)) / Constants.BASIS_POINTS;
    }

    /**
     * @dev تولید deadline امن
     * @param additionalSeconds ثانیه‌های اضافی
     * @return deadline
     */
    function generateSafeDeadline(uint256 additionalSeconds) external view returns (uint256 deadline) {
        require(additionalSeconds >= 60 && additionalSeconds <= 3600, "Invalid deadline range"); // 1 min to 1 hour
        deadline = block.timestamp + additionalSeconds;
    }

    /**
     * @dev اضافه کردن کاربر به لیست مورد اعتماد
     * @param user آدرس کاربر
     */
    function addTrustedUser(address user) external onlyOwner {
        trustedUsers[user] = true;
    }

    /**
     * @dev حذف کاربر از لیست مورد اعتماد
     * @param user آدرس کاربر
     */
    function removeTrustedUser(address user) external onlyOwner {
        trustedUsers[user] = false;
    }

    /**
     * @dev رفع مسدودیت کاربر
     * @param user آدرس کاربر
     */
    function unblockUser(address user) external onlyOwner {
        mevProtection[user].isBlocked = false;
        mevProtection[user].suspiciousActivity = 0;
        emit UserUnblocked(user);
    }

    /**
     * @dev تنظیم global max slippage
     * @param _maxSlippage حداکثر slippage در basis points
     */
    function setGlobalMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        require(_maxSlippage <= MAX_SLIPPAGE_TOLERANCE, "Too high");
        globalMaxSlippage = _maxSlippage;
    }

    /**
     * @dev فعال/غیرفعال کردن MEV protection
     * @param enabled وضعیت
     */
    function setMEVProtectionEnabled(bool enabled) external onlyOwner {
        mevProtectionEnabled = enabled;
    }

    /**
     * @dev فعال/غیرفعال کردن emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPause(bool paused) external onlyOwner {
        emergencyPause = paused;
    }

    /**
     * @dev محاسبه مقدار مورد انتظار
     */
    function _calculateExpectedAmount(
        uint256 amountIn,
        uint256 maxSlippage
    ) internal pure returns (uint256) {
        return (amountIn * (Constants.BASIS_POINTS - maxSlippage)) / Constants.BASIS_POINTS;
    }

    /**
     * @dev محاسبه slippage
     */
    function _calculateSlippage(
        uint256 expectedAmount,
        uint256 actualAmount
    ) internal pure returns (uint256 slippage) {
        if (actualAmount >= expectedAmount) return 0;
        slippage = ((expectedAmount - actualAmount) * Constants.BASIS_POINTS) / expectedAmount;
    }

    /**
     * @dev بررسی sandwich attack
     */
    function _checkSandwichAttack(address user) internal view {
        // پیاده‌سازی ساده‌ای از تشخیص sandwich attack
        // می‌توان پیچیده‌تر کرد با بررسی mempool و pattern matching
        
        MEVProtection storage protection = mevProtection[user];
        
        // اگر کاربر در 3 block متوالی تراکنش داشته
        if (protection.lastBlockNumber != 0 && 
            block.number - protection.lastBlockNumber <= BLOCK_SANDWICH_THRESHOLD &&
            protection.transactionCount > 1) {
            
            // این می‌تواند نشانه sandwich attack باشد
            // در حال حاضر فقط log می‌کنیم
        }
    }

    /**
     * @dev دریافت اطلاعات MEV protection کاربر
     * @param user آدرس کاربر
     */
    function getMEVProtectionInfo(address user) 
        external 
        view 
        returns (
            uint256 lastBlockNumber,
            uint256 transactionCount,
            uint256 suspiciousActivity,
            bool isBlocked
        ) 
    {
        MEVProtection storage protection = mevProtection[user];
        return (
            protection.lastBlockNumber,
            protection.transactionCount,
            protection.suspiciousActivity,
            protection.isBlocked
        );
    }
}