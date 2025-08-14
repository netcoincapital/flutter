// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SwapLibrary.sol";
import "./PriceCalculator.sol";
import "../libraries/Constants.sol";
import "../libraries/FullMath.sol";

/**
 * @title SwapQuoter
 * @dev محاسبه off-chain quotes بدون تغییر state
 */
contract SwapQuoter {
    using FullMath for uint256;

    struct QuoteParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address factory;
        uint256 slippageTolerance;
    }

    struct QuoteResult {
        uint256 amountOut;
        uint256 amountOutMin;
        uint256 priceImpact;
        uint256 fee;
        uint256 gasEstimate;
        bool feasible;
        string warning;
    }

    struct MultiHopQuoteResult {
        uint256[] amounts;
        uint256 totalPriceImpact;
        uint256 totalFee;
        uint256 gasEstimate;
        bool feasible;
        string warning;
    }

    // Gas estimates for different operations
    uint256 public constant SIMPLE_SWAP_GAS = 150000;
    uint256 public constant MULTI_HOP_BASE_GAS = 120000;
    uint256 public constant PER_HOP_GAS = 50000;
    uint256 public constant APPROVE_GAS = 50000;

    // Warning thresholds
    uint256 public constant HIGH_PRICE_IMPACT_THRESHOLD = 300; // 3%
    uint256 public constant VERY_HIGH_PRICE_IMPACT_THRESHOLD = 500; // 5%
    uint256 public constant LOW_LIQUIDITY_THRESHOLD = 1000 * 10**18; // 1000 tokens

    /**
     * @dev دریافت quote برای simple swap
     * @param params پارامترهای quote
     * @return result نتیجه quote
     */
    function getQuote(QuoteParams calldata params) 
        external 
        view 
        returns (QuoteResult memory result) 
    {
        try this._getQuoteInternal(params) returns (QuoteResult memory _result) {
            result = _result;
        } catch {
            result = QuoteResult({
                amountOut: 0,
                amountOutMin: 0,
                priceImpact: 0,
                fee: 0,
                gasEstimate: SIMPLE_SWAP_GAS,
                feasible: false,
                warning: "Quote calculation failed"
            });
        }
    }

    /**
     * @dev محاسبه داخلی quote
     */
    function _getQuoteInternal(QuoteParams calldata params) 
        external 
        view 
        returns (QuoteResult memory result) 
    {
        // دریافت reserves
        (uint256 reserveIn, uint256 reserveOut) = SwapLibrary.getReserves(
            params.factory,
            params.tokenIn,
            params.tokenOut
        );

        if (reserveIn == 0 || reserveOut == 0) {
            return QuoteResult({
                amountOut: 0,
                amountOutMin: 0,
                priceImpact: 0,
                fee: 0,
                gasEstimate: SIMPLE_SWAP_GAS,
                feasible: false,
                warning: "No liquidity available"
            });
        }

        // محاسبه price impact
        uint256 priceImpact = SwapLibrary.calculatePriceImpact(
            params.amountIn,
            reserveIn,
            reserveOut
        );

        // انتخاب fee tier
        uint256 fee = _selectFeeTier(priceImpact);

        // محاسبه مقدار خروجی
        uint256 amountOut = SwapLibrary.getAmountOut(
            params.amountIn,
            reserveIn,
            reserveOut,
            fee
        );

        // محاسبه minimum amount با slippage
        uint256 amountOutMin = (amountOut * (Constants.BASIS_POINTS - params.slippageTolerance)) / Constants.BASIS_POINTS;

        // بررسی امکان‌پذیری
        bool feasible = _checkFeasibility(reserveIn, reserveOut, params.amountIn, priceImpact);

        // تولید هشدارها
        string memory warning = _generateWarning(reserveIn, reserveOut, priceImpact);

        // تخمین gas
        uint256 gasEstimate = _estimateGas(1); // 1 hop

        result = QuoteResult({
            amountOut: amountOut,
            amountOutMin: amountOutMin,
            priceImpact: priceImpact,
            fee: fee,
            gasEstimate: gasEstimate,
            feasible: feasible,
            warning: warning
        });
    }

    /**
     * @dev دریافت quote برای multi-hop swap
     * @param factory آدرس factory
     * @param amountIn مقدار ورودی
     * @param path مسیر swap
     * @param slippageTolerance تحمل slippage
     * @return result نتیجه quote
     */
    function getMultiHopQuote(
        address factory,
        uint256 amountIn,
        address[] calldata path,
        uint256 slippageTolerance
    ) external view returns (MultiHopQuoteResult memory result) {
        if (path.length < 2) {
            return MultiHopQuoteResult({
                amounts: new uint256[](0),
                totalPriceImpact: 0,
                totalFee: 0,
                gasEstimate: MULTI_HOP_BASE_GAS,
                feasible: false,
                warning: "Invalid path"
            });
        }

        try this._getMultiHopQuoteInternal(factory, amountIn, path, slippageTolerance) 
            returns (MultiHopQuoteResult memory _result) {
            result = _result;
        } catch {
            result = MultiHopQuoteResult({
                amounts: new uint256[](0),
                totalPriceImpact: 0,
                totalFee: 0,
                gasEstimate: _estimateGas(path.length - 1),
                feasible: false,
                warning: "Multi-hop quote calculation failed"
            });
        }
    }

    /**
     * @dev محاسبه داخلی multi-hop quote
     */
    function _getMultiHopQuoteInternal(
        address factory,
        uint256 amountIn,
        address[] calldata path,
        uint256 slippageTolerance
    ) external view returns (MultiHopQuoteResult memory result) {
        uint256[] memory amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        uint256 totalPriceImpact = 0;
        uint256 totalFee = 0;
        bool feasible = true;
        string memory warning = "";

        for (uint256 i = 0; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = SwapLibrary.getReserves(
                factory,
                path[i],
                path[i + 1]
            );

            if (reserveIn == 0 || reserveOut == 0) {
                feasible = false;
                warning = "No liquidity in path";
                break;
            }

            // محاسبه price impact برای این hop
            uint256 hopPriceImpact = SwapLibrary.calculatePriceImpact(
                amounts[i],
                reserveIn,
                reserveOut
            );
            totalPriceImpact += hopPriceImpact;

            // انتخاب fee tier
            uint256 hopFee = _selectFeeTier(hopPriceImpact);
            totalFee += hopFee;

            // محاسبه مقدار خروجی
            amounts[i + 1] = SwapLibrary.getAmountOut(
                amounts[i],
                reserveIn,
                reserveOut,
                hopFee
            );

            // بررسی امکان‌پذیری هر hop
            if (!_checkFeasibility(reserveIn, reserveOut, amounts[i], hopPriceImpact)) {
                feasible = false;
                warning = string(abi.encodePacked("High impact at hop ", _toString(i + 1)));
            }
        }

        // تولید هشدار کلی
        if (bytes(warning).length == 0) {
            warning = _generateMultiHopWarning(totalPriceImpact, path.length - 1);
        }

        // محاسبه minimum amount out
        uint256 finalAmountOut = amounts.length > 0 ? amounts[amounts.length - 1] : 0;
        uint256 amountOutMin = (finalAmountOut * (Constants.BASIS_POINTS - slippageTolerance)) / Constants.BASIS_POINTS;

        // اصلاح amounts برای نمایش minimum
        if (amounts.length > 0) {
            amounts[amounts.length - 1] = amountOutMin;
        }

        result = MultiHopQuoteResult({
            amounts: amounts,
            totalPriceImpact: totalPriceImpact,
            totalFee: totalFee,
            gasEstimate: _estimateGas(path.length - 1),
            feasible: feasible,
            warning: warning
        });
    }

    /**
     * @dev دریافت بهترین مسیر برای swap
     * @param factory آدرس factory
     * @param tokenIn توکن ورودی
     * @param tokenOut توکن خروجی
     * @param amountIn مقدار ورودی
     * @return bestPath بهترین مسیر
     * @return bestAmountOut بهترین مقدار خروجی
     */
    function getBestPath(
        address factory,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (address[] memory bestPath, uint256 bestAmountOut) {
        // مسیر مستقیم
        address[] memory directPath = new address[](2);
        directPath[0] = tokenIn;
        directPath[1] = tokenOut;
        
        QuoteParams memory directParams = QuoteParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            factory: factory,
            slippageTolerance: 100
        });
        
        QuoteResult memory directQuote = this.getQuote(directParams);
        
        bestPath = directPath;
        bestAmountOut = directQuote.amountOut;

        // TODO: پیاده‌سازی الگوریتم پیدا کردن بهترین مسیر با intermediate tokens
        // در حال حاضر فقط مسیر مستقیم را برمی‌گرداند
    }

    /**
     * @dev محاسبه قیمت تبدیل بین دو توکن
     * @param factory آدرس factory
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @return price قیمت tokenA بر حسب tokenB
     */
    function getPrice(
        address factory,
        address tokenA,
        address tokenB
    ) external view returns (uint256 price) {
        if (tokenA == tokenB) return Constants.PRECISION;

        (uint256 reserveA, uint256 reserveB) = SwapLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );

        if (reserveA == 0 || reserveB == 0) return 0;

        price = (reserveB * Constants.PRECISION) / reserveA;
    }

    /**
     * @dev دریافت اطلاعات نقدینگی pair
     * @param factory آدرس factory
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @return reserveA ذخیره A
     * @return reserveB ذخیره B
     * @return liquidityHealth سلامت نقدینگی (0-100)
     */
    function getLiquidityInfo(
        address factory,
        address tokenA,
        address tokenB
    ) external view returns (
        uint256 reserveA,
        uint256 reserveB,
        uint256 liquidityHealth
    ) {
        (reserveA, reserveB) = SwapLibrary.getReserves(factory, tokenA, tokenB);
        
        // محاسبه liquidity health بر اساس حجم و تعادل
        if (reserveA == 0 || reserveB == 0) {
            liquidityHealth = 0;
        } else {
            uint256 totalLiquidity = reserveA + reserveB;
            uint256 balance = (reserveA < reserveB ? reserveA : reserveB) * 100 / 
                             (reserveA > reserveB ? reserveA : reserveB);
            
            if (totalLiquidity < LOW_LIQUIDITY_THRESHOLD) {
                liquidityHealth = balance / 2; // کاهش امتیاز برای نقدینگی کم
            } else {
                liquidityHealth = balance;
            }
        }
    }

    /**
     * @dev انتخاب fee tier بر اساس price impact
     */
    function _selectFeeTier(uint256 priceImpact) internal pure returns (uint256 fee) {
        if (priceImpact <= 50) {        // <= 0.5%
            fee = 5;                    // 0.05%
        } else if (priceImpact <= 200) { // <= 2%
            fee = 30;                   // 0.30%
        } else {                        // > 2%
            fee = 100;                  // 1.00%
        }
    }

    /**
     * @dev بررسی امکان‌پذیری swap
     */
    function _checkFeasibility(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 amountIn,
        uint256 priceImpact
    ) internal pure returns (bool) {
        // بررسی نقدینگی کافی
        if (reserveIn < LOW_LIQUIDITY_THRESHOLD || reserveOut < LOW_LIQUIDITY_THRESHOLD) {
            return false;
        }
        
        // بررسی price impact
        if (priceImpact > VERY_HIGH_PRICE_IMPACT_THRESHOLD) {
            return false;
        }
        
        // بررسی اینکه swap بیش از 30% pool را استفاده نکند
        if (amountIn > reserveIn * 30 / 100) {
            return false;
        }
        
        return true;
    }

    /**
     * @dev تولید هشدار برای simple swap
     */
    function _generateWarning(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 priceImpact
    ) internal pure returns (string memory) {
        if (reserveIn < LOW_LIQUIDITY_THRESHOLD || reserveOut < LOW_LIQUIDITY_THRESHOLD) {
            return "Low liquidity warning";
        }
        
        if (priceImpact > VERY_HIGH_PRICE_IMPACT_THRESHOLD) {
            return "Very high price impact";
        }
        
        if (priceImpact > HIGH_PRICE_IMPACT_THRESHOLD) {
            return "High price impact";
        }
        
        return "";
    }

    /**
     * @dev تولید هشدار برای multi-hop swap
     */
    function _generateMultiHopWarning(
        uint256 totalPriceImpact,
        uint256 hopCount
    ) internal pure returns (string memory) {
        if (totalPriceImpact > VERY_HIGH_PRICE_IMPACT_THRESHOLD) {
            return "Very high cumulative price impact";
        }
        
        if (totalPriceImpact > HIGH_PRICE_IMPACT_THRESHOLD) {
            return "High cumulative price impact";
        }
        
        if (hopCount > 3) {
            return "Long path may increase slippage";
        }
        
        return "";
    }

    /**
     * @dev تخمین gas مصرفی
     */
    function _estimateGas(uint256 hopCount) internal pure returns (uint256) {
        if (hopCount == 1) {
            return SIMPLE_SWAP_GAS;
        } else {
            return MULTI_HOP_BASE_GAS + (hopCount * PER_HOP_GAS);
        }
    }

    /**
     * @dev تبدیل عدد به string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
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
}