// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "../01-core/AccessControl.sol";
import "../03-pool/PoolFactory.sol";
import "../03-pool/LaxcePool.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Interfaces.sol";
import "../libraries/FullMath.sol";
import "../libraries/SqrtPriceMath.sol";
import "../libraries/SwapMath.sol";
import "./Quoter.sol";

/**
 * @title SwapRouter
 * @dev کانترکت اجرای مبادلات با قابلیت‌های پیشرفته
 * @notice کانترکت اصلی برای اجرای swap با حمایت از multi-hop و MEV protection
 */
contract SwapRouter is Pausable, LaxceAccessControl, Multicall {
    using SafeERC20 for IERC20;
    using LaxceReentrancyGuard for LaxceReentrancyGuard.ReentrancyData;
    using SwapMath for SwapMath.SwapParams;
    
    // ==================== CONSTANTS ====================
    
    /// @dev deadline پیش‌فرض (30 دقیقه)
    uint256 public constant DEFAULT_DEADLINE = 30 minutes;
    
    /// @dev حداکثر slippage (50%)
    uint256 public constant MAX_SLIPPAGE = 5000;
    
    /// @dev حداقل slippage (0.01%)
    uint256 public constant MIN_SLIPPAGE = 1;
    
    /// @dev حداکثر hops برای multi-hop swap
    uint256 public constant MAX_HOPS = 3;
    
    // ==================== STRUCTS ====================
    
    /// @dev پارامترهای exact input single
    struct ExactInputSingleParams {
        address tokenIn;            // توکن ورودی
        address tokenOut;           // توکن خروجی
        uint24 fee;                 // کارمزد pool
        address recipient;          // دریافت کننده
        uint256 deadline;           // مهلت زمانی
        uint256 amountIn;           // مقدار ورودی
        uint256 amountOutMinimum;   // حداقل خروجی
        uint160 sqrtPriceLimitX96;  // حد قیمت
    }
    
    /// @dev پارامترهای exact output single
    struct ExactOutputSingleParams {
        address tokenIn;            // توکن ورودی
        address tokenOut;           // توکن خروجی
        uint24 fee;                 // کارمزد pool
        address recipient;          // دریافت کننده
        uint256 deadline;           // مهلت زمانی
        uint256 amountOut;          // مقدار خروجی
        uint256 amountInMaximum;    // حداکثر ورودی
        uint160 sqrtPriceLimitX96;  // حد قیمت
    }
    
    /// @dev پارامترهای exact input multi-hop
    struct ExactInputParams {
        bytes path;                 // مسیر encoded
        address recipient;          // دریافت کننده
        uint256 deadline;           // مهلت زمانی
        uint256 amountIn;           // مقدار ورودی
        uint256 amountOutMinimum;   // حداقل خروجی
    }
    
    /// @dev پارامترهای exact output multi-hop
    struct ExactOutputParams {
        bytes path;                 // مسیر encoded
        address recipient;          // دریافت کننده
        uint256 deadline;           // مهلت زمانی
        uint256 amountOut;          // مقدار خروجی
        uint256 amountInMaximum;    // حداکثر ورودی
    }
    
    /// @dev اطلاعات swap
    struct SwapInfo {
        address tokenIn;            // توکن ورودی
        address tokenOut;           // توکن خروجی
        uint256 amountIn;           // مقدار ورودی
        uint256 amountOut;          // مقدار خروجی
        uint256 feeAmount;          // کارمزد
        uint256 priceImpact;        // تاثیر قیمت
        uint256 gasUsed;            // گاز استفاده شده
        address[] pools;            // pools استفاده شده
    }
    
    /// @dev تنظیمات MEV protection
    struct MEVProtectionConfig {
        bool enabled;               // فعال بودن
        uint256 maxPriceImpact;     // حداکثر تاثیر قیمت
        uint256 minBlockDelay;      // حداقل تاخیر block
        uint256 maxSlippageTolerance; // حداکثر slippage
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev reentrancy guard instance
    LaxceReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس PoolFactory
    address public immutable factory;
    
    /// @dev آدرس WETH9
    address public immutable WETH9;
    
    /// @dev آدرس Quoter
    address public quoter;
    
    /// @dev cache pool addresses
    mapping(bytes32 => address) private _poolCache;
    
    /// @dev default slippage (5%)
    uint256 public defaultSlippage = 500;
    
    /// @dev router fee (0.01%)
    uint256 public routerFee = 1;
    
    /// @dev router fee recipient
    address public routerFeeRecipient;
    
    /// @dev MEV protection config
    MEVProtectionConfig public mevProtection;
    
    /// @dev blacklisted tokens
    mapping(address => bool) public blacklistedTokens;
    
    /// @dev whitelisted tokens (if whitelist mode enabled)
    mapping(address => bool) public whitelistedTokens;
    
    /// @dev whitelist mode enabled
    bool public whitelistMode;
    
    /// @dev user swap history for MEV protection
    mapping(address => mapping(bytes32 => uint256)) private _lastSwapBlock;
    
    /// @dev emergency mode
    bool public emergencyMode;
    
    // ==================== EVENTS ====================
    
    event SwapExecuted(
        address indexed sender,
        address indexed recipient,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAmount
    );
    
    event MultiHopSwap(
        address indexed sender,
        address indexed recipient,
        bytes path,
        uint256 amountIn,
        uint256 amountOut
    );
    
    event RouterFeeUpdated(uint256 oldFee, uint256 newFee);
    event RouterFeeRecipientUpdated(address oldRecipient, address newRecipient);
    event DefaultSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event MEVProtectionUpdated(MEVProtectionConfig config);
    event TokenBlacklisted(address indexed token, bool blacklisted);
    event TokenWhitelisted(address indexed token, bool whitelisted);
    event WhitelistModeToggled(bool enabled);
    event EmergencyModeToggled(bool enabled);
    event QuoterUpdated(address oldQuoter, address newQuoter);
    
    // ==================== ERRORS ====================
    
    error SwapRouter__DeadlineExpired();
    error SwapRouter__InsufficientAmountOut();
    error SwapRouter__ExcessiveAmountIn();
    error SwapRouter__InvalidPath();
    error SwapRouter__TokenBlacklisted();
    error SwapRouter__TokenNotWhitelisted();
    error SwapRouter__MEVProtectionTriggered();
    error SwapRouter__ExcessivePriceImpact();
    error SwapRouter__EmergencyMode();
    error SwapRouter__InvalidSlippage();
    error SwapRouter__PoolNotFound();
    error SwapRouter__InvalidAmount();
    error SwapRouter__TransferFailed();
    error SwapRouter__InsufficientBalance();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert SwapRouter__DeadlineExpired();
        _;
    }
    
    modifier notEmergency() {
        if (emergencyMode) revert SwapRouter__EmergencyMode();
        _;
    }
    
    modifier validTokens(address tokenA, address tokenB) {
        if (blacklistedTokens[tokenA] || blacklistedTokens[tokenB]) {
            revert SwapRouter__TokenBlacklisted();
        }
        
        if (whitelistMode) {
            if (!whitelistedTokens[tokenA] || !whitelistedTokens[tokenB]) {
                revert SwapRouter__TokenNotWhitelisted();
            }
        }
        _;
    }
    
    modifier mevProtectionCheck(address tokenIn, address tokenOut, uint256 amountIn) {
        if (mevProtection.enabled) {
            bytes32 swapHash = keccak256(abi.encodePacked(tokenIn, tokenOut, amountIn));
            
            if (_lastSwapBlock[msg.sender][swapHash] + mevProtection.minBlockDelay > block.number) {
                revert SwapRouter__MEVProtectionTriggered();
            }
            
            _lastSwapBlock[msg.sender][swapHash] = block.number;
        }
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(
        address _factory,
        address _WETH9,
        address _quoter
    ) {
        factory = _factory;
        WETH9 = _WETH9;
        quoter = _quoter;
        routerFeeRecipient = msg.sender;
        
        _reentrancyGuard.initialize();
        
        // گرنت نقش‌های پیش‌فرض
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // تنظیم MEV protection پیش‌فرض
        mevProtection = MEVProtectionConfig({
            enabled: false,
            maxPriceImpact: 1000, // 10%
            minBlockDelay: 1,
            maxSlippageTolerance: 500 // 5%
        });
    }
    
    // ==================== SWAP FUNCTIONS ====================
    
    /**
     * @notice exact input single hop swap
     * @param params پارامترهای swap
     * @return amountOut مقدار خروجی
     */
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        notEmergency
        validTokens(params.tokenIn, params.tokenOut)
        mevProtection(params.tokenIn, params.tokenOut, params.amountIn)
        returns (uint256 amountOut)
    {
        if (params.amountIn == 0) revert SwapRouter__InvalidAmount();
        
        // دریافت quote برای بررسی price impact
        Quoter.QuoteResult memory quote = _getQuote(
            params.tokenIn,
            params.tokenOut,
            params.fee,
            params.amountIn,
            true
        );
        
        // بررسی price impact
        if (mevProtection.enabled && quote.priceImpact > mevProtection.maxPriceImpact) {
            revert SwapRouter__ExcessivePriceImpact();
        }
        
        // انتقال توکن ورودی
        _transferTokenIn(params.tokenIn, params.amountIn);
        
        // اجرای swap
        amountOut = _executeSwap(
            params.tokenIn,
            params.tokenOut,
            params.fee,
            params.amountIn,
            params.amountOutMinimum,
            params.recipient,
            params.sqrtPriceLimitX96
        );
        
        emit SwapExecuted(
            msg.sender,
            params.recipient,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            quote.feeAmount
        );
    }
    
    /**
     * @notice exact output single hop swap
     * @param params پارامترهای swap
     * @return amountIn مقدار ورودی
     */
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        notEmergency
        validTokens(params.tokenIn, params.tokenOut)
        returns (uint256 amountIn)
    {
        if (params.amountOut == 0) revert SwapRouter__InvalidAmount();
        
        // دریافت quote
        Quoter.QuoteResult memory quote = _getQuote(
            params.tokenIn,
            params.tokenOut,
            params.fee,
            params.amountOut,
            false
        );
        
        amountIn = quote.amountOut; // در exact output، این amount in است
        
        if (amountIn > params.amountInMaximum) {
            revert SwapRouter__ExcessiveAmountIn();
        }
        
        // انتقال توکن ورودی
        _transferTokenIn(params.tokenIn, amountIn);
        
        // اجرای swap
        uint256 actualAmountOut = _executeSwap(
            params.tokenIn,
            params.tokenOut,
            params.fee,
            amountIn,
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96
        );
        
        if (actualAmountOut < params.amountOut) {
            revert SwapRouter__InsufficientAmountOut();
        }
        
        emit SwapExecuted(
            msg.sender,
            params.recipient,
            params.tokenIn,
            params.tokenOut,
            amountIn,
            actualAmountOut,
            quote.feeAmount
        );
    }
    
    /**
     * @notice exact input multi-hop swap
     * @param params پارامترهای swap
     * @return amountOut مقدار خروجی
     */
    function exactInput(ExactInputParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        notEmergency
        returns (uint256 amountOut)
    {
        if (params.amountIn == 0) revert SwapRouter__InvalidAmount();
        
        // decode path
        (address[] memory tokens, uint24[] memory fees) = _decodePath(params.path);
        if (tokens.length > MAX_HOPS + 1) revert SwapRouter__InvalidPath();
        
        // بررسی tokens
        for (uint i = 0; i < tokens.length; i++) {
            if (blacklistedTokens[tokens[i]]) revert SwapRouter__TokenBlacklisted();
            if (whitelistMode && !whitelistedTokens[tokens[i]]) {
                revert SwapRouter__TokenNotWhitelisted();
            }
        }
        
        // انتقال توکن ورودی
        _transferTokenIn(tokens[0], params.amountIn);
        
        // اجرای multi-hop swap
        amountOut = _executeMultiHopSwap(
            tokens,
            fees,
            params.amountIn,
            params.amountOutMinimum,
            params.recipient,
            true
        );
        
        emit MultiHopSwap(
            msg.sender,
            params.recipient,
            params.path,
            params.amountIn,
            amountOut
        );
    }
    
    /**
     * @notice exact output multi-hop swap
     * @param params پارامترهای swap
     * @return amountIn مقدار ورودی
     */
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        notEmergency
        returns (uint256 amountIn)
    {
        if (params.amountOut == 0) revert SwapRouter__InvalidAmount();
        
        // decode path (معکوس برای exact output)
        (address[] memory tokens, uint24[] memory fees) = _decodePath(params.path);
        if (tokens.length > MAX_HOPS + 1) revert SwapRouter__InvalidPath();
        
        // محاسبه amount in مورد نیاز
        amountIn = _calculateRequiredInput(tokens, fees, params.amountOut);
        
        if (amountIn > params.amountInMaximum) {
            revert SwapRouter__ExcessiveAmountIn();
        }
        
        // انتقال توکن ورودی
        _transferTokenIn(tokens[0], amountIn);
        
        // اجرای multi-hop swap
        uint256 actualAmountOut = _executeMultiHopSwap(
            tokens,
            fees,
            amountIn,
            params.amountOut,
            params.recipient,
            false
        );
        
        if (actualAmountOut < params.amountOut) {
            revert SwapRouter__InsufficientAmountOut();
        }
        
        emit MultiHopSwap(
            msg.sender,
            params.recipient,
            params.path,
            amountIn,
            actualAmountOut
        );
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev اجرای single swap
     */
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountOut) {
        address poolAddress = _getPoolAddress(tokenIn, tokenOut, fee);
        if (poolAddress == address(0)) revert SwapRouter__PoolNotFound();
        
        LaxcePool pool = LaxcePool(poolAddress);
        
        // تعیین جهت swap
        bool zeroForOne = tokenIn < tokenOut;
        
        // اجرای swap
        (int256 amount0, int256 amount1) = pool.swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96 == 0 
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
        
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
        
        if (amountOut < amountOutMin) {
            revert SwapRouter__InsufficientAmountOut();
        }
        
        // کسر router fee
        _collectRouterFee(tokenOut, amountOut);
    }
    
    /**
     * @dev اجرای multi-hop swap
     */
    function _executeMultiHopSwap(
        address[] memory tokens,
        uint24[] memory fees,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        bool exactInput
    ) internal returns (uint256 amountOut) {
        uint256 currentAmount = amountIn;
        
        for (uint i = 0; i < tokens.length - 1; i++) {
            address tokenInHop = tokens[i];
            address tokenOutHop = tokens[i + 1];
            uint24 feeHop = fees[i];
            
            address recipientHop = (i == tokens.length - 2) ? recipient : address(this);
            
            currentAmount = _executeSwap(
                tokenInHop,
                tokenOutHop,
                feeHop,
                currentAmount,
                0, // no minimum for intermediate hops
                recipientHop,
                0 // no price limit for intermediate hops
            );
        }
        
        amountOut = currentAmount;
        
        if (amountOut < amountOutMin) {
            revert SwapRouter__InsufficientAmountOut();
        }
    }
    
    /**
     * @dev محاسبه input مورد نیاز برای exact output
     */
    function _calculateRequiredInput(
        address[] memory tokens,
        uint24[] memory fees,
        uint256 amountOut
    ) internal view returns (uint256 amountIn) {
        uint256 currentAmount = amountOut;
        
        // محاسبه به صورت معکوس
        for (int i = int(tokens.length) - 2; i >= 0; i--) {
            address tokenIn = tokens[uint(i)];
            address tokenOut = tokens[uint(i) + 1];
            uint24 fee = fees[uint(i)];
            
            Quoter.QuoteResult memory quote = _getQuote(
                tokenIn,
                tokenOut,
                fee,
                currentAmount,
                false
            );
            
            currentAmount = quote.amountOut; // در exact output، این amount in است
        }
        
        amountIn = currentAmount;
    }
    
    /**
     * @dev دریافت quote
     */
    function _getQuote(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amount,
        bool exactInput
    ) internal view returns (Quoter.QuoteResult memory) {
        Quoter quoterContract = Quoter(quoter);
        
        if (exactInput) {
            return quoterContract.quoteExactInputSingle(
                Quoter.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    amountIn: amount,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            return quoterContract.quoteExactOutputSingle(
                Quoter.QuoteExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    amountOut: amount,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }
    
    /**
     * @dev دریافت آدرس pool
     */
    function _getPoolAddress(address tokenA, address tokenB, uint24 fee) internal view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB, fee));
        
        address cached = _poolCache[key];
        if (cached != address(0)) return cached;
        
        return PoolFactory(factory).getPool(tokenA, tokenB, fee);
    }
    
    /**
     * @dev انتقال توکن ورودی
     */
    function _transferTokenIn(address token, uint256 amount) internal {
        if (token == WETH9 && msg.value > 0) {
            // Handle ETH input
            if (msg.value != amount) revert SwapRouter__InvalidAmount();
            IWETH9(WETH9).deposit{value: amount}();
        } else {
            // Handle ERC20 input
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }
    
    /**
     * @dev کسر router fee
     */
    function _collectRouterFee(address token, uint256 amount) internal {
        if (routerFee > 0 && routerFeeRecipient != address(0)) {
            uint256 feeAmount = amount.mul(routerFee).div(10000);
            IERC20(token).safeTransfer(routerFeeRecipient, feeAmount);
        }
    }
    
    /**
     * @dev decode path
     */
    function _decodePath(bytes memory path)
        internal
        pure
        returns (address[] memory tokens, uint24[] memory fees)
    {
        if (path.length < 43) revert SwapRouter__InvalidPath();
        
        uint256 numPools = (path.length - 20) / 23;
        tokens = new address[](numPools + 1);
        fees = new uint24[](numPools);
        
        uint256 offset = 0;
        for (uint256 i = 0; i < numPools + 1; i++) {
            tokens[i] = address(bytes20(path[offset:offset + 20]));
            offset += 20;
            
            if (i < numPools) {
                fees[i] = uint24(bytes3(path[offset:offset + 3]));
                offset += 3;
            }
        }
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice تنظیم router fee
     */
    function setRouterFee(uint256 _routerFee) external onlyRole(OPERATOR_ROLE) {
        if (_routerFee > 100) revert SwapRouter__InvalidAmount(); // حداکثر 1%
        
        uint256 oldFee = routerFee;
        routerFee = _routerFee;
        
        emit RouterFeeUpdated(oldFee, _routerFee);
    }
    
    /**
     * @notice تنظیم router fee recipient
     */
    function setRouterFeeRecipient(address _recipient) external onlyRole(OPERATOR_ROLE) {
        address oldRecipient = routerFeeRecipient;
        routerFeeRecipient = _recipient;
        
        emit RouterFeeRecipientUpdated(oldRecipient, _recipient);
    }
    
    /**
     * @notice تنظیم default slippage
     */
    function setDefaultSlippage(uint256 _slippage) external onlyRole(OPERATOR_ROLE) {
        if (_slippage < MIN_SLIPPAGE || _slippage > MAX_SLIPPAGE) {
            revert SwapRouter__InvalidSlippage();
        }
        
        uint256 oldSlippage = defaultSlippage;
        defaultSlippage = _slippage;
        
        emit DefaultSlippageUpdated(oldSlippage, _slippage);
    }
    
    /**
     * @notice تنظیم MEV protection
     */
    function setMEVProtection(MEVProtectionConfig calldata _config) external onlyRole(OPERATOR_ROLE) {
        mevProtection = _config;
        emit MEVProtectionUpdated(_config);
    }
    
    /**
     * @notice تنظیم blacklist token
     */
    function setTokenBlacklist(address token, bool blacklisted) external onlyRole(OPERATOR_ROLE) {
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }
    
    /**
     * @notice تنظیم whitelist token
     */
    function setTokenWhitelist(address token, bool whitelisted) external onlyRole(OPERATOR_ROLE) {
        whitelistedTokens[token] = whitelisted;
        emit TokenWhitelisted(token, whitelisted);
    }
    
    /**
     * @notice تغییر وضعیت whitelist mode
     */
    function setWhitelistMode(bool _enabled) external onlyRole(OPERATOR_ROLE) {
        whitelistMode = _enabled;
        emit WhitelistModeToggled(_enabled);
    }
    
    /**
     * @notice تغییر وضعیت emergency mode
     */
    function setEmergencyMode(bool _enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeToggled(_enabled);
    }
    
    /**
     * @notice بروزرسانی quoter
     */
    function setQuoter(address _quoter) external onlyRole(OPERATOR_ROLE) {
        address oldQuoter = quoter;
        quoter = _quoter;
        emit QuoterUpdated(oldQuoter, _quoter);
    }
    
    /**
     * @notice توقف اضطراری
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice لغو توقف
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @notice دریافت آدرس factory
     */
    function getFactory() external view returns (address) {
        return factory;
    }
    
    /**
     * @notice دریافت آدرس WETH9
     */
    function getWETH9() external view returns (address) {
        return WETH9;
    }
    
    /**
     * @notice دریافت آدرس quoter
     */
    function getQuoter() external view returns (address) {
        return quoter;
    }
    
    // ==================== RECEIVE FUNCTION ====================
    
    receive() external payable {
        // Only accept ETH from WETH9
        require(msg.sender == WETH9, "SwapRouter: ETH not from WETH");
    }
}

// ==================== INTERFACES ==================== 