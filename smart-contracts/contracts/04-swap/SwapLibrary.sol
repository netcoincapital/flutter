// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/FullMath.sol";
import "../libraries/Constants.sol";

/**
 * @title SwapLibrary
 * @dev توابع کمکی برای محاسبات swap
 */
library SwapLibrary {
    using FullMath for uint256;

    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InvalidPath();

    /**
     * @dev محاسبه مقدار خروجی با فرمول Constant Product AMM
     * @param amountIn مقدار ورودی
     * @param reserveIn ذخیره توکن ورودی
     * @param reserveOut ذخیره توکن خروجی
     * @param fee کارمزد (در واحد basis points، مثلاً 30 = 0.3%)
     * @return amountOut مقدار خروجی
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 fee
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        // محاسبه مقدار خروجی با در نظر گیری کارمزد
        // amountOut = (amountIn * (10000 - fee) * reserveOut) / ((reserveIn * 10000) + (amountIn * (10000 - fee)))
        uint256 amountInWithFee = amountIn * (Constants.BASIS_POINTS - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * Constants.BASIS_POINTS) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @dev محاسبه مقدار ورودی مورد نیاز برای مقدار خروجی مشخص
     * @param amountOut مقدار خروجی مطلوب
     * @param reserveIn ذخیره توکن ورودی
     * @param reserveOut ذخیره توکن خروجی
     * @param fee کارمزد (در واحد basis points)
     * @return amountIn مقدار ورودی مورد نیاز
     */
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 fee
    ) internal pure returns (uint256 amountIn) {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        // محاسبه مقدار ورودی با در نظر گیری کارمزد
        uint256 numerator = reserveIn * amountOut * Constants.BASIS_POINTS;
        uint256 denominator = (reserveOut - amountOut) * (Constants.BASIS_POINTS - fee);
        amountIn = (numerator / denominator) + 1; // +1 برای جبران truncation
    }

    /**
     * @dev محاسبه مقادیر خروجی برای multi-hop swap
     * @param factory آدرس factory
     * @param amountIn مقدار ورودی
     * @param path مسیر توکن‌ها
     * @return amounts آرایه مقادیر برای هر hop
     */
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, 30); // 0.3% fee
        }
    }

    /**
     * @dev محاسبه مقادیر ورودی برای multi-hop swap
     * @param factory آدرس factory
     * @param amountOut مقدار خروجی مطلوب
     * @param path مسیر توکن‌ها
     * @return amounts آرایه مقادیر برای هر hop
     */
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, 30); // 0.3% fee
        }
    }

    /**
     * @dev دریافت reserves برای دو توکن
     * @param factory آدرس factory
     * @param tokenA آدرس توکن A
     * @param tokenB آدرس توکن B
     * @return reserveA ذخیره توکن A
     * @return reserveB ذخیره توکن B
     */
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        address pair = pairFor(factory, tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ILaxcePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @dev مرتب‌سازی آدرس توکن‌ها
     */
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    /**
     * @dev محاسبه آدرس pair برای دو توکن
     */
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
        )))));
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
        if (reserveIn == 0 || reserveOut == 0) return 0;
        
        // قیمت قبل از swap
        uint256 priceBefore = (reserveOut * Constants.BASIS_POINTS) / reserveIn;
        
        // قیمت بعد از swap
        uint256 newReserveIn = reserveIn + amountIn;
        uint256 amountOut = getAmountOut(amountIn, reserveIn, reserveOut, 0); // بدون fee برای محاسبه impact
        uint256 newReserveOut = reserveOut - amountOut;
        uint256 priceAfter = (newReserveOut * Constants.BASIS_POINTS) / newReserveIn;
        
        // محاسبه impact
        if (priceAfter >= priceBefore) return 0;
        impact = ((priceBefore - priceAfter) * Constants.BASIS_POINTS) / priceBefore;
    }
}

// Interface های مورد نیاز
interface ILaxcePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}