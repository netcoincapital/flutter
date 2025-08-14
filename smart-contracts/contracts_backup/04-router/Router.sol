// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../01-core/AccessControl.sol";
import "../03-pool/PoolFactory.sol";
import "../03-pool/LaxcePool.sol";
import "../03-pool/PoolManager.sol";
import "./PathFinder.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Interfaces.sol";

/**
 * @title Router
 * @dev Main router for executing swaps with optimal pathfinding
 * @dev Supports single-hop and multi-hop swaps with slippage protection
 */
contract Router is Pausable, LaxceAccessControl, Multicall {
    using SafeERC20 for IERC20;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;

    // =========== CONSTANTS ===========
    uint256 public constant MAX_SLIPPAGE = 5000; // 50%
    uint256 public constant MIN_SLIPPAGE = 1; // 0.01%
    uint256 public constant DEFAULT_DEADLINE = 1200; // 20 minutes
    uint256 public constant MAX_HOPS = 3;

    // =========== STRUCTS ===========
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct SwapResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 gasUsed;
        address[] pools;
    }

    // =========== STATE VARIABLES ===========
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    PoolFactory public immutable factory;
    PathFinder public immutable pathFinder;
    PoolManager public immutable poolManager;
    IWETH9 public immutable WETH9;
    
    // Slippage and deadline settings
    uint256 public defaultSlippage = 50; // 0.5%
    uint256 public defaultDeadline = DEFAULT_DEADLINE;
    
    // Fee collection
    address public feeRecipient;
    uint256 public routerFee = 0; // 0% initially
    
    // Security settings
    mapping(address => bool) public approvedTokens;
    mapping(address => bool) public blockedTokens;
    bool public tokenWhitelistEnabled = false;

    // =========== EVENTS ===========
    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );
    
    event MultiHopSwap(
        address indexed sender,
        address[] tokens,
        uint256[] amounts,
        address recipient
    );
    
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event DeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event RouterFeeUpdated(uint256 oldFee, uint256 newFee);
    event TokenApproved(address indexed token, bool approved);
    event TokenBlocked(address indexed token, bool blocked);

    // =========== ERRORS ===========
    error Router__DeadlineExpired();
    error Router__InsufficientAmountOut();
    error Router__ExcessiveAmountIn();
    error Router__InvalidPath();
    error Router__TokenNotApproved();
    error Router__TokenBlocked();
    error Router__InvalidSlippage();
    error Router__ZeroAmount();
    error Router__InvalidRecipient();
    error Router__TransferFailed();
    error Router__SwapFailed();

    // =========== MODIFIERS ===========
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert Router__DeadlineExpired();
        _;
    }

    modifier validToken(address token) {
        if (blockedTokens[token]) revert Router__TokenBlocked();
        if (tokenWhitelistEnabled && !approvedTokens[token]) {
            revert Router__TokenNotApproved();
        }
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert Router__ZeroAmount();
        _;
    }

    modifier validRecipient(address recipient) {
        if (recipient == address(0)) revert Router__InvalidRecipient();
        _;
    }

    // =========== CONSTRUCTOR ===========
    constructor(
        address _factory,
        address _pathFinder,
        address _poolManager,
        address _WETH9
    ) {
        if (_factory == address(0) || 
            _pathFinder == address(0) || 
            _poolManager == address(0) || 
            _WETH9 == address(0)) {
            revert Router__InvalidRecipient();
        }

        factory = PoolFactory(_factory);
        pathFinder = PathFinder(_pathFinder);
        poolManager = PoolManager(_poolManager);
        WETH9 = IWETH9(_WETH9);
        
        _reentrancyGuard.initialize();
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        feeRecipient = msg.sender;
    }

    // =========== EXACT INPUT SWAPS ===========

    /**
     * @dev Swaps `amountIn` of one token for as much as possible of another token
     * @param params The parameters necessary for the swap
     * @return amountOut The amount of the received token
     */
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        validToken(params.tokenIn)
        validToken(params.tokenOut)
        validAmount(params.amountIn)
        validRecipient(params.recipient)
        whenNotPaused
        returns (uint256 amountOut)
    {
        // Handle ETH input
        if (params.tokenIn == address(WETH9) && msg.value > 0) {
            if (msg.value != params.amountIn) revert Router__InvalidPath();
            WETH9.deposit{value: msg.value}();
        } else {
            IERC20(params.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                params.amountIn
            );
        }

        // Get pool for the pair
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        if (pool == address(0)) revert Router__InvalidPath();

        // Approve token to pool
        IERC20(params.tokenIn).safeApprove(pool, params.amountIn);

        // Execute swap
        amountOut = _executeSwap(
            pool,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.amountOutMinimum,
            params.recipient,
            params.sqrtPriceLimitX96,
            true
        );

        // Handle ETH output
        if (params.tokenOut == address(WETH9) && params.recipient == msg.sender) {
            WETH9.withdraw(amountOut);
            _safeTransferETH(params.recipient, amountOut);
        }

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.recipient
        );
    }

    /**
     * @dev Swaps `amountIn` of one token for as much as possible of another along the specified path
     * @param params The parameters necessary for the multi-hop swap
     * @return amountOut The amount of the received token
     */
    function exactInput(ExactInputParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        validAmount(params.amountIn)
        validRecipient(params.recipient)
        whenNotPaused
        returns (uint256 amountOut)
    {
        // Decode path
        (address[] memory tokens, uint24[] memory fees) = _decodePath(params.path);
        if (tokens.length < 2) revert Router__InvalidPath();

        // Validate tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (blockedTokens[tokens[i]]) revert Router__TokenBlocked();
            if (tokenWhitelistEnabled && !approvedTokens[tokens[i]]) {
                revert Router__TokenNotApproved();
            }
        }

        // Handle ETH input
        if (tokens[0] == address(WETH9) && msg.value > 0) {
            if (msg.value != params.amountIn) revert Router__InvalidPath();
            WETH9.deposit{value: msg.value}();
        } else {
            IERC20(tokens[0]).safeTransferFrom(
                msg.sender,
                address(this),
                params.amountIn
            );
        }

        // Execute multi-hop swap
        amountOut = _executeMultiHopSwap(
            tokens,
            fees,
            params.amountIn,
            params.amountOutMinimum,
            params.recipient,
            true
        );

        // Handle ETH output
        if (tokens[tokens.length - 1] == address(WETH9) && params.recipient == msg.sender) {
            WETH9.withdraw(amountOut);
            _safeTransferETH(params.recipient, amountOut);
        }

        // Track amounts for each hop
        uint256[] memory amounts = new uint256[](tokens.length);
        amounts[0] = params.amountIn;
        amounts[tokens.length - 1] = amountOut;

        emit MultiHopSwap(msg.sender, tokens, amounts, params.recipient);
    }

    // =========== EXACT OUTPUT SWAPS ===========

    /**
     * @dev Swaps as little as possible of one token for `amountOut` of another token
     * @param params The parameters necessary for the swap
     * @return amountIn The amount of the input token
     */
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        validToken(params.tokenIn)
        validToken(params.tokenOut)
        validAmount(params.amountOut)
        validRecipient(params.recipient)
        whenNotPaused
        returns (uint256 amountIn)
    {
        // Get pool for the pair
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        if (pool == address(0)) revert Router__InvalidPath();

        // Calculate required input amount
        (uint256 requiredAmountIn, , ) = pathFinder.getAmountIn(
            params.tokenIn,
            params.tokenOut,
            params.amountOut
        );

        if (requiredAmountIn > params.amountInMaximum) {
            revert Router__ExcessiveAmountIn();
        }

        // Handle ETH input
        if (params.tokenIn == address(WETH9) && msg.value > 0) {
            if (msg.value < requiredAmountIn) revert Router__ExcessiveAmountIn();
            WETH9.deposit{value: requiredAmountIn}();
            
            // Refund excess ETH
            if (msg.value > requiredAmountIn) {
                _safeTransferETH(msg.sender, msg.value - requiredAmountIn);
            }
        } else {
            IERC20(params.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                requiredAmountIn
            );
        }

        // Approve token to pool
        IERC20(params.tokenIn).safeApprove(pool, requiredAmountIn);

        // Execute swap
        uint256 actualAmountOut = _executeSwap(
            pool,
            params.tokenIn,
            params.tokenOut,
            requiredAmountIn,
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            false
        );

        if (actualAmountOut < params.amountOut) {
            revert Router__InsufficientAmountOut();
        }

        // Handle ETH output
        if (params.tokenOut == address(WETH9) && params.recipient == msg.sender) {
            WETH9.withdraw(actualAmountOut);
            _safeTransferETH(params.recipient, actualAmountOut);
        }

        amountIn = requiredAmountIn;

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            amountIn,
            actualAmountOut,
            params.recipient
        );
    }

    /**
     * @dev Swaps as little as possible of one token for `amountOut` of another along the specified path
     * @param params The parameters necessary for the multi-hop swap
     * @return amountIn The amount of the input token
     */
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        nonReentrant
        checkDeadline(params.deadline)
        validAmount(params.amountOut)
        validRecipient(params.recipient)
        whenNotPaused
        returns (uint256 amountIn)
    {
        // Decode path (reversed for exact output)
        (address[] memory tokens, uint24[] memory fees) = _decodePath(params.path);
        if (tokens.length < 2) revert Router__InvalidPath();

        // Validate tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            if (blockedTokens[tokens[i]]) revert Router__TokenBlocked();
            if (tokenWhitelistEnabled && !approvedTokens[tokens[i]]) {
                revert Router__TokenNotApproved();
            }
        }

        // Calculate required input amount for the full path
        (uint256 requiredAmountIn, , ) = pathFinder.getAmountIn(
            tokens[0],
            tokens[tokens.length - 1],
            params.amountOut
        );

        if (requiredAmountIn > params.amountInMaximum) {
            revert Router__ExcessiveAmountIn();
        }

        // Handle ETH input
        if (tokens[0] == address(WETH9) && msg.value > 0) {
            if (msg.value < requiredAmountIn) revert Router__ExcessiveAmountIn();
            WETH9.deposit{value: requiredAmountIn}();
            
            // Refund excess ETH
            if (msg.value > requiredAmountIn) {
                _safeTransferETH(msg.sender, msg.value - requiredAmountIn);
            }
        } else {
            IERC20(tokens[0]).safeTransferFrom(
                msg.sender,
                address(this),
                requiredAmountIn
            );
        }

        // Execute multi-hop swap
        uint256 actualAmountOut = _executeMultiHopSwap(
            tokens,
            fees,
            requiredAmountIn,
            params.amountOut,
            params.recipient,
            false
        );

        if (actualAmountOut < params.amountOut) {
            revert Router__InsufficientAmountOut();
        }

        // Handle ETH output
        if (tokens[tokens.length - 1] == address(WETH9) && params.recipient == msg.sender) {
            WETH9.withdraw(actualAmountOut);
            _safeTransferETH(params.recipient, actualAmountOut);
        }

        amountIn = requiredAmountIn;

        // Track amounts for each hop
        uint256[] memory amounts = new uint256[](tokens.length);
        amounts[0] = amountIn;
        amounts[tokens.length - 1] = actualAmountOut;

        emit MultiHopSwap(msg.sender, tokens, amounts, params.recipient);
    }

    // =========== QUOTE FUNCTIONS ===========

    /**
     * @dev Get quote for exact input swap
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external view returns (uint256 amountOut) {
        (amountOut, , ) = pathFinder.getAmountOut(tokenIn, tokenOut, amountIn);
    }

    /**
     * @dev Get quote for exact input multi-hop swap
     */
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        (address[] memory tokens, ) = _decodePath(path);
        if (tokens.length < 2) revert Router__InvalidPath();

        (amountOut, , ) = pathFinder.getAmountOut(
            tokens[0],
            tokens[tokens.length - 1],
            amountIn
        );
    }

    /**
     * @dev Get quote for exact output swap
     */
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external view returns (uint256 amountIn) {
        (amountIn, , ) = pathFinder.getAmountIn(tokenIn, tokenOut, amountOut);
    }

    /**
     * @dev Get quote for exact output multi-hop swap
     */
    function quoteExactOutput(bytes memory path, uint256 amountOut)
        external
        view
        returns (uint256 amountIn)
    {
        (address[] memory tokens, ) = _decodePath(path);
        if (tokens.length < 2) revert Router__InvalidPath();

        (amountIn, , ) = pathFinder.getAmountIn(
            tokens[0],
            tokens[tokens.length - 1],
            amountOut
        );
    }

    // =========== OPTIMAL PATH FUNCTIONS ===========

    /**
     * @dev Find optimal path and quote
     */
    function findOptimalPathAndQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        PathFinder.SwapPath memory path,
        uint256 amountOut,
        uint256 priceImpact
    ) {
        path = pathFinder.findOptimalPath(tokenIn, tokenOut, amountIn, defaultSlippage);
        amountOut = path.expectedAmountOut;
        priceImpact = path.priceImpact;
    }

    /**
     * @dev Find multiple paths for comparison
     */
    function findMultiplePathsAndQuotes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 pathCount
    ) external view returns (PathFinder.SwapPath[] memory paths) {
        return pathFinder.findMultiplePaths(tokenIn, tokenOut, amountIn, pathCount);
    }

    // =========== INTERNAL FUNCTIONS ===========

    /**
     * @dev Execute single hop swap
     */
    function _executeSwap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient,
        uint160 sqrtPriceLimitX96,
        bool exactInput
    ) internal returns (uint256 amountOut) {
        bool zeroForOne = tokenIn < tokenOut;
        
        // Calculate swap parameters
        int256 amountSpecified = exactInput ? 
            int256(amountIn) : 
            -int256(amountOutMinimum);

        try LaxcePool(pool).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96 == 0 ?
                (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1) :
                sqrtPriceLimitX96,
            abi.encode(SwapCallbackData({path: abi.encodePacked(tokenIn, uint24(0), tokenOut), payer: msg.sender}))
        ) returns (int256 amount0, int256 amount1) {
            amountOut = uint256(-(zeroForOne ? amount1 : amount0));
            
            if (exactInput && amountOut < amountOutMinimum) {
                revert Router__InsufficientAmountOut();
            }
        } catch {
            revert Router__SwapFailed();
        }

        // Collect router fee if applicable
        if (routerFee > 0 && feeRecipient != address(0)) {
            uint256 fee = (amountOut * routerFee) / 10000;
            if (fee > 0) {
                IERC20(tokenOut).safeTransfer(feeRecipient, fee);
                amountOut = amountOut - fee;
            }
        }
    }

    /**
     * @dev Execute multi-hop swap
     */
    function _executeMultiHopSwap(
        address[] memory tokens,
        uint24[] memory fees,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient,
        bool exactInput
    ) internal returns (uint256 amountOut) {
        uint256 currentAmount = amountIn;
        address currentRecipient;

        for (uint256 i = 0; i < tokens.length - 1; i++) {
            // Determine recipient for this hop
            currentRecipient = (i == tokens.length - 2) ? recipient : address(this);
            
            // Get pool for this hop
            address pool = factory.getPool(tokens[i], tokens[i + 1], fees[i]);
            if (pool == address(0)) revert Router__InvalidPath();
            
            // Approve token for this hop
            IERC20(tokens[i]).safeApprove(pool, currentAmount);
            
            // Execute swap for this hop
            currentAmount = _executeSwap(
                pool,
                tokens[i],
                tokens[i + 1],
                currentAmount,
                0, // No minimum for intermediate hops
                currentRecipient,
                0, // No price limit for intermediate hops
                true
            );
        }

        amountOut = currentAmount;

        if (exactInput && amountOut < amountOutMinimum) {
            revert Router__InsufficientAmountOut();
        }
    }

    /**
     * @dev Decode swap path
     */
    function _decodePath(bytes memory path) 
        internal 
        pure 
        returns (address[] memory tokens, uint24[] memory fees) 
    {
        uint256 numPools = (path.length - 20) / 23; // 20 bytes for address, 3 bytes for fee
        tokens = new address[](numPools + 1);
        fees = new uint24[](numPools);

        uint256 offset = 0;
        for (uint256 i = 0; i <= numPools; i++) {
            tokens[i] = address(bytes20(path[offset:offset + 20]));
            offset += 20;
            
            if (i < numPools) {
                fees[i] = uint24(bytes3(path[offset:offset + 3]));
                offset += 3;
            }
        }
    }

    /**
     * @dev Safe ETH transfer
     */
    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert Router__TransferFailed();
    }

    // =========== ADMIN FUNCTIONS ===========

    /**
     * @dev Set slippage tolerance
     */
    function setDefaultSlippage(uint256 _slippage) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        if (_slippage < MIN_SLIPPAGE || _slippage > MAX_SLIPPAGE) {
            revert Router__InvalidSlippage();
        }
        
        uint256 oldSlippage = defaultSlippage;
        defaultSlippage = _slippage;
        
        emit SlippageUpdated(oldSlippage, _slippage);
    }

    /**
     * @dev Set default deadline
     */
    function setDefaultDeadline(uint256 _deadline) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        uint256 oldDeadline = defaultDeadline;
        defaultDeadline = _deadline;
        
        emit DeadlineUpdated(oldDeadline, _deadline);
    }

    /**
     * @dev Set fee recipient
     */
    function setFeeRecipient(address _feeRecipient) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    /**
     * @dev Set router fee (in basis points)
     */
    function setRouterFee(uint256 _fee) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        if (_fee > 100) revert Router__InvalidSlippage(); // Max 1%
        
        uint256 oldFee = routerFee;
        routerFee = _fee;
        
        emit RouterFeeUpdated(oldFee, _fee);
    }

    /**
     * @dev Approve/unapprove token
     */
    function setTokenApproval(address token, bool approved) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        approvedTokens[token] = approved;
        emit TokenApproved(token, approved);
    }

    /**
     * @dev Block/unblock token
     */
    function setTokenBlocked(address token, bool blocked) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        blockedTokens[token] = blocked;
        emit TokenBlocked(token, blocked);
    }

    /**
     * @dev Enable/disable token whitelist
     */
    function setTokenWhitelistEnabled(bool enabled) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        tokenWhitelistEnabled = enabled;
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency token rescue
     */
    function rescueToken(address token, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Emergency ETH rescue
     */
    function rescueETH(uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        _safeTransferETH(msg.sender, amount);
    }

    // =========== CALLBACK FUNCTIONS ===========

    /**
     * @dev Callback for LaxcePool swaps
     */
    function laxceSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        SwapCallbackData memory decoded = abi.decode(data, (SwapCallbackData));
        (address tokenIn, address tokenOut) = _decodeFirstPool(decoded.path);

        // Verify caller is a valid pool
        address pool = factory.getPool(tokenIn, tokenOut, 0); // Fee will be included in path
        if (msg.sender != pool) revert Router__SwapFailed();

        // Pay the amount required for the swap
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        address tokenToPay = amount0Delta > 0 ? tokenIn : tokenOut;
        
        IERC20(tokenToPay).safeTransfer(msg.sender, amountToPay);
    }

    /**
     * @dev Decode first pool from path
     */
    function _decodeFirstPool(bytes memory path)
        internal
        pure
        returns (address tokenA, address tokenB)
    {
        tokenA = address(bytes20(path[0:20]));
        tokenB = address(bytes20(path[23:43]));
    }

    // =========== RECEIVE FUNCTION ===========
    
    /**
     * @dev Receive ETH
     */
    receive() external payable {
        if (msg.sender != address(WETH9)) revert Router__TransferFailed();
    }

    // =========== VIEW FUNCTIONS ===========

    /**
     * @dev Get router configuration
     */
    function getConfiguration() 
        external 
        view 
        returns (
            uint256 _defaultSlippage,
            uint256 _defaultDeadline,
            address _feeRecipient,
            uint256 _routerFee,
            bool _tokenWhitelistEnabled
        ) 
    {
        return (
            defaultSlippage,
            defaultDeadline,
            feeRecipient,
            routerFee,
            tokenWhitelistEnabled
        );
    }

    /**
     * @dev Check if token is usable
     */
    function isTokenUsable(address token) external view returns (bool) {
        if (blockedTokens[token]) return false;
        if (tokenWhitelistEnabled && !approvedTokens[token]) return false;
        return true;
    }
} 