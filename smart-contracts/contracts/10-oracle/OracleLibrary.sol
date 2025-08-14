// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/FullMath.sol";
import "../libraries/Constants.sol";

/**
 * @title OracleLibrary
 * @dev کتابخانه توابع کمکی برای Oracle
 */
library OracleLibrary {
    using FullMath for uint256;

    struct TWAPData {
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulative;
        uint32 timestamp;
        bool initialized;
    }

    struct PriceCalculation {
        uint256 price;
        uint256 confidence;
        uint256 timestamp;
        bool valid;
    }

    // Constants
    uint256 internal constant Q96 = 2**96;
    uint256 internal constant Q128 = 2**128;
    uint256 internal constant Q192 = 2**192;
    
    // Price calculation constants
    uint256 internal constant MIN_SQRT_RATIO = 4295128739;
    uint256 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /**
     * @dev محاسبه TWAP از observations
     * @param observations آرایه observations
     * @param secondsAgo ثانیه‌های قبل
     * @return twapTick میانگین tick
     */
    function calculateTWAP(
        TWAPData[] memory observations,
        uint32 secondsAgo
    ) internal view returns (int24 twapTick) {
        if (observations.length < 2) return 0;
        
        uint32 targetTime = uint32(block.timestamp) - secondsAgo;
        
        // پیدا کردن observations مناسب
        (TWAPData memory before, TWAPData memory after) = _findSurroundingObservations(
            observations,
            targetTime
        );
        
        if (!before.initialized || !after.initialized) return 0;
        
        uint32 timeElapsed = after.timestamp - before.timestamp;
        if (timeElapsed == 0) return 0;
        
        twapTick = int24((after.tickCumulative - before.tickCumulative) / int56(uint56(timeElapsed)));
    }

    /**
     * @dev تبدیل tick به قیمت
     * @param tick tick value
     * @return price قیمت
     */
    function tickToPrice(int24 tick) internal pure returns (uint256 price) {
        return _tickToSqrtPrice(tick).mulDiv(Constants.PRECISION, Q96).mulDiv(Constants.PRECISION, Q96);
    }

    /**
     * @dev تبدیل قیمت به tick
     * @param price قیمت
     * @return tick tick value
     */
    function priceToTick(uint256 price) internal pure returns (int24 tick) {
        require(price > 0, "Price must be positive");
        
        // محاسبه sqrt price
        uint160 sqrtPriceX96 = uint160(_sqrt(price.mulDiv(Q192, Constants.PRECISION * Constants.PRECISION)));
        
        return _sqrtPriceToTick(sqrtPriceX96);
    }

    /**
     * @dev محاسبه price impact
     * @param amountIn مقدار ورودی
     * @param reserveIn ذخیره ورودی
     * @param reserveOut ذخیره خروجی
     * @return impact price impact در basis points
     */
    function calculatePriceImpact(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 impact) {
        if (reserveIn == 0 || reserveOut == 0 || amountIn == 0) return 0;
        
        // قیمت قبل از swap
        uint256 priceBefore = (reserveOut * Constants.PRECISION) / reserveIn;
        
        // قیمت بعد از swap (فرض Constant Product)
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 newReserveOut = (reserveIn * reserveOut) / newReserveIn;
        uint256 priceAfter = (newReserveOut * Constants.PRECISION) / newReserveIn;
        
        // محاسبه impact
        if (priceAfter >= priceBefore) return 0;
        
        impact = ((priceBefore - priceAfter) * Constants.BASIS_POINTS) / priceBefore;
    }

    /**
     * @dev اعتبارسنجی قیمت
     * @param price قیمت
     * @param referencePrice قیمت مرجع
     * @param maxDeviation حداکثر انحراف مجاز (basis points)
     * @return valid آیا معتبر است
     */
    function validatePrice(
        uint256 price,
        uint256 referencePrice,
        uint256 maxDeviation
    ) internal pure returns (bool valid) {
        if (price == 0 || referencePrice == 0) return false;
        
        uint256 deviation;
        if (price > referencePrice) {
            deviation = ((price - referencePrice) * Constants.BASIS_POINTS) / referencePrice;
        } else {
            deviation = ((referencePrice - price) * Constants.BASIS_POINTS) / referencePrice;
        }
        
        return deviation <= maxDeviation;
    }

    /**
     * @dev محاسبه confidence score برای قیمت
     * @param currentPrice قیمت فعلی
     * @param twapPrice قیمت TWAP
     * @param liquidity نقدینگی
     * @param age سن داده (ثانیه)
     * @return confidence امتیاز اعتماد (0-100)
     */
    function calculateConfidence(
        uint256 currentPrice,
        uint256 twapPrice,
        uint256 liquidity,
        uint256 age
    ) internal pure returns (uint256 confidence) {
        // شروع با امتیاز کامل
        confidence = 100;
        
        // کاهش بر اساس انحراف از TWAP
        if (twapPrice > 0) {
            uint256 deviation = currentPrice > twapPrice ?
                ((currentPrice - twapPrice) * 100) / twapPrice :
                ((twapPrice - currentPrice) * 100) / twapPrice;
            
            if (deviation > 50) confidence = 0;
            else confidence = confidence - (deviation * 2);
        }
        
        // کاهش بر اساس نقدینگی کم
        if (liquidity < 1000 * Constants.PRECISION) {
            confidence = confidence / 2;
        }
        
        // کاهش بر اساس سن داده
        if (age > 3600) { // بیش از 1 ساعت
            confidence = confidence / 2;
        } else if (age > 300) { // بیش از 5 دقیقه
            confidence = confidence - ((age - 300) * confidence) / 3600;
        }
        
        return confidence;
    }

    /**
     * @dev ترکیب چند قیمت با وزن‌دهی
     * @param prices آرایه قیمت‌ها
     * @param weights آرایه وزن‌ها
     * @return weightedPrice قیمت وزن‌دار
     */
    function combineWeightedPrices(
        uint256[] memory prices,
        uint256[] memory weights
    ) internal pure returns (uint256 weightedPrice) {
        require(prices.length == weights.length, "Array length mismatch");
        if (prices.length == 0) return 0;
        
        uint256 totalWeight = 0;
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < prices.length; i++) {
            if (prices[i] > 0 && weights[i] > 0) {
                totalValue += prices[i] * weights[i];
                totalWeight += weights[i];
            }
        }
        
        if (totalWeight == 0) return 0;
        
        weightedPrice = totalValue / totalWeight;
    }

    /**
     * @dev محاسبه میانه قیمت‌ها
     * @param prices آرایه قیمت‌ها
     * @return median میانه
     */
    function calculateMedian(uint256[] memory prices) internal pure returns (uint256 median) {
        if (prices.length == 0) return 0;
        if (prices.length == 1) return prices[0];
        
        // مرتب‌سازی
        _quickSort(prices, 0, int256(prices.length - 1));
        
        uint256 mid = prices.length / 2;
        if (prices.length % 2 == 0) {
            median = (prices[mid - 1] + prices[mid]) / 2;
        } else {
            median = prices[mid];
        }
    }

    /**
     * @dev تشخیص outlier در قیمت‌ها
     * @param prices آرایه قیمت‌ها
     * @param threshold آستانه تشخیص (basis points)
     * @return outliers آرایه boolean برای outliers
     */
    function detectOutliers(
        uint256[] memory prices,
        uint256 threshold
    ) internal pure returns (bool[] memory outliers) {
        outliers = new bool[](prices.length);
        if (prices.length < 3) return outliers;
        
        uint256 median = calculateMedian(prices);
        
        for (uint256 i = 0; i < prices.length; i++) {
            if (prices[i] == 0) {
                outliers[i] = true;
                continue;
            }
            
            uint256 deviation;
            if (prices[i] > median) {
                deviation = ((prices[i] - median) * Constants.BASIS_POINTS) / median;
            } else {
                deviation = ((median - prices[i]) * Constants.BASIS_POINTS) / median;
            }
            
            outliers[i] = deviation > threshold;
        }
    }

    /**
     * @dev محاسبه volatility از قیمت‌ها
     * @param prices آرایه قیمت‌ها
     * @return volatility نوسانات (basis points)
     */
    function calculateVolatility(uint256[] memory prices) internal pure returns (uint256 volatility) {
        if (prices.length < 2) return 0;
        
        // محاسبه میانگین
        uint256 sum = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            if (prices[i] > 0) {
                sum += prices[i];
                count++;
            }
        }
        
        if (count < 2) return 0;
        uint256 mean = sum / count;
        
        // محاسبه واریانس
        uint256 variance = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            if (prices[i] > 0) {
                uint256 diff = prices[i] > mean ? prices[i] - mean : mean - prices[i];
                variance += (diff * diff) / mean; // نرمال‌سازی
            }
        }
        
        variance = variance / (count - 1);
        volatility = _sqrt(variance * Constants.BASIS_POINTS); // تبدیل به basis points
    }

    /**
     * @dev تبدیل tick به sqrt price
     */
    function _tickToSqrtPrice(int24 tick) private pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(887272)), 'T');

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /**
     * @dev تبدیل sqrt price به tick
     */
    function _sqrtPriceToTick(uint160 sqrtPriceX96) private pure returns (int24 tick) {
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, 'R');
        uint256 ratio = uint256(sqrtPriceX96) << 32;

        uint256 r = ratio;
        uint256 msb = 0;

        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        int256 log_2 = (int256(msb) - 128) << 64;

        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }

        int256 log_sqrt10001 = log_2 * 255738958999603826347141;

        int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

        tick = tickLow == tickHi ? tickLow : (_tickToSqrtPrice(tickHi) <= sqrtPriceX96 ? tickHi : tickLow);
    }

    /**
     * @dev پیدا کردن observations اطراف زمان مشخص
     */
    function _findSurroundingObservations(
        TWAPData[] memory observations,
        uint32 targetTime
    ) private pure returns (TWAPData memory before, TWAPData memory after) {
        for (uint256 i = 0; i < observations.length - 1; i++) {
            if (observations[i].timestamp <= targetTime && observations[i + 1].timestamp >= targetTime) {
                before = observations[i];
                after = observations[i + 1];
                return (before, after);
            }
        }
        
        // fallback: استفاده از اول و آخر
        if (observations.length >= 2) {
            before = observations[0];
            after = observations[observations.length - 1];
        }
    }

    /**
     * @dev محاسبه جذر
     */
    function _sqrt(uint256 x) private pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @dev مرتب‌سازی سریع
     */
    function _quickSort(uint256[] memory arr, int256 left, int256 right) private pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) _quickSort(arr, left, j);
        if (i < right) _quickSort(arr, i, right);
    }
}