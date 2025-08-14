// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Constants.sol";

/**
 * @title SecurityLib
 * @dev کتابخانه جامع امنیتی برای LAXCE DEX
 * @notice شامل تمام الگوهای امنیتی ضروری
 */
library SecurityLib {
    
    // ==================== CUSTOM ERRORS ====================
    
    error SlippageTooHigh(uint256 expected, uint256 actual);
    error FlashLoanDetected();
    error RateLimitExceeded(address user, uint256 lastCall);
    error InvalidTokenPair(address token0, address token1);
    error InsufficientLiquidity(uint256 available, uint256 required);
    error PriceManipulationDetected(uint256 oldPrice, uint256 newPrice);
    error FakeTokenDetected(address token);
    error MEVAttackDetected();
    error PoolDrainAttempt(uint256 remainingLiquidity);
    
    // ==================== STRUCTS ====================
    
    struct SlippageParams {
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 amountOutMax;
        uint256 maxSlippageBps;
    }
    
    struct RateLimit {
        uint256 lastCallTime;
        uint256 callCount;
        uint256 windowStart;
    }
    
    struct PriceValidation {
        uint256 lastPrice;
        uint256 lastUpdateTime;
        uint256 maxDeviationBps;
        bool isValid;
    }
    
    struct FlashLoanGuard {
        uint256 balanceBefore;
        uint256 balanceAfter;
        bool isFlashLoan;
    }
    
    // ==================== SLIPPAGE PROTECTION ====================
    
    /**
     * @dev بررسی slippage برای سواپ
     */
    function validateSlippage(
        SlippageParams memory params,
        uint256 actualAmountOut
    ) internal pure {
        // بررسی حداقل مقدار خروجی
        if (actualAmountOut < params.amountOutMin) {
            revert SlippageTooHigh(params.amountOutMin, actualAmountOut);
        }
        
        // بررسی حداکثر مقدار خروجی (برای جلوگیری از manipulation)
        if (actualAmountOut > params.amountOutMax) {
            revert SlippageTooHigh(params.amountOutMax, actualAmountOut);
        }
        
        // محاسبه درصد slippage
        uint256 expectedAmount = (params.amountOutMin + params.amountOutMax) / 2;
        if (expectedAmount > 0) {
            uint256 slippageBps;
            if (actualAmountOut < expectedAmount) {
                slippageBps = ((expectedAmount - actualAmountOut) * Constants.BPS_PRECISION) / expectedAmount;
            } else {
                slippageBps = ((actualAmountOut - expectedAmount) * Constants.BPS_PRECISION) / expectedAmount;
            }
            
            if (slippageBps > params.maxSlippageBps) {
                revert SlippageTooHigh(expectedAmount, actualAmountOut);
            }
        }
    }
    
    // ==================== FLASH LOAN PROTECTION ====================
    
    /**
     * @dev شناسایی flash loan attacks
     */
    function detectFlashLoan(
        address token,
        uint256 balanceBefore,
        uint256 balanceAfter
    ) internal pure returns (bool) {
        // اگر balance در همان تراکنش زیاد افزایش یافته باشد
        if (balanceAfter > balanceBefore) {
            uint256 increase = balanceAfter - balanceBefore;
            uint256 increasePercentage = (increase * 100) / balanceBefore;
            
            // اگر بیش از 1000% افزایش داشته باشد، احتمالاً flash loan است
            if (increasePercentage > 1000) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev محافظت در برابر flash loan
     */
    function requireNoFlashLoan(
        address token,
        uint256 balanceBefore
    ) internal view {
        // Check if balance dramatically increased in this block
        uint256 currentBalance = getTokenBalance(token, address(this));
        if (detectFlashLoan(token, balanceBefore, currentBalance)) {
            revert FlashLoanDetected();
        }
    }
    
    // ==================== RATE LIMITING ====================
    
    /**
     * @dev بررسی rate limiting برای کاربر
     */
    function checkRateLimit(
        mapping(address => RateLimit) storage rateLimits,
        address user,
        uint256 maxCallsPerWindow,
        uint256 windowDuration
    ) internal {
        RateLimit storage limit = rateLimits[user];
        uint256 currentTime = block.timestamp;
        
        // Reset window if expired
        if (currentTime >= limit.windowStart + windowDuration) {
            limit.windowStart = currentTime;
            limit.callCount = 0;
        }
        
        // Check if limit exceeded
        if (limit.callCount >= maxCallsPerWindow) {
            revert RateLimitExceeded(user, limit.lastCallTime);
        }
        
        // Update counters
        limit.callCount++;
        limit.lastCallTime = currentTime;
    }
    
    // ==================== INPUT VALIDATION ====================
    
    /**
     * @dev اعتبارسنجی جامع ورودی‌ها
     */
    function validateSwapParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) internal pure {
        require(tokenIn != address(0), Constants.ZERO_ADDRESS);
        require(tokenOut != address(0), Constants.ZERO_ADDRESS);
        require(to != address(0), Constants.ZERO_ADDRESS);
        require(amountIn > 0, Constants.ZERO_AMOUNT);
        require(amountOutMin > 0, "Invalid min amount");
        require(tokenIn != tokenOut, "Identical tokens");
    }
    
    /**
     * @dev بررسی صحت آدرس توکن
     */
    function validateToken(address token) internal view returns (bool) {
        if (token == address(0)) return false;
        
        // بررسی اینکه contract است
        uint256 size;
        assembly {
            size := extcodesize(token)
        }
        
        if (size == 0) return false;
        
        // تلاش برای فراخوانی totalSupply (basic ERC20 check)
        try IERC20(token).totalSupply() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }
    
    // ==================== PRICE MANIPULATION PROTECTION ====================
    
    /**
     * @dev بررسی دستکاری قیمت
     */
    function validatePriceChange(
        PriceValidation storage priceData,
        uint256 newPrice,
        uint256 maxDeviationBps
    ) internal {
        if (priceData.lastPrice > 0 && priceData.isValid) {
            uint256 priceChange;
            
            if (newPrice > priceData.lastPrice) {
                priceChange = ((newPrice - priceData.lastPrice) * Constants.BPS_PRECISION) / priceData.lastPrice;
            } else {
                priceChange = ((priceData.lastPrice - newPrice) * Constants.BPS_PRECISION) / priceData.lastPrice;
            }
            
            if (priceChange > maxDeviationBps) {
                revert PriceManipulationDetected(priceData.lastPrice, newPrice);
            }
        }
        
        // Update price data
        priceData.lastPrice = newPrice;
        priceData.lastUpdateTime = block.timestamp;
        priceData.isValid = true;
    }
    
    // ==================== MEV PROTECTION ====================
    
    /**
     * @dev تشخیص حملات MEV/Sandwich
     */
    function detectSandwichAttack(
        address user,
        uint256 amountIn,
        uint256 amountOut,
        mapping(address => uint256) storage lastTxAmounts,
        mapping(address => uint256) storage lastTxBlocks
    ) internal view {
        // بررسی اینکه کاربر در block قبلی transaction بزرگ داشته
        if (lastTxBlocks[user] == block.number - 1) {
            uint256 lastAmount = lastTxAmounts[user];
            
            // اگر مقدار فعلی خیلی متفاوت از قبلی باشد
            if (amountIn > lastAmount * 10 || lastAmount > amountIn * 10) {
                revert MEVAttackDetected();
            }
        }
    }
    
    // ==================== POOL PROTECTION ====================
    
    /**
     * @dev جلوگیری از pool drain
     */
    function validatePoolHealth(
        uint256 reserve0,
        uint256 reserve1,
        uint256 withdrawAmount0,
        uint256 withdrawAmount1,
        uint256 minLiquidity
    ) internal pure {
        uint256 remainingReserve0 = reserve0 - withdrawAmount0;
        uint256 remainingReserve1 = reserve1 - withdrawAmount1;
        
        // بررسی حداقل نقدینگی
        if (remainingReserve0 < minLiquidity || remainingReserve1 < minLiquidity) {
            revert PoolDrainAttempt(remainingReserve0 + remainingReserve1);
        }
        
        // بررسی K constant (for AMM)
        uint256 kBefore = reserve0 * reserve1;
        uint256 kAfter = remainingReserve0 * remainingReserve1;
        
        // K نباید بیش از حد کاهش یابد
        if (kAfter < (kBefore * 95) / 100) {
            revert PoolDrainAttempt(kAfter);
        }
    }
    
    // ==================== UTILITY FUNCTIONS ====================
    
    /**
     * @dev دریافت موجودی توکن
     */
    function getTokenBalance(address token, address account) internal view returns (uint256) {
        try IERC20(token).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }
    
    /**
     * @dev محاسبه percentage change
     */
    function calculatePercentageChange(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (uint256) {
        if (oldValue == 0) return 0;
        
        if (newValue > oldValue) {
            return ((newValue - oldValue) * Constants.BPS_PRECISION) / oldValue;
        } else {
            return ((oldValue - newValue) * Constants.BPS_PRECISION) / oldValue;
        }
    }
    
    /**
     * @dev بررسی صحت deadline
     */
    function validateDeadline(uint256 deadline) internal view {
        require(block.timestamp <= deadline, "Transaction expired");
    }
    
    /**
     * @dev Safe transfer with checks
     */
    function safeTokenTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        require(validateToken(token), "Invalid token");
        require(to != address(0), Constants.ZERO_ADDRESS);
        require(amount > 0, Constants.ZERO_AMOUNT);
        
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }
}

// Interface برای IERC20 calls
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
} 