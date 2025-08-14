// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PauseLib
 * @dev Circuit Breaker و Emergency Pause System
 * @notice سیستم توقف اضطراری برای محافظت در مواقع بحرانی
 */
library PauseLib {
    
    // ==================== EVENTS ====================
    
    event EmergencyPaused(address indexed caller, string reason);
    event EmergencyUnpaused(address indexed caller);
    event CircuitBreakerTriggered(string reason, uint256 timestamp);
    event AutoPauseTriggered(string condition, uint256 value, uint256 threshold);
    
    // ==================== STRUCTS ====================
    
    struct PauseState {
        bool isPaused;              // آیا contract pause است
        uint256 pausedAt;           // زمان pause
        address pausedBy;           // کسی که pause کرده
        string pauseReason;         // دلیل pause
        uint256 unpauseAfter;       // زمان خودکار unpause (0 = manual)
    }
    
    struct CircuitBreaker {
        uint256 lastTriggerTime;    // آخرین زمان trigger
        uint256 triggerCount;       // تعداد trigger در window
        uint256 windowStart;        // شروع window فعلی
        uint256 maxTriggers;        // حداکثر trigger در window
        uint256 windowDuration;     // مدت window
        bool isActive;              // آیا فعال است
    }
    
    struct AutoPauseCondition {
        string name;                // نام condition
        uint256 threshold;          // آستانه trigger
        uint256 currentValue;       // مقدار فعلی
        bool isEnabled;             // آیا فعال است
        uint256 cooldownPeriod;     // مدت cooldown
        uint256 lastTriggered;      // آخرین trigger
    }
    
    // ==================== PAUSE FUNCTIONS ====================
    
    /**
     * @dev Pause کردن contract با دلیل
     */
    function emergencyPause(
        PauseState storage pauseState,
        address caller,
        string memory reason
    ) internal {
        require(!pauseState.isPaused, "Already paused");
        
        pauseState.isPaused = true;
        pauseState.pausedAt = block.timestamp;
        pauseState.pausedBy = caller;
        pauseState.pauseReason = reason;
        pauseState.unpauseAfter = 0; // Manual unpause required
        
        emit EmergencyPaused(caller, reason);
    }
    
    /**
     * @dev Pause کردن با زمان مشخص (خودکار unpause)
     */
    function timedPause(
        PauseState storage pauseState,
        address caller,
        string memory reason,
        uint256 duration
    ) internal {
        require(!pauseState.isPaused, "Already paused");
        require(duration > 0 && duration <= 24 hours, "Invalid duration");
        
        pauseState.isPaused = true;
        pauseState.pausedAt = block.timestamp;
        pauseState.pausedBy = caller;
        pauseState.pauseReason = reason;
        pauseState.unpauseAfter = block.timestamp + duration;
        
        emit EmergencyPaused(caller, reason);
    }
    
    /**
     * @dev Unpause کردن contract
     */
    function emergencyUnpause(
        PauseState storage pauseState,
        address caller
    ) internal {
        require(pauseState.isPaused, "Not paused");
        
        // بررسی اینکه یا caller همان pauser است یا زمان unpause رسیده
        require(
            pauseState.pausedBy == caller ||
            (pauseState.unpauseAfter > 0 && block.timestamp >= pauseState.unpauseAfter),
            "Cannot unpause"
        );
        
        pauseState.isPaused = false;
        pauseState.pausedAt = 0;
        pauseState.pausedBy = address(0);
        pauseState.pauseReason = "";
        pauseState.unpauseAfter = 0;
        
        emit EmergencyUnpaused(caller);
    }
    
    // ==================== CIRCUIT BREAKER ====================
    
    /**
     * @dev Initialize circuit breaker
     */
    function initCircuitBreaker(
        CircuitBreaker storage breaker,
        uint256 maxTriggers,
        uint256 windowDuration
    ) internal {
        breaker.maxTriggers = maxTriggers;
        breaker.windowDuration = windowDuration;
        breaker.windowStart = block.timestamp;
        breaker.isActive = true;
    }
    
    /**
     * @dev Trigger circuit breaker
     */
    function triggerCircuitBreaker(
        CircuitBreaker storage breaker,
        PauseState storage pauseState,
        string memory reason
    ) internal returns (bool shouldPause) {
        if (!breaker.isActive) return false;
        
        uint256 currentTime = block.timestamp;
        
        // Reset window if expired
        if (currentTime >= breaker.windowStart + breaker.windowDuration) {
            breaker.windowStart = currentTime;
            breaker.triggerCount = 0;
        }
        
        // Increment trigger count
        breaker.triggerCount++;
        breaker.lastTriggerTime = currentTime;
        
        emit CircuitBreakerTriggered(reason, currentTime);
        
        // Check if should pause
        if (breaker.triggerCount >= breaker.maxTriggers) {
            emergencyPause(pauseState, address(this), 
                string(abi.encodePacked("Circuit breaker: ", reason)));
            return true;
        }
        
        return false;
    }
    
    // ==================== AUTO PAUSE CONDITIONS ====================
    
    /**
     * @dev چک کردن شرایط auto pause
     */
    function checkAutoPause(
        AutoPauseCondition storage condition,
        uint256 currentValue,
        PauseState storage pauseState
    ) internal returns (bool triggered) {
        if (!condition.isEnabled) return false;
        
        uint256 currentTime = block.timestamp;
        
        // Check cooldown
        if (currentTime < condition.lastTriggered + condition.cooldownPeriod) {
            return false;
        }
        
        // Update current value
        condition.currentValue = currentValue;
        
        // Check threshold
        if (currentValue >= condition.threshold) {
            condition.lastTriggered = currentTime;
            
            string memory reason = string(abi.encodePacked(
                "Auto-pause: ", condition.name, " exceeded threshold"
            ));
            
            emergencyPause(pauseState, address(this), reason);
            
            emit AutoPauseTriggered(condition.name, currentValue, condition.threshold);
            
            return true;
        }
        
        return false;
    }
    
    // ==================== VALIDATION FUNCTIONS ====================
    
    /**
     * @dev بررسی اینکه contract pause نیست
     */
    function requireNotPaused(PauseState storage pauseState) internal view {
        // Auto-unpause if time has passed
        if (pauseState.isPaused && 
            pauseState.unpauseAfter > 0 && 
            block.timestamp >= pauseState.unpauseAfter) {
            // Note: This is a view function, so we can't modify state here
            // The actual unpause should be called externally
            return;
        }
        
        require(!pauseState.isPaused, 
            string(abi.encodePacked("Contract paused: ", pauseState.pauseReason)));
    }
    
    /**
     * @dev بررسی امکان unpause
     */
    function canUnpause(
        PauseState storage pauseState,
        address caller
    ) internal view returns (bool) {
        if (!pauseState.isPaused) return false;
        
        // Admin can always unpause
        if (pauseState.pausedBy == caller) return true;
        
        // Timed unpause
        if (pauseState.unpauseAfter > 0 && block.timestamp >= pauseState.unpauseAfter) {
            return true;
        }
        
        return false;
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev دریافت وضعیت pause
     */
    function getPauseInfo(PauseState storage pauseState) 
        internal 
        view 
        returns (
            bool isPaused,
            uint256 pausedAt,
            address pausedBy,
            string memory reason,
            uint256 timeUntilUnpause
        ) 
    {
        isPaused = pauseState.isPaused;
        pausedAt = pauseState.pausedAt;
        pausedBy = pauseState.pausedBy;
        reason = pauseState.pauseReason;
        
        if (pauseState.unpauseAfter > 0 && block.timestamp < pauseState.unpauseAfter) {
            timeUntilUnpause = pauseState.unpauseAfter - block.timestamp;
        } else {
            timeUntilUnpause = 0;
        }
    }
    
    /**
     * @dev دریافت آمار circuit breaker
     */
    function getCircuitBreakerStats(CircuitBreaker storage breaker)
        internal
        view
        returns (
            uint256 triggerCount,
            uint256 maxTriggers,
            uint256 windowTimeLeft,
            bool isActive
        )
    {
        triggerCount = breaker.triggerCount;
        maxTriggers = breaker.maxTriggers;
        isActive = breaker.isActive;
        
        uint256 windowEnd = breaker.windowStart + breaker.windowDuration;
        if (block.timestamp < windowEnd) {
            windowTimeLeft = windowEnd - block.timestamp;
        } else {
            windowTimeLeft = 0;
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev تنظیم circuit breaker
     */
    function configureCircuitBreaker(
        CircuitBreaker storage breaker,
        uint256 maxTriggers,
        uint256 windowDuration,
        bool isActive
    ) internal {
        require(maxTriggers > 0, "Invalid max triggers");
        require(windowDuration > 0, "Invalid window duration");
        
        breaker.maxTriggers = maxTriggers;
        breaker.windowDuration = windowDuration;
        breaker.isActive = isActive;
        
        // Reset window
        breaker.windowStart = block.timestamp;
        breaker.triggerCount = 0;
    }
    
    /**
     * @dev تنظیم auto pause condition
     */
    function configureAutoPause(
        AutoPauseCondition storage condition,
        string memory name,
        uint256 threshold,
        bool isEnabled,
        uint256 cooldownPeriod
    ) internal {
        condition.name = name;
        condition.threshold = threshold;
        condition.isEnabled = isEnabled;
        condition.cooldownPeriod = cooldownPeriod;
    }
} 