// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SwapLibrary.sol";
import "./SlippageProtection.sol";
import "./SwapValidator.sol";
import "./PriceCalculator.sol";

/**
 * @title SwapEngine
 * @dev موتور اصلی swap با تغییر state
 */
contract SwapEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        address to;
        uint256 deadline;
    }

    struct SwapResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 priceImpact;
        uint256 fee;
        address[] path;
    }

    // Events
    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceImpact,
        uint256 fee
    );

    event MultiHopSwap(
        address indexed user,
        address[] path,
        uint256 amountIn,
        uint256 amountOut,
        uint256 totalFee
    );

    event SwapFailed(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        string reason
    );

    // State variables
    address public factory;
    SlippageProtection public slippageProtection;
    SwapValidator public swapValidator;
    PriceCalculator public priceCalculator;
    
    mapping(address => uint256) public totalSwapVolume;
    mapping(address => mapping(address => uint256)) public pairSwapVolume;
    
    // Fee collection
    address public feeCollector;
    mapping(address => uint256) public collectedFees;
    
    // Emergency controls
    bool public emergencyPaused = false;
    mapping(address => bool) public pausedPairs;

    error InvalidFactory();
    error InvalidAddress();
    error SwapFailed();
    error EmergencyPaused();
    error PairPaused();
    error InsufficientBalance();
    error InsufficientAllowance();

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    modifier pairNotPaused(address tokenA, address tokenB) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        if (pausedPairs[pair]) revert PairPaused();
        _;
    }

    constructor(
        address _factory,
        address _slippageProtection,
        address _swapValidator,
        address _priceCalculator,
        address _feeCollector
    ) Ownable(msg.sender) {
        if (_factory == address(0)) revert InvalidFactory();
        if (_slippageProtection == address(0)) revert InvalidAddress();
        if (_swapValidator == address(0)) revert InvalidAddress();
        if (_priceCalculator == address(0)) revert InvalidAddress();
        if (_feeCollector == address(0)) revert InvalidAddress();

        factory = _factory;
        slippageProtection = SlippageProtection(_slippageProtection);
        swapValidator = SwapValidator(_swapValidator);
        priceCalculator = PriceCalculator(_priceCalculator);
        feeCollector = _feeCollector;
    }

    /**
     * @dev اجرای simple swap
     * @param params پارامترهای swap
     * @return result نتیجه swap
     */
    function executeSwap(SwapParams calldata params)
        external
        nonReentrant
        notPaused
        pairNotPaused(params.tokenIn, params.tokenOut)
        returns (SwapResult memory result)
    {
        // اعتبارسنجی
        SwapValidator.SwapValidation memory validation = SwapValidator.SwapValidation({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            amountOutMin: params.amountOutMin,
            to: params.to,
            deadline: params.deadline,
            path: new address[](2)
        });
        validation.path[0] = params.tokenIn;
        validation.path[1] = params.tokenOut;

        swapValidator.validateSwap(validation);

        // بررسی balance و allowance
        _validateUserFunds(msg.sender, params.tokenIn, params.amountIn);

        // محاسبه قیمت و fee
        PriceCalculator.SwapParams memory priceParams = PriceCalculator.SwapParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            factory: factory,
            slippageTolerance: 100 // 1% default
        });

        (uint256 amountOut, uint256 priceImpact, uint256 fee) = 
            priceCalculator.calculateSwapPrice(priceParams);

        // بررسی slippage
        SlippageProtection.SlippageParams memory slippageParams = SlippageProtection.SlippageParams({
            amountIn: params.amountIn,
            amountOutMin: params.amountOutMin,
            deadline: params.deadline,
            maxSlippage: 100 // 1% default
        });

        slippageProtection.checkSlippage(slippageParams, amountOut);
        slippageProtection.checkMEVProtection(msg.sender);

        // اجرای swap
        _performSwap(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.to,
            fee
        );

        // به‌روزرسانی آمار
        _updateSwapStats(params.tokenIn, params.tokenOut, params.amountIn, fee);

        result = SwapResult({
            amountIn: params.amountIn,
            amountOut: amountOut,
            priceImpact: priceImpact,
            fee: fee,
            path: validation.path
        });

        emit Swap(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            priceImpact,
            fee
        );
    }

    /**
     * @dev اجرای multi-hop swap
     * @param amountIn مقدار ورودی
     * @param amountOutMin حداقل مقدار خروجی
     * @param path مسیر swap
     * @param to آدرس مقصد
     * @param deadline deadline
     * @return amounts مقادیر برای هر hop
     */
    function executeMultiHopSwap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        notPaused
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Deadline expired");

        // اعتبارسنجی
        SwapValidator.SwapValidation memory validation = SwapValidator.SwapValidation({
            tokenIn: path[0],
            tokenOut: path[path.length - 1],
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            to: to,
            deadline: deadline,
            path: path
        });

        swapValidator.validateSwap(validation);

        // بررسی balance و allowance
        _validateUserFunds(msg.sender, path[0], amountIn);

        // محاسبه مسیر و قیمت‌ها
        (amounts, , uint256 totalFee) = priceCalculator.calculateMultiHopPrice(
            factory,
            amountIn,
            path
        );

        require(amounts[amounts.length - 1] >= amountOutMin, "Insufficient output amount");

        // اجرای multi-hop swap
        _performMultiHopSwap(amounts, path, to, totalFee);

        // به‌روزرسانی آمار
        for (uint256 i = 0; i < path.length - 1; i++) {
            _updateSwapStats(path[i], path[i + 1], amounts[i], totalFee / (path.length - 1));
        }

        emit MultiHopSwap(
            msg.sender,
            path,
            amounts[0],
            amounts[amounts.length - 1],
            totalFee
        );
    }

    /**
     * @dev اجرای exact output swap
     * @param amountOut مقدار خروجی دقیق
     * @param amountInMax حداکثر مقدار ورودی
     * @param path مسیر swap
     * @param to آدرس مقصد
     * @param deadline deadline
     * @return amounts مقادیر واقعی
     */
    function executeExactOutputSwap(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        notPaused
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Deadline expired");

        // محاسبه مقدار ورودی مورد نیاز
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "Excessive input amount");

        // اعتبارسنجی
        SwapValidator.SwapValidation memory validation = SwapValidator.SwapValidation({
            tokenIn: path[0],
            tokenOut: path[path.length - 1],
            amountIn: amounts[0],
            amountOutMin: amountOut,
            to: to,
            deadline: deadline,
            path: path
        });

        swapValidator.validateSwap(validation);

        // بررسی balance و allowance
        _validateUserFunds(msg.sender, path[0], amounts[0]);

        // اجرای swap
        _performMultiHopSwap(amounts, path, to, 0);

        emit MultiHopSwap(
            msg.sender,
            path,
            amounts[0],
            amounts[amounts.length - 1],
            0
        );
    }

    /**
     * @dev اجرای واقعی swap
     */
    function _performSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address to,
        uint256 fee
    ) internal {
        // انتقال token ورودی از کاربر
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // دریافت آدرس pair
        address pair = SwapLibrary.pairFor(factory, tokenIn, tokenOut);

        // انتقال token به pair
        IERC20(tokenIn).safeTransfer(pair, amountIn);

        // اجرای swap در pair
        (address token0,) = SwapLibrary.sortTokens(tokenIn, tokenOut);
        (uint256 amount0Out, uint256 amount1Out) = tokenIn == token0 
            ? (uint256(0), amountOut) 
            : (amountOut, uint256(0));

        ILaxcePair(pair).swap(amount0Out, amount1Out, to, new bytes(0));

        // جمع‌آوری fee
        if (fee > 0) {
            uint256 feeAmount = (amountOut * fee) / 10000;
            IERC20(tokenOut).safeTransferFrom(to, feeCollector, feeAmount);
            collectedFees[tokenOut] += feeAmount;
        }
    }

    /**
     * @dev اجرای multi-hop swap
     */
    function _performMultiHopSwap(
        uint256[] memory amounts,
        address[] calldata path,
        address to,
        uint256 totalFee
    ) internal {
        // انتقال token ورودی از کاربر
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amounts[0]);

        for (uint256 i; i < path.length - 1; i++) {
            address pair = SwapLibrary.pairFor(factory, path[i], path[i + 1]);
            address nextRecipient = i < path.length - 2 ? 
                SwapLibrary.pairFor(factory, path[i + 1], path[i + 2]) : to;

            // انتقال token به pair
            IERC20(path[i]).safeTransfer(pair, amounts[i]);

            // اجرای swap
            (address token0,) = SwapLibrary.sortTokens(path[i], path[i + 1]);
            (uint256 amount0Out, uint256 amount1Out) = path[i] == token0 
                ? (uint256(0), amounts[i + 1]) 
                : (amounts[i + 1], uint256(0));

            ILaxcePair(pair).swap(amount0Out, amount1Out, nextRecipient, new bytes(0));
        }

        // جمع‌آوری fee از نتیجه نهایی
        if (totalFee > 0) {
            uint256 feeAmount = (amounts[amounts.length - 1] * totalFee) / 10000;
            IERC20(path[path.length - 1]).safeTransferFrom(to, feeCollector, feeAmount);
            collectedFees[path[path.length - 1]] += feeAmount;
        }
    }

    /**
     * @dev اعتبارسنجی funds کاربر
     */
    function _validateUserFunds(address user, address token, uint256 amount) internal view {
        uint256 balance = IERC20(token).balanceOf(user);
        if (balance < amount) revert InsufficientBalance();

        uint256 allowance = IERC20(token).allowance(user, address(this));
        if (allowance < amount) revert InsufficientAllowance();
    }

    /**
     * @dev به‌روزرسانی آمار swap
     */
    function _updateSwapStats(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 fee
    ) internal {
        totalSwapVolume[tokenIn] += amountIn;
        pairSwapVolume[tokenIn][tokenOut] += amountIn;
    }

    /**
     * @dev تنظیم emergency pause
     */
    function setEmergencyPause(bool paused) external onlyOwner {
        emergencyPaused = paused;
    }

    /**
     * @dev pause/unpause کردن pair خاص
     */
    function setPairPaused(address tokenA, address tokenB, bool paused) external onlyOwner {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        pausedPairs[pair] = paused;
    }

    /**
     * @dev تنظیم fee collector
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        if (_feeCollector == address(0)) revert InvalidAddress();
        feeCollector = _feeCollector;
    }

    /**
     * @dev دریافت آمار swap
     */
    function getSwapStats(address token) external view returns (uint256 volume) {
        return totalSwapVolume[token];
    }

    /**
     * @dev دریافت آمار pair
     */
    function getPairStats(address tokenA, address tokenB) external view returns (uint256 volume) {
        return pairSwapVolume[tokenA][tokenB];
    }
}

// Interface مورد نیاز
interface ILaxcePair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}