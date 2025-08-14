// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LaxceReentrancyGuard
 * @dev محافظت در برابر حملات reentrancy
 * @notice کتابخانه مشترک برای تمام لایه‌های DEX
 */
library LaxceReentrancyGuard {
    /// @dev وضعیت‌های مختلف برای تشخیص reentrancy
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /// @dev ساختار ذخیره وضعیت reentrancy
    struct ReentrancyData {
        uint256 status;
        bool initialized;
    }

    /// @dev رویدادها
    event ReentrancyStatusChanged(address indexed contract_, uint256 oldStatus, uint256 newStatus);
    event ReentrancyAttemptBlocked(address indexed contract_, address indexed caller);

    /// @dev خطاها
    error ReentrancyGuardReentrantCall();
    error ReentrancyGuardNotInitialized();
    error ReentrancyGuardAlreadyInitialized();

    /**
     * @dev مقداردهی اولیه ReentrancyGuard
     * @param self ساختار داده ReentrancyData
     */
    function initialize(ReentrancyData storage self) internal {
        if (self.initialized) {
            revert ReentrancyGuardAlreadyInitialized();
        }
        
        self.status = _NOT_ENTERED;
        self.initialized = true;
        
        emit ReentrancyStatusChanged(address(this), 0, _NOT_ENTERED);
    }

    /**
     * @dev شروع محافظت از reentrancy
     * @param self ساختار داده ReentrancyData
     */
    function enter(ReentrancyData storage self) internal {
        if (!self.initialized) {
            revert ReentrancyGuardNotInitialized();
        }
        
        if (self.status == _ENTERED) {
            emit ReentrancyAttemptBlocked(address(this), msg.sender);
            revert ReentrancyGuardReentrantCall();
        }

        uint256 oldStatus = self.status;
        self.status = _ENTERED;
        
        emit ReentrancyStatusChanged(address(this), oldStatus, _ENTERED);
    }

    /**
     * @dev پایان محافظت از reentrancy
     * @param self ساختار داده ReentrancyData
     */
    function exit(ReentrancyData storage self) internal {
        if (!self.initialized) {
            revert ReentrancyGuardNotInitialized();
        }
        
        uint256 oldStatus = self.status;
        self.status = _NOT_ENTERED;
        
        emit ReentrancyStatusChanged(address(this), oldStatus, _NOT_ENTERED);
    }

    /**
     * @dev بررسی وضعیت فعلی
     * @param self ساختار داده ReentrancyData
     * @return true اگر در حال اجرا باشد
     */
    function isEntered(ReentrancyData storage self) internal view returns (bool) {
        if (!self.initialized) {
            return false;
        }
        return self.status == _ENTERED;
    }

    /**
     * @dev بررسی مقداردهی اولیه
     * @param self ساختار داده ReentrancyData
     * @return true اگر مقداردهی شده باشد
     */
    function isInitialized(ReentrancyData storage self) internal view returns (bool) {
        return self.initialized;
    }

    /**
     * @dev ریست کردن وضعیت (فقط در شرایط اضطراری)
     * @param self ساختار داده ReentrancyData
     */
    function emergencyReset(ReentrancyData storage self) internal {
        uint256 oldStatus = self.status;
        self.status = _NOT_ENTERED;
        
        emit ReentrancyStatusChanged(address(this), oldStatus, _NOT_ENTERED);
    }

    /**
     * @dev دریافت وضعیت فعلی
     * @param self ساختار داده ReentrancyData
     * @return وضعیت فعلی (1 = NOT_ENTERED, 2 = ENTERED)
     */
    function getStatus(ReentrancyData storage self) internal view returns (uint256) {
        return self.status;
    }
} 