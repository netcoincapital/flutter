// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../01-core/AccessControl.sol";
import "../03-pool/PoolFactory.sol";
import "../03-pool/LaxcePool.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/TickMath.sol";
import "../libraries/FullMath.sol";
import "../libraries/SqrtPriceMath.sol";
import "../libraries/SwapMath.sol";

/**
 * @title Quoter
 * @dev کانترکت محاسبه قیمت آف‌چین برای مبادلات بدون اجرای واقعی
 * @notice این کانترکت برای محاسبه دقیق قیمت‌ها و مقادیر مبادله استفاده می‌شود
 */
contract Quoter is Pausable, LaxceAccessControl {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TickMath for int24;
    using SwapMath for SwapMath.SwapState;
    using ReentrancyGuard for ReentrancyGuard.ReentrancyData;
    
    // ==================== CONSTANTS ====================
    
    /// @dev حداکثر تعداد hops برای مسیریابی
    uint256 public constant MAX_HOPS = 3;
    
    /// @dev حداکثر pools برای جستجو
    uint256 public constant MAX_POOLS_TO_SEARCH = 20;
    
    /// @dev حداکثر slippage مجاز (50%)
    uint256 public constant MAX_SLIPPAGE = 5000;
    
    // ==================== STRUCTS ====================
    
    /// @dev پارامترهای quote برای exact input
    struct QuoteExactInputSingleParams {
        address tokenIn;            // توکن ورودی
        address tokenOut;           // توکن خروجی
        uint24 fee;                 // کارمزد pool
        uint256 amountIn;           // مقدار ورودی
        uint160 sqrtPriceLimitX96;  // حد قیمت
    }
    
    /// @dev پارامترهای quote برای exact output
    struct QuoteExactOutputSingleParams {
        address tokenIn;            // توکن ورودی
        address tokenOut;           // توکن خروجی
        uint24 fee;                 // کارمزد pool
        uint256 amountOut;          // مقدار خروجی
        uint160 sqrtPriceLimitX96;  // حد قیمت
    }
    
    /// @dev پارامترهای quote برای exact input multi-hop
    struct QuoteExactInputParams {
        bytes path;                 // مسیر encoded
        uint256 amountIn;           // مقدار ورودی
    }
    
    /// @dev پارامترهای quote برای exact output multi-hop
    struct QuoteExactOutputParams {
        bytes path;                 // مسیر encoded
        uint256 amountOut;          // مقدار خروجی
    }
    
    /// @dev نتیجه quote
    struct QuoteResult {
        uint256 amountOut;          // مقدار خروجی
        uint160 sqrtPriceX96After;  // قیمت بعد از مبادله
        uint32 initializedTicksCrossed; // تعداد tick های عبور شده
        uint256 gasEstimate;        // تخمین گاز
        uint256 priceImpact;        // تاثیر قیمت (basis points)
        uint256 feeAmount;          // مقدار کارمزد
    }
    
    /// @dev اطلاعات pool برای محاسبات
    struct PoolInfo {
        address pool;               // آدرس pool
        uint256 liquidity;          // نقدینگی فعلی
        uint160 sqrtPriceX96;       // قیمت فعلی
        int24 tick;                 // tick فعلی
        uint24 fee;                 // کارمزد
        bool initialized;           // آیا initialize شده
    }
    
    /// @dev وضعیت محاسبه swap
    struct SwapCalculation {
        uint256 amountCalculated;   // مقدار محاسبه شده
        uint160 sqrtPriceX96;       // قیمت جدید
        int24 tick;                 // tick جدید
        uint256 feeAmount;          // کارمزد
        uint256 gasUsed;            // گاز استفاده شده
    }
    
    // ==================== STATE VARIABLES ====================
    
    /// @dev reentrancy guard instance
    ReentrancyGuard.ReentrancyData private _reentrancyGuard;
    
    /// @dev آدرس PoolFactory
    address public immutable factory;
    
    /// @dev cache pool addresses برای بهینه‌سازی
    mapping(bytes32 => address) private _poolCache;
    
    /// @dev pool info cache
    mapping(address => PoolInfo) private _poolInfoCache;
    
    /// @dev cache timeout (5 minutes)
    uint256 public constant CACHE_TIMEOUT = 300;
    
    /// @dev last cache update time
    mapping(address => uint256) private _lastCacheUpdate;
    
    /// @dev gas estimates برای عملیات مختلف
    mapping(string => uint256) public gasEstimates;
    
    /// @dev maximum price impact allowed (default 10%)
    uint256 public maxPriceImpact = 1000; // basis points
    
    /// @dev minimum liquidity required for quotes
    uint256 public minLiquidity = 1000; // wei
    
    // ==================== EVENTS ====================
    
    event QuoteCalculated(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 priceImpact
    );
    
    event PoolCached(address indexed pool, uint256 timestamp);
    event CacheCleared(address indexed pool);
    event GasEstimateUpdated(string operation, uint256 gasAmount);
    event MaxPriceImpactUpdated(uint256 oldValue, uint256 newValue);
    event MinLiquidityUpdated(uint256 oldValue, uint256 newValue);
    
    // ==================== ERRORS ====================
    
    error Quoter__InvalidPath();
    error Quoter__InsufficientLiquidity();
    error Quoter__ExcessivePriceImpact();
    error Quoter__InvalidPool();
    error Quoter__InvalidAmount();
    error Quoter__PathTooLong();
    error Quoter__InvalidTokens();
    error Quoter__PoolNotFound();
    error Quoter__InvalidFee();
    error Quoter__QuoteReverted();
    
    // ==================== MODIFIERS ====================
    
    modifier nonReentrant() {
        _reentrancyGuard.enter();
        _;
        _reentrancyGuard.exit();
    }
    
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert Quoter__InvalidAmount();
        _;
    }
    
    modifier validTokens(address tokenA, address tokenB) {
        if (tokenA == address(0) || tokenB == address(0) || tokenA == tokenB) {
            revert Quoter__InvalidTokens();
        }
        _;
    }
    
    // ==================== CONSTRUCTOR ====================
    
    constructor(address _factory) {
        factory = _factory;
        _reentrancyGuard.initialize();
        
        // گنت نقش‌های پیش‌فرض
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        // تنظیم تخمین‌های گاز پیش‌فرض
        _setDefaultGasEstimates();
    }
    
    // ==================== QUOTE FUNCTIONS ====================
    
    /**
     * @notice محاسبه quote برای exact input single hop
     * @param params پارامترهای quote
     * @return result نتیجه محاسبه شده
     */
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        view
        nonReentrant
        validAmount(params.amountIn)
        validTokens(params.tokenIn, params.tokenOut)
        returns (QuoteResult memory result)
    {
        // پیدا کردن pool
        address poolAddress = _getPool(params.tokenIn, params.tokenOut, params.fee);
        if (poolAddress == address(0)) revert Quoter__PoolNotFound();
        
        // محاسبه quote
        return _calculateSingleSwap(
            poolAddress,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            true, // exactInput
            params.sqrtPriceLimitX96
        );
    }
    
    /**
     * @notice محاسبه quote برای exact output single hop
     * @param params پارامترهای quote
     * @return result نتیجه محاسبه شده
     */
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        view
        nonReentrant
        validAmount(params.amountOut)
        validTokens(params.tokenIn, params.tokenOut)
        returns (QuoteResult memory result)
    {
        // پیدا کردن pool
        address poolAddress = _getPool(params.tokenIn, params.tokenOut, params.fee);
        if (poolAddress == address(0)) revert Quoter__PoolNotFound();
        
        // محاسبه quote
        return _calculateSingleSwap(
            poolAddress,
            params.tokenIn,
            params.tokenOut,
            params.amountOut,
            false, // exactOutput
            params.sqrtPriceLimitX96
        );
    }
    
    /**
     * @notice محاسبه quote برای exact input multi-hop
     * @param params پارامترهای quote
     * @return result نتیجه محاسبه شده
     */
    function quoteExactInput(QuoteExactInputParams memory params)
        external
        view
        nonReentrant
        validAmount(params.amountIn)
        returns (QuoteResult memory result)
    {
        return _calculateMultiHopSwap(params.path, params.amountIn, true);
    }
    
    /**
     * @notice محاسبه quote برای exact output multi-hop
     * @param params پارامترهای quote
     * @return result نتیجه محاسبه شده
     */
    function quoteExactOutput(QuoteExactOutputParams memory params)
        external
        view
        nonReentrant
        validAmount(params.amountOut)
        returns (QuoteResult memory result)
    {
        return _calculateMultiHopSwap(params.path, params.amountOut, false);
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    /**
     * @dev محاسبه single hop swap
     */
    function _calculateSingleSwap(
        address poolAddress,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactInput,
        uint160 sqrtPriceLimitX96
    ) internal view returns (QuoteResult memory result) {
        // دریافت اطلاعات pool
        PoolInfo memory poolInfo = _getPoolInfo(poolAddress);
        if (!poolInfo.initialized) revert Quoter__InvalidPool();
        
        // بررسی نقدینگی کافی
        if (poolInfo.liquidity < minLiquidity) revert Quoter__InsufficientLiquidity();
        
        // تعیین جهت swap
        bool zeroForOne = tokenIn < tokenOut;
        
        // محاسبه swap
        SwapCalculation memory calc = SwapMath.calculateSwap(
            SwapMath.SwapParams({
                sqrtPriceCurrentX96: poolInfo.sqrtPriceX96,
                sqrtPriceTargetX96: sqrtPriceLimitX96,
                liquidity: poolInfo.liquidity,
                amount: exactInput ? int256(amount) : -int256(amount),
                fee: poolInfo.fee,
                zeroForOne: zeroForOne
            })
        );
        
        // محاسبه price impact
        uint256 priceImpact = _calculatePriceImpact(
            poolInfo.sqrtPriceX96,
            calc.sqrtPriceX96
        );
        
        // بررسی price impact
        if (priceImpact > maxPriceImpact) revert Quoter__ExcessivePriceImpact();
        
        result = QuoteResult({
            amountOut: calc.amountCalculated,
            sqrtPriceX96After: calc.sqrtPriceX96,
            initializedTicksCrossed: 0, // محاسبه می‌شود در implementation کامل
            gasEstimate: calc.gasUsed.add(gasEstimates["singleSwap"]),
            priceImpact: priceImpact,
            feeAmount: calc.feeAmount
        });
        
        emit QuoteCalculated(tokenIn, tokenOut, amount, result.amountOut, priceImpact);
    }
    
    /**
     * @dev محاسبه multi-hop swap
     */
    function _calculateMultiHopSwap(
        bytes memory path,
        uint256 amount,
        bool exactInput
    ) internal view returns (QuoteResult memory result) {
        // decode path
        (address[] memory tokens, uint24[] memory fees) = _decodePath(path);
        if (tokens.length > MAX_HOPS + 1) revert Quoter__PathTooLong();
        
        uint256 currentAmount = amount;
        uint256 totalGas = gasEstimates["multiSwapBase"];
        uint256 totalFees = 0;
        uint256 totalPriceImpact = 0;
        uint160 finalPrice = 0;
        
        // انجام محاسبه برای هر hop
        for (uint256 i = 0; i < tokens.length - 1; i++) {
            address tokenIn = exactInput ? tokens[i] : tokens[tokens.length - 2 - i];
            address tokenOut = exactInput ? tokens[i + 1] : tokens[tokens.length - 1 - i];
            uint24 fee = exactInput ? fees[i] : fees[fees.length - 1 - i];
            
            address poolAddress = _getPool(tokenIn, tokenOut, fee);
            if (poolAddress == address(0)) revert Quoter__PoolNotFound();
            
            QuoteResult memory hopResult = _calculateSingleSwap(
                poolAddress,
                tokenIn,
                tokenOut,
                currentAmount,
                exactInput,
                0 // no limit for intermediate hops
            );
            
            currentAmount = hopResult.amountOut;
            totalGas = totalGas.add(hopResult.gasEstimate);
            totalFees = totalFees.add(hopResult.feeAmount);
            totalPriceImpact = totalPriceImpact.add(hopResult.priceImpact);
            finalPrice = hopResult.sqrtPriceX96After;
        }
        
        result = QuoteResult({
            amountOut: currentAmount,
            sqrtPriceX96After: finalPrice,
            initializedTicksCrossed: 0,
            gasEstimate: totalGas,
            priceImpact: totalPriceImpact,
            feeAmount: totalFees
        });
    }
    
    /**
     * @dev دریافت آدرس pool
     */
    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB, fee));
        
        // بررسی cache
        address cached = _poolCache[key];
        if (cached != address(0)) return cached;
        
        // دریافت از factory
        return PoolFactory(factory).getPool(tokenA, tokenB, fee);
    }
    
    /**
     * @dev دریافت اطلاعات pool
     */
    function _getPoolInfo(address poolAddress) internal view returns (PoolInfo memory info) {
        // بررسی cache
        if (_lastCacheUpdate[poolAddress].add(CACHE_TIMEOUT) > block.timestamp) {
            return _poolInfoCache[poolAddress];
        }
        
        // دریافت از pool
        LaxcePool pool = LaxcePool(poolAddress);
        
        try pool.slot0() returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool unlocked
        ) {
            info = PoolInfo({
                pool: poolAddress,
                liquidity: pool.liquidity(),
                sqrtPriceX96: sqrtPriceX96,
                tick: tick,
                fee: pool.fee(),
                initialized: unlocked
            });
        } catch {
            revert Quoter__InvalidPool();
        }
    }
    
    /**
     * @dev محاسبه price impact
     */
    function _calculatePriceImpact(
        uint160 priceBefore,
        uint160 priceAfter
    ) internal pure returns (uint256) {
        if (priceBefore == 0) return 0;
        
        uint256 difference = priceBefore > priceAfter
            ? priceBefore - priceAfter
            : priceAfter - priceBefore;
            
        return difference.mul(10000).div(priceBefore);
    }
    
    /**
     * @dev decode کردن path
     */
    function _decodePath(bytes memory path)
        internal
        pure
        returns (address[] memory tokens, uint24[] memory fees)
    {
        if (path.length < 43) revert Quoter__InvalidPath(); // حداقل 20+3+20
        
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
    
    /**
     * @dev تنظیم تخمین‌های گاز پیش‌فرض
     */
    function _setDefaultGasEstimates() internal {
        gasEstimates["singleSwap"] = 80000;
        gasEstimates["multiSwapBase"] = 100000;
        gasEstimates["multiSwapPerHop"] = 50000;
        gasEstimates["quote"] = 30000;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @notice تنظیم حداکثر price impact
     * @param _maxPriceImpact حداکثر price impact (basis points)
     */
    function setMaxPriceImpact(uint256 _maxPriceImpact) external onlyRole(OPERATOR_ROLE) {
        if (_maxPriceImpact > MAX_SLIPPAGE) revert Quoter__ExcessivePriceImpact();
        
        uint256 oldValue = maxPriceImpact;
        maxPriceImpact = _maxPriceImpact;
        
        emit MaxPriceImpactUpdated(oldValue, _maxPriceImpact);
    }
    
    /**
     * @notice تنظیم حداقل نقدینگی
     * @param _minLiquidity حداقل نقدینگی مورد نیاز
     */
    function setMinLiquidity(uint256 _minLiquidity) external onlyRole(OPERATOR_ROLE) {
        uint256 oldValue = minLiquidity;
        minLiquidity = _minLiquidity;
        
        emit MinLiquidityUpdated(oldValue, _minLiquidity);
    }
    
    /**
     * @notice بروزرسانی تخمین گاز
     * @param operation نوع عملیات
     * @param gasAmount مقدار گاز
     */
    function updateGasEstimate(string calldata operation, uint256 gasAmount)
        external
        onlyRole(OPERATOR_ROLE)
    {
        gasEstimates[operation] = gasAmount;
        emit GasEstimateUpdated(operation, gasAmount);
    }
    
    /**
     * @notice پاک کردن cache pool
     * @param poolAddress آدرس pool
     */
    function clearPoolCache(address poolAddress) external onlyRole(OPERATOR_ROLE) {
        delete _poolInfoCache[poolAddress];
        delete _lastCacheUpdate[poolAddress];
        emit CacheCleared(poolAddress);
    }
    
    /**
     * @notice پاک کردن کل cache
     */
    function clearAllCache() external onlyRole(OPERATOR_ROLE) {
        // این function در implementation واقعی باید تمام cache ها را پاک کند
        // برای سادگی فقط event emit می‌کنیم
        emit CacheCleared(address(0));
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
     * @notice دریافت اطلاعات pool
     * @param tokenA توکن اول
     * @param tokenB توکن دوم  
     * @param fee کارمزد
     * @return info اطلاعات pool
     */
    function getPoolInfo(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (PoolInfo memory info)
    {
        address poolAddress = _getPool(tokenA, tokenB, fee);
        if (poolAddress == address(0)) revert Quoter__PoolNotFound();
        
        return _getPoolInfo(poolAddress);
    }
    
    /**
     * @notice بررسی وجود pool
     * @param tokenA توکن اول
     * @param tokenB توکن دوم
     * @param fee کارمزد
     * @return exists آیا pool وجود دارد
     */
    function poolExists(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (bool exists)
    {
        return _getPool(tokenA, tokenB, fee) != address(0);
    }
    
    /**
     * @notice دریافت آدرس factory
     */
    function getFactory() external view returns (address) {
        return factory;
    }
} 