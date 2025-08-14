// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/Constants.sol";

/**
 * @title SwapValidator
 * @dev اعتبارسنجی تراکنش‌های swap
 */
contract SwapValidator is Ownable {
    using SafeERC20 for IERC20;

    struct SwapValidation {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address to;
        uint256 deadline;
        address[] path;
    }

    struct TokenValidation {
        bool isValid;
        bool isBlacklisted;
        uint256 minTradeAmount;     // حداقل مقدار برای trade
        uint256 maxTradeAmount;     // حداکثر مقدار برای trade
        uint256 dailyVolumeLimit;   // حد volume روزانه
        uint256 dailyVolume;        // volume امروز
        uint256 lastResetDay;       // آخرین روز reset
    }

    // Events
    event TokenValidated(address indexed token, bool isValid);
    event TokenBlacklisted(address indexed token, bool blacklisted);
    event SwapValidated(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        bool success
    );
    event ValidationFailed(
        address indexed user,
        address indexed token,
        string reason
    );

    // State variables
    mapping(address => TokenValidation) public tokenValidation;
    mapping(address => mapping(uint256 => uint256)) public userDailyVolume; // user => day => volume
    mapping(address => bool) public trustedCallers; // contracts that can call validation
    
    // Global limits
    uint256 public constant MIN_TRADE_AMOUNT = 1000; // minimum 1000 wei
    uint256 public constant MAX_PATH_LENGTH = 4;     // maximum 4 hops
    uint256 public constant MAX_DEADLINE_EXTENSION = 3600; // 1 hour max
    
    // Daily limits
    uint256 public defaultDailyVolumeLimit = 1000000 * 10**18; // 1M tokens default
    uint256 public emergencyDailyLimit = 100000 * 10**18;      // 100K in emergency
    bool public emergencyMode = false;

    error InvalidToken();
    error TokenBlacklisted();
    error InsufficientAmount();
    error ExcessiveAmount();
    error DailyLimitExceeded();
    error InvalidPath();
    error InvalidDeadline();
    error InvalidRecipient();
    error UnauthorizedCaller();
    error EmergencyModeActive();

    modifier onlyTrustedCaller() {
        if (!trustedCallers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedCaller();
        }
        _;
    }

    constructor() Ownable(msg.sender) {
        trustedCallers[msg.sender] = true;
    }

    /**
     * @dev اعتبارسنجی کامل swap
     * @param validation پارامترهای validation
     * @return success آیا معتبر است
     */
    function validateSwap(SwapValidation calldata validation) 
        external 
        onlyTrustedCaller 
        returns (bool success) 
    {
        // بررسی emergency mode
        if (emergencyMode) revert EmergencyModeActive();

        // اعتبارسنجی tokens
        _validateTokens(validation.tokenIn, validation.tokenOut);
        
        // اعتبارسنجی amounts
        _validateAmounts(validation.tokenIn, validation.amountIn);
        
        // اعتبارسنجی path
        _validatePath(validation.path);
        
        // اعتبارسنجی deadline
        _validateDeadline(validation.deadline);
        
        // اعتبارسنجی recipient
        _validateRecipient(validation.to);
        
        // اعتبارسنجی daily limits
        _validateDailyLimits(validation.tokenIn, validation.amountIn);
        
        // به‌روزرسانی daily volume
        _updateDailyVolume(validation.tokenIn, validation.amountIn);
        
        emit SwapValidated(
            tx.origin, // استفاده از tx.origin برای کاربر اصلی
            validation.tokenIn,
            validation.tokenOut,
            validation.amountIn,
            true
        );
        
        return true;
    }

    /**
     * @dev اعتبارسنجی سریع token
     * @param token آدرس token
     * @return isValid آیا معتبر است
     */
    function quickValidateToken(address token) external view returns (bool isValid) {
        TokenValidation storage validation = tokenValidation[token];
        return validation.isValid && !validation.isBlacklisted;
    }

    /**
     * @dev اعتبارسنجی balance کاربر
     * @param user آدرس کاربر
     * @param token آدرس token
     * @param amount مقدار مورد نیاز
     * @return hasBalance آیا balance کافی دارد
     */
    function validateUserBalance(
        address user,
        address token,
        uint256 amount
    ) external view returns (bool hasBalance) {
        uint256 balance = IERC20(token).balanceOf(user);
        return balance >= amount;
    }

    /**
     * @dev اعتبارسنجی allowance
     * @param user آدرس کاربر
     * @param token آدرس token
     * @param spender آدرس spender
     * @param amount مقدار مورد نیاز
     * @return hasAllowance آیا allowance کافی دارد
     */
    function validateAllowance(
        address user,
        address token,
        address spender,
        uint256 amount
    ) external view returns (bool hasAllowance) {
        uint256 allowance = IERC20(token).allowance(user, spender);
        return allowance >= amount;
    }

    /**
     * @dev تنظیم validation برای token
     * @param token آدرس token
     * @param isValid آیا معتبر است
     * @param minAmount حداقل مقدار trade
     * @param maxAmount حداکثر مقدار trade
     * @param dailyLimit حد volume روزانه
     */
    function setTokenValidation(
        address token,
        bool isValid,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 dailyLimit
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(maxAmount >= minAmount, "Invalid amounts");
        
        tokenValidation[token] = TokenValidation({
            isValid: isValid,
            isBlacklisted: false,
            minTradeAmount: minAmount,
            maxTradeAmount: maxAmount,
            dailyVolumeLimit: dailyLimit,
            dailyVolume: 0,
            lastResetDay: _getCurrentDay()
        });
        
        emit TokenValidated(token, isValid);
    }

    /**
     * @dev قرار دادن token در blacklist
     * @param token آدرس token
     * @param blacklisted وضعیت blacklist
     */
    function setTokenBlacklisted(address token, bool blacklisted) external onlyOwner {
        tokenValidation[token].isBlacklisted = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }

    /**
     * @dev اضافه کردن trusted caller
     * @param caller آدرس caller
     */
    function addTrustedCaller(address caller) external onlyOwner {
        trustedCallers[caller] = true;
    }

    /**
     * @dev حذف trusted caller
     * @param caller آدرس caller
     */
    function removeTrustedCaller(address caller) external onlyOwner {
        trustedCallers[caller] = false;
    }

    /**
     * @dev فعال/غیرفعال کردن emergency mode
     * @param enabled وضعیت
     */
    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
    }

    /**
     * @dev تنظیم default daily volume limit
     * @param limit حد جدید
     */
    function setDefaultDailyVolumeLimit(uint256 limit) external onlyOwner {
        defaultDailyVolumeLimit = limit;
    }

    /**
     * @dev دریافت daily volume کاربر
     * @param user آدرس کاربر
     * @return volume
     */
    function getUserDailyVolume(address user) external view returns (uint256 volume) {
        uint256 currentDay = _getCurrentDay();
        return userDailyVolume[user][currentDay];
    }

    /**
     * @dev دریافت اطلاعات token validation
     * @param token آدرس token
     */
    function getTokenValidation(address token) 
        external 
        view 
        returns (
            bool isValid,
            bool isBlacklisted,
            uint256 minTradeAmount,
            uint256 maxTradeAmount,
            uint256 dailyVolumeLimit,
            uint256 dailyVolume
        ) 
    {
        TokenValidation storage validation = tokenValidation[token];
        return (
            validation.isValid,
            validation.isBlacklisted,
            validation.minTradeAmount,
            validation.maxTradeAmount,
            validation.dailyVolumeLimit,
            validation.dailyVolume
        );
    }

    /**
     * @dev اعتبارسنجی tokens
     */
    function _validateTokens(address tokenIn, address tokenOut) internal view {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidToken();
        if (tokenIn == tokenOut) revert InvalidToken();
        
        TokenValidation storage validationIn = tokenValidation[tokenIn];
        TokenValidation storage validationOut = tokenValidation[tokenOut];
        
        if (!validationIn.isValid || validationIn.isBlacklisted) revert InvalidToken();
        if (!validationOut.isValid || validationOut.isBlacklisted) revert InvalidToken();
    }

    /**
     * @dev اعتبارسنجی amounts
     */
    function _validateAmounts(address token, uint256 amount) internal view {
        if (amount < MIN_TRADE_AMOUNT) revert InsufficientAmount();
        
        TokenValidation storage validation = tokenValidation[token];
        if (validation.minTradeAmount > 0 && amount < validation.minTradeAmount) {
            revert InsufficientAmount();
        }
        
        if (validation.maxTradeAmount > 0 && amount > validation.maxTradeAmount) {
            revert ExcessiveAmount();
        }
    }

    /**
     * @dev اعتبارسنجی path
     */
    function _validatePath(address[] calldata path) internal pure {
        if (path.length < 2 || path.length > MAX_PATH_LENGTH) revert InvalidPath();
        
        // بررسی تکراری نبودن آدرس‌ها در path
        for (uint256 i = 0; i < path.length; i++) {
            if (path[i] == address(0)) revert InvalidPath();
            for (uint256 j = i + 1; j < path.length; j++) {
                if (path[i] == path[j]) revert InvalidPath();
            }
        }
    }

    /**
     * @dev اعتبارسنجی deadline
     */
    function _validateDeadline(uint256 deadline) internal view {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (deadline > block.timestamp + MAX_DEADLINE_EXTENSION) revert InvalidDeadline();
    }

    /**
     * @dev اعتبارسنجی recipient
     */
    function _validateRecipient(address to) internal pure {
        if (to == address(0)) revert InvalidRecipient();
    }

    /**
     * @dev اعتبارسنجی daily limits
     */
    function _validateDailyLimits(address token, uint256 amount) internal view {
        TokenValidation storage validation = tokenValidation[token];
        uint256 currentDay = _getCurrentDay();
        
        // reset daily volume if needed
        uint256 currentVolume = validation.dailyVolume;
        if (validation.lastResetDay < currentDay) {
            currentVolume = 0;
        }
        
        uint256 dailyLimit = validation.dailyVolumeLimit > 0 ? 
            validation.dailyVolumeLimit : defaultDailyVolumeLimit;
            
        if (emergencyMode) {
            dailyLimit = emergencyDailyLimit;
        }
        
        if (currentVolume + amount > dailyLimit) revert DailyLimitExceeded();
    }

    /**
     * @dev به‌روزرسانی daily volume
     */
    function _updateDailyVolume(address token, uint256 amount) internal {
        TokenValidation storage validation = tokenValidation[token];
        uint256 currentDay = _getCurrentDay();
        
        // reset if new day
        if (validation.lastResetDay < currentDay) {
            validation.dailyVolume = 0;
            validation.lastResetDay = currentDay;
        }
        
        validation.dailyVolume += amount;
        
        // update user daily volume
        userDailyVolume[tx.origin][currentDay] += amount;
    }

    /**
     * @dev دریافت روز فعلی (epoch days)
     */
    function _getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 86400; // 24 * 60 * 60
    }
}