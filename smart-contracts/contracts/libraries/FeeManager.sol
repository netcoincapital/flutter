// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/Constants.sol";
import "../libraries/TickMath.sol";

/**
 * @title FeeManager
 * @dev مدیریت Fee Tiers و محاسبات fee مانند Uniswap V3
 * @notice سطوح مختلف fee برای بهینه‌سازی سرمایه
 */
library FeeManager {
    
    // ==================== STRUCTS ====================
    
    struct FeeTier {
        uint24 fee;                 // Fee در bps (e.g. 3000 = 0.3%)
        int24 tickSpacing;          // فاصله بین ticks مجاز
        bool isEnabled;             // آیا این tier فعال است
        uint256 poolCount;          // تعداد pools با این fee
        string description;         // توضیحات tier
    }
    
    struct FeeCollectionInfo {
        uint256 protocolFee0;       // Protocol fee token0
        uint256 protocolFee1;       // Protocol fee token1
        uint256 lpFee0;             // LP fee token0  
        uint256 lpFee1;             // LP fee token1
        uint256 lastCollection;     // آخرین زمان جمع‌آوری
    }
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر fee (10% = 100000)
    uint24 internal constant MAX_FEE = 100000;
    
    /// @dev حداقل fee (0.01% = 100)
    uint24 internal constant MIN_FEE = 100;
    
    /// @dev Protocol fee ratio (10% of total fee)
    uint8 internal constant PROTOCOL_FEE_RATIO = 10;
    
    /// @dev Standard fee tiers مانند Uniswap V3
    uint24 internal constant FEE_LOW = 500;     // 0.05%
    uint24 internal constant FEE_MEDIUM = 3000; // 0.3%
    uint24 internal constant FEE_HIGH = 10000;  // 1%
    
    // ==================== ERRORS ====================
    
    error InvalidFee(uint24 fee);
    error InvalidTickSpacing(int24 tickSpacing);
    error FeeTierNotEnabled(uint24 fee);  
    error FeeTierAlreadyExists(uint24 fee);
    
    // ==================== FEE TIER MANAGEMENT ====================
    
    /**
     * @dev بررسی صحت fee tier
     */
    function isValidFeeTier(uint24 fee) internal pure returns (bool) {
        return fee >= MIN_FEE && fee <= MAX_FEE;
    }
    
    /**
     * @dev دریافت tick spacing برای fee
     */
    function getFeeTickSpacing(uint24 fee) internal pure returns (int24) {
        if (fee == 500) return 10;      // 0.05% -> 10 tick spacing
        if (fee == 3000) return 60;     // 0.3% -> 60 tick spacing  
        if (fee == 10000) return 200;   // 1% -> 200 tick spacing
        
        // برای fee های سفارشی
        if (fee <= 1000) return 10;     // کم: 10
        if (fee <= 5000) return 60;     // متوسط: 60
        return 200;                     // زیاد: 200
    }
    
    /**
     * @dev محاسبه fee برای swap
     */
    function calculateSwapFee(
        uint256 amountIn,
        uint24 fee
    ) internal pure returns (uint256 feeAmount) {
        require(isValidFeeTier(fee), "Invalid fee tier");
        
        // Fee calculation: amountIn * fee / 1000000
        feeAmount = (amountIn * fee) / 1000000;
    }
    
    /**
     * @dev تقسیم fee بین protocol و LP
     */
    function splitFee(
        uint256 totalFee
    ) internal pure returns (uint256 protocolFee, uint256 lpFee) {
        
        protocolFee = (totalFee * PROTOCOL_FEE_RATIO) / 100;
        lpFee = totalFee - protocolFee;
    }
    
    // ==================== FEE GROWTH CALCULATIONS ====================
    
    /**
     * @dev محاسبه fee growth برای tick range
     */
    function calculateFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint256 feeGrowthOutsideLower0X128,
        uint256 feeGrowthOutsideLower1X128,
        uint256 feeGrowthOutsideUpper0X128,
        uint256 feeGrowthOutsideUpper1X128
    ) internal pure returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        
        // محاسبه fee growth زیر tick lower
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = feeGrowthOutsideLower0X128;
            feeGrowthBelow1X128 = feeGrowthOutsideLower1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - feeGrowthOutsideLower0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - feeGrowthOutsideLower1X128;
        }
        
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        
        // محاسبه fee growth بالای tick upper
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = feeGrowthOutsideUpper0X128;
            feeGrowthAbove1X128 = feeGrowthOutsideUpper1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - feeGrowthOutsideUpper0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - feeGrowthOutsideUpper1X128;
        }
        
        // محاسبه fee growth داخل range
        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
    
    /**
     * @dev محاسبه fees owed برای position
     */
    function calculateFeesOwed(
        uint128 liquidity,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128
    ) internal pure returns (uint128 tokensOwed0, uint128 tokensOwed1) {
        
        // محاسبه تغییر fee growth
        uint256 feeGrowthDelta0 = feeGrowthInside0X128 - feeGrowthInside0LastX128;
        uint256 feeGrowthDelta1 = feeGrowthInside1X128 - feeGrowthInside1LastX128;
        
        // محاسبه tokens owed
        tokensOwed0 = uint128((feeGrowthDelta0 * liquidity) >> 128);
        tokensOwed1 = uint128((feeGrowthDelta1 * liquidity) >> 128);
    }
    
    // ==================== CAPITAL EFFICIENCY ====================
    
    /**
     * @dev محاسبه capital efficiency برای position
     */
    function calculateCapitalEfficiency(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) internal pure returns (uint256 efficiency) {
        
        // اگر position خارج از range باشد، efficiency = 0
        if (tickCurrent < tickLower || tickCurrent > tickUpper) {
            return 0;
        }
        
        // محاسبه efficiency بر اساس range width
        uint256 rangeWidth = uint256(int256(tickUpper - tickLower));
        uint256 maxRange = uint256(int256(TickMath.MAX_TICK - TickMath.MIN_TICK));
        
        // Efficiency معکوس range width است
        efficiency = (maxRange * 1e18) / rangeWidth;
        
        // اعمال liquidity weight
        efficiency = (efficiency * liquidity) / 1e18;
    }
    
    /**
     * @dev محاسبه optimal fee tier برای volume
     */
    function suggestFeeTier(
        uint256 volume24h,
        uint256 volatility // در bps
    ) internal pure returns (uint24 suggestedFee) {
        
        // پایین volatility -> fee کمتر
        if (volatility <= 100) { // کمتر از 1%
            if (volume24h >= 1000000 * 1e18) {
                return FEE_LOW; // 0.05%
            } else {
                return FEE_MEDIUM; // 0.3%
            }
        }
        
        // متوسط volatility -> fee متوسط
        if (volatility <= 500) { // کمتر از 5%
            return FEE_MEDIUM; // 0.3%
        }
        
        // بالا volatility -> fee بالا
        return FEE_HIGH; // 1%
    }
    
    // ==================== PRICE RANGE OPTIMIZATION ====================
    
    /**
     * @dev محاسبه optimal price range برای LP
     */
    function calculateOptimalRange(
        uint256 currentPrice,
        uint256 volatility, // در bps
        uint24 fee
    ) internal pure returns (uint256 priceLower, uint256 priceUpper) {
        
        // محاسبه range بر اساس volatility و fee
        uint256 rangeMultiplier;
        
        if (fee == FEE_LOW) {
            rangeMultiplier = 150; // 1.5x volatility
        } else if (fee == FEE_MEDIUM) {
            rangeMultiplier = 200; // 2x volatility  
        } else {
            rangeMultiplier = 300; // 3x volatility
        }
        
        uint256 priceDeviation = (currentPrice * volatility * rangeMultiplier) / (10000 * 100);
        
        priceLower = currentPrice > priceDeviation ? currentPrice - priceDeviation : currentPrice / 2;
        priceUpper = currentPrice + priceDeviation;
    }
    
    /**
     * @dev محاسبه price impact برای trade
     */
    function calculatePriceImpact(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint24 fee
    ) internal pure returns (uint256 priceImpact) {
        
        // محاسبه price بدون fee
        uint256 priceWithoutFee = (reserveOut * 1e18) / reserveIn;
        
        // محاسبه amount out با fee
        uint256 amountInWithFee = amountIn - calculateSwapFee(amountIn, fee);
        uint256 amountOut = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
        
        // محاسبه price جدید
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;
        uint256 newPrice = (newReserveOut * 1e18) / newReserveIn;
        
        // محاسبه price impact
        if (newPrice < priceWithoutFee) {
            priceImpact = ((priceWithoutFee - newPrice) * 10000) / priceWithoutFee;
        } else {
            priceImpact = ((newPrice - priceWithoutFee) * 10000) / priceWithoutFee;
        }
    }
    
    // ==================== UTILITY FUNCTIONS ====================
    
    /**
     * @dev تبدیل fee به string
     */
    function feeToString(uint24 fee) internal pure returns (string memory) {
        if (fee == 500) return "0.05%";
        if (fee == 3000) return "0.3%";
        if (fee == 10000) return "1%";
        
        // برای fee های سفارشی
        uint256 feePercent = (fee * 100) / 10000;
        uint256 feeDecimal = ((fee * 100) % 10000) / 100;
        
        if (feeDecimal == 0) {
            return string(abi.encodePacked(toString(feePercent), "%"));
        } else {
            return string(abi.encodePacked(toString(feePercent), ".", toString(feeDecimal), "%"));
        }
    }
    
    /**
     * @dev Convert uint to string
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    /**
     * @dev محاسبه annual percentage rate (APR)
     */
    function calculateAPR(
        uint256 feesEarned24h,
        uint256 liquidityValue
    ) internal pure returns (uint256 apr) {
        
        if (liquidityValue == 0) return 0;
        
        // APR = (daily fees * 365 * 100) / liquidity value
        apr = (feesEarned24h * 365 * 100) / liquidityValue;
    }
    
    /**
     * @dev بررسی اینکه آیا fee tier optimal است
     */
    function isOptimalFeeTier(
        uint24 fee,
        uint256 volume24h,
        uint256 volatility,
        uint256 liquidityUtilization // در bps
    ) internal pure returns (bool isOptimal, string memory reason) {
        
        uint24 suggestedFee = suggestFeeTier(volume24h, volatility);
        
        if (fee == suggestedFee) {
            return (true, "Optimal fee tier");
        }
        
        if (fee > suggestedFee) {
            if (liquidityUtilization < 5000) { // کمتر از 50%
                return (false, "Fee too high for current utilization");
            }
        } else {
            if (liquidityUtilization > 8000) { // بیشتر از 80%
                return (false, "Fee too low for high utilization");
            }
        }
        
        return (true, "Acceptable fee tier");
    }
} 