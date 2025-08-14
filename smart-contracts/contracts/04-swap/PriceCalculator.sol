// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/FullMath.sol";
import "../libraries/Constants.sol";
import "./SwapLibrary.sol";

/**
 * @title PriceCalculator
 * @dev محاسبه قیمت‌ها و price impact برای swaps
 */
contract PriceCalculator is Ownable, ReentrancyGuard {
    using FullMath for uint256;

    struct PriceInfo {
        uint256 price;              // قیمت فعلی
        uint256 priceImpact;        // تأثیر روی قیمت (basis points)
        uint256 fee;                // کارمزد محاسبه شده
        uint256 timestamp;          // زمان آخرین به‌روزرسانی
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        address factory;
        uint256 slippageTolerance;  // در basis points
    }

    // Events
    event PriceCalculated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceImpact,
        uint256 fee
    );

    event MaxPriceImpactUpdated(uint256 oldMax, uint256 newMax);

    // State variables
    address public factory;
    mapping(address => mapping(address => PriceInfo)) public priceInfo;
    
    // Price impact limits
    uint256 public maxPriceImpact = 500; // 5% maximum price impact
    uint256 public constant HIGH_IMPACT_THRESHOLD = 200; // 2% high impact warning
    
    // Fee tiers
    uint256 public constant LOW_FEE = 5;     // 0.05%
    uint256 public constant MEDIUM_FEE = 30; // 0.30%
    uint256 public constant HIGH_FEE = 100;  // 1.00%

    error InvalidFactory();
    error InvalidTokens();
    error ExcessivePriceImpact();
    error InsufficientLiquidity();
    error InvalidAmount();

    constructor(address _factory) Ownable(msg.sender) {
        if (_factory == address(0)) revert InvalidFactory();
        factory = _factory;
    }

    /**
     * @dev محاسبه قیمت و اطلاعات swap
     * @param params پارامترهای swap
     * @return amountOut مقدار خروجی
     * @return priceImpact تأثیر روی قیمت
     * @return fee کارمزد
     */
    function calculateSwapPrice(SwapParams calldata params)
        external
        view
        returns (
            uint256 amountOut,
            uint256 priceImpact,
            uint256 fee
        )
    {
        if (params.tokenIn == params.tokenOut) revert InvalidTokens();
        if (params.amountIn == 0) revert InvalidAmount();

        // دریافت reserves
        (uint256 reserveIn, uint256 reserveOut) = SwapLibrary.getReserves(
            params.factory,
            params.tokenIn,
            params.tokenOut
        );

        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        // محاسبه price impact
        priceImpact = SwapLibrary.calculatePriceImpact(
            params.amountIn,
            reserveIn,
            reserveOut
        );

        // انتخاب fee tier بر اساس price impact
        fee = _selectFeeTier(priceImpact);

        // محاسبه مقدار خروجی
        amountOut = SwapLibrary.getAmountOut(
            params.amountIn,
            reserveIn,
            reserveOut,
            fee
        );

        // بررسی حد مجاز price impact
        if (priceImpact > maxPriceImpact) revert ExcessivePriceImpact();
    }

    /**
     * @dev محاسبه قیمت برای multi-hop swap
     * @param factory آدرس factory
     * @param amountIn مقدار ورودی
     * @param path مسیر swap
     * @return amounts مقادیر برای هر hop
     * @return totalPriceImpact کل price impact
     * @return totalFee کل کارمزد
     */
    function calculateMultiHopPrice(
        address factory,
        uint256 amountIn,
        address[] calldata path
    )
        external
        view
        returns (
            uint256[] memory amounts,
            uint256 totalPriceImpact,
            uint256 totalFee
        )
    {
        if (path.length < 2) revert InvalidTokens();
        if (amountIn == 0) revert InvalidAmount();

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = SwapLibrary.getReserves(
                factory,
                path[i],
                path[i + 1]
            );

            // محاسبه price impact برای این hop
            uint256 hopImpact = SwapLibrary.calculatePriceImpact(
                amounts[i],
                reserveIn,
                reserveOut
            );
            totalPriceImpact += hopImpact;

            // انتخاب fee tier
            uint256 hopFee = _selectFeeTier(hopImpact);
            totalFee += hopFee;

            // محاسبه مقدار خروجی
            amounts[i + 1] = SwapLibrary.getAmountOut(
                amounts[i],
                reserveIn,
                reserveOut,
                hopFee
            );
        }

        // بررسی کل price impact
        if (totalPriceImpact > maxPriceImpact) revert ExcessivePriceImpact();
    }

    /**
     * @dev محاسبه minimum amount out با در نظر گیری slippage
     * @param amountOut مقدار خروجی پیش‌بینی شده
     * @param slippageTolerance تحمل slippage در basis points
     * @return minAmountOut حداقل مقدار خروجی
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
     * @dev محاسبه maximum amount in با در نظر گیری slippage
     * @param amountIn مقدار ورودی پیش‌بینی شده
     * @param slippageTolerance تحمل slippage در basis points
     * @return maxAmountIn حداکثر مقدار ورودی
     */
    function calculateMaxAmountIn(
        uint256 amountIn,
        uint256 slippageTolerance
    ) external pure returns (uint256 maxAmountIn) {
        if (slippageTolerance > Constants.BASIS_POINTS) {
            slippageTolerance = Constants.BASIS_POINTS;
        }
        
        maxAmountIn = (amountIn * (Constants.BASIS_POINTS + slippageTolerance)) / Constants.BASIS_POINTS;
    }

    /**
     * @dev دریافت قیمت spot برای جفت توکن
     * @param tokenA آدرس توکن A
     * @param tokenB آدرس توکن B
     * @return price قیمت tokenA بر حسب tokenB
     */
    function getSpotPrice(
        address tokenA,
        address tokenB
    ) external view returns (uint256 price) {
        if (tokenA == tokenB) return Constants.BASIS_POINTS;

        (uint256 reserveA, uint256 reserveB) = SwapLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );

        if (reserveA == 0 || reserveB == 0) return 0;

        // قیمت = reserveB / reserveA * PRECISION
        price = (reserveB * Constants.PRECISION) / reserveA;
    }

    /**
     * @dev به‌روزرسانی اطلاعات قیمت
     * @param tokenIn توکن ورودی
     * @param tokenOut توکن خروجی
     * @param price قیمت جدید
     * @param priceImpact تأثیر قیمت
     * @param fee کارمزد
     */
    function updatePriceInfo(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 priceImpact,
        uint256 fee
    ) external nonReentrant {
        // فقط contracts مجاز می‌توانند قیمت را به‌روزرسانی کنند
        // در آینده می‌توان access control اضافه کرد

        priceInfo[tokenIn][tokenOut] = PriceInfo({
            price: price,
            priceImpact: priceImpact,
            fee: fee,
            timestamp: block.timestamp
        });

        emit PriceCalculated(tokenIn, tokenOut, 0, 0, priceImpact, fee);
    }

    /**
     * @dev تنظیم حداکثر price impact مجاز
     * @param _maxPriceImpact حداکثر price impact در basis points
     */
    function setMaxPriceImpact(uint256 _maxPriceImpact) external onlyOwner {
        require(_maxPriceImpact <= 1000, "Too high"); // حداکثر 10%
        uint256 oldMax = maxPriceImpact;
        maxPriceImpact = _maxPriceImpact;
        emit MaxPriceImpactUpdated(oldMax, _maxPriceImpact);
    }

    /**
     * @dev انتخاب fee tier مناسب بر اساس price impact
     * @param priceImpact price impact در basis points
     * @return fee کارمزد انتخاب شده
     */
    function _selectFeeTier(uint256 priceImpact) internal pure returns (uint256 fee) {
        if (priceImpact <= 50) {        // <= 0.5%
            fee = LOW_FEE;              // 0.05%
        } else if (priceImpact <= 200) { // <= 2%
            fee = MEDIUM_FEE;           // 0.30%
        } else {                        // > 2%
            fee = HIGH_FEE;             // 1.00%
        }
    }

    /**
     * @dev بررسی اینکه آیا swap مقرون به صرفه است
     * @param amountIn مقدار ورودی
     * @param amountOut مقدار خروجی
     * @param gasPrice قیمت gas
     * @return isEconomical آیا مقرون به صرفه است
     */
    function isSwapEconomical(
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasPrice
    ) external pure returns (bool isEconomical) {
        // محاسبه تقریبی هزینه gas (حدود 150,000 gas برای swap)
        uint256 gasCost = gasPrice * 150000;
        
        // swap مقرون به صرفه است اگر value معامله حداقل 10 برابر gas cost باشد
        uint256 minTradeValue = gasCost * 10;
        
        // فرض می‌کنیم amountOut به صورت USD محاسبه شده
        isEconomical = amountOut >= minTradeValue;
    }
}