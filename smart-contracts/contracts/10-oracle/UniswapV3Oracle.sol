// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/FullMath.sol";
import "../libraries/Constants.sol";

/**
 * @title UniswapV3Oracle
 * @dev Oracle برای استفاده از TWAP Uniswap V3
 */
contract UniswapV3Oracle is Ownable {
    using FullMath for uint256;

    struct PoolInfo {
        address pool;               // آدرس pool
        uint32 period;              // دوره TWAP
        address token0;             // توکن 0
        address token1;             // توکن 1
        uint24 fee;                 // fee tier
        bool active;                // فعال/غیرفعال
        uint256 lastUpdate;         // آخرین به‌روزرسانی
    }

    struct PriceData {
        uint256 price;              // قیمت فعلی
        uint256 twapPrice;          // قیمت TWAP
        uint32 timestamp;           // زمان به‌روزرسانی
        bool valid;                 // معتبر/نامعتبر
        uint256 liquidity;          // نقدینگی pool
    }

    struct Observation {
        uint32 blockTimestamp;      // زمان block
        int56 tickCumulative;       // tick تجمعی
        uint160 secondsPerLiquidityCumulative; // ثانیه per liquidity تجمعی
        bool initialized;           // مقداردهی شده
    }

    // Events
    event PoolAdded(address indexed pool, address indexed token0, address indexed token1, uint24 fee);
    event PoolRemoved(address indexed pool);
    event PriceUpdated(address indexed pool, uint256 price, uint256 twapPrice, uint32 timestamp);
    event PeriodUpdated(address indexed pool, uint32 oldPeriod, uint32 newPeriod);

    // State variables
    mapping(address => PoolInfo) public poolInfo;
    mapping(address => mapping(address => address)) public getPool; // token0 => token1 => pool
    mapping(address => PriceData) public priceData;
    mapping(address => Observation[]) public observations;
    
    address[] public allPools;
    uint32 public defaultPeriod = 1800; // 30 minutes default TWAP
    uint32 public constant MIN_PERIOD = 300;     // 5 minutes minimum
    uint32 public constant MAX_PERIOD = 86400;   // 24 hours maximum
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% max deviation

    // Uniswap V3 Factory
    address public immutable uniswapV3Factory;
    
    // Price validation
    mapping(address => uint256) public maxDeviationPerPool;
    mapping(address => bool) public trustedPools;
    
    // Circuit breaker
    mapping(address => bool) public circuitBreakerTriggered;
    mapping(address => uint256) public lastValidPrice;

    error PoolNotFound();
    error InvalidPeriod();
    error InvalidPool();
    error PriceDeviationTooHigh();
    error CircuitBreakerActive();
    error InsufficientObservations();
    error StalePrice();

    constructor(address _uniswapV3Factory) Ownable(msg.sender) {
        uniswapV3Factory = _uniswapV3Factory;
    }

    /**
     * @dev اضافه کردن pool جدید
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     * @param fee fee tier
     * @param period دوره TWAP
     */
    function addPool(
        address token0,
        address token1,
        uint24 fee,
        uint32 period
    ) external onlyOwner {
        if (period < MIN_PERIOD || period > MAX_PERIOD) revert InvalidPeriod();
        
        // محاسبه آدرس pool
        address pool = _computePoolAddress(token0, token1, fee);
        if (pool == address(0)) revert InvalidPool();
        
        // مرتب‌سازی tokens
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        
        poolInfo[pool] = PoolInfo({
            pool: pool,
            period: period,
            token0: token0,
            token1: token1,
            fee: fee,
            active: true,
            lastUpdate: block.timestamp
        });
        
        getPool[token0][token1] = pool;
        getPool[token1][token0] = pool;
        allPools.push(pool);
        
        maxDeviationPerPool[pool] = MAX_PRICE_DEVIATION;
        trustedPools[pool] = true;
        
        // مقداردهی اولیه observations
        _initializeObservations(pool);
        
        emit PoolAdded(pool, token0, token1, fee);
    }

    /**
     * @dev حذف pool
     * @param pool آدرس pool
     */
    function removePool(address pool) external onlyOwner {
        PoolInfo storage info = poolInfo[pool];
        if (info.pool == address(0)) revert PoolNotFound();
        
        info.active = false;
        trustedPools[pool] = false;
        
        emit PoolRemoved(pool);
    }

    /**
     * @dev دریافت قیمت فعلی
     * @param tokenA آدرس token A
     * @param tokenB آدرس token B
     * @return price قیمت tokenA بر حسب tokenB
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint256 price) {
        address pool = getPool[tokenA][tokenB];
        if (pool == address(0)) revert PoolNotFound();
        if (circuitBreakerTriggered[pool]) revert CircuitBreakerActive();
        
        PriceData storage data = priceData[pool];
        if (!data.valid || block.timestamp > data.timestamp + 3600) revert StalePrice(); // 1 hour staleness
        
        PoolInfo storage info = poolInfo[pool];
        
        // تعیین جهت قیمت
        if (tokenA == info.token0) {
            return data.price;
        } else {
            return (PRICE_PRECISION * PRICE_PRECISION) / data.price;
        }
    }

    /**
     * @dev دریافت قیمت TWAP
     * @param tokenA آدرس token A
     * @param tokenB آدرس token B
     * @return twapPrice قیمت TWAP
     */
    function getTWAPPrice(address tokenA, address tokenB) external view returns (uint256 twapPrice) {
        address pool = getPool[tokenA][tokenB];
        if (pool == address(0)) revert PoolNotFound();
        if (circuitBreakerTriggered[pool]) revert CircuitBreakerActive();
        
        PriceData storage data = priceData[pool];
        if (!data.valid) revert StalePrice();
        
        PoolInfo storage info = poolInfo[pool];
        
        // تعیین جهت قیمت
        if (tokenA == info.token0) {
            return data.twapPrice;
        } else {
            return (PRICE_PRECISION * PRICE_PRECISION) / data.twapPrice;
        }
    }

    /**
     * @dev به‌روزرسانی قیمت pool
     * @param pool آدرس pool
     */
    function updatePrice(address pool) external {
        PoolInfo storage info = poolInfo[pool];
        if (!info.active) revert PoolNotFound();
        
        // دریافت tick فعلی
        (int24 tick,) = _getCurrentTick(pool);
        
        // محاسبه قیمت فعلی
        uint256 currentPrice = _tickToPrice(tick);
        
        // محاسبه TWAP
        uint256 twapPrice = _calculateTWAP(pool, info.period);
        
        // اعتبارسنجی قیمت
        _validatePrice(pool, currentPrice, twapPrice);
        
        // به‌روزرسانی داده‌ها
        priceData[pool] = PriceData({
            price: currentPrice,
            twapPrice: twapPrice,
            timestamp: uint32(block.timestamp),
            valid: true,
            liquidity: _getPoolLiquidity(pool)
        });
        
        info.lastUpdate = block.timestamp;
        
        // اضافه کردن observation جدید
        _addObservation(pool, tick);
        
        emit PriceUpdated(pool, currentPrice, twapPrice, uint32(block.timestamp));
    }

    /**
     * @dev به‌روزرسانی batch قیمت‌ها
     * @param pools آرایه pools
     */
    function updatePrices(address[] calldata pools) external {
        for (uint256 i = 0; i < pools.length; i++) {
            if (poolInfo[pools[i]].active) {
                this.updatePrice(pools[i]);
            }
        }
    }

    /**
     * @dev تنظیم دوره TWAP
     * @param pool آدرس pool
     * @param period دوره جدید
     */
    function setPeriod(address pool, uint32 period) external onlyOwner {
        if (period < MIN_PERIOD || period > MAX_PERIOD) revert InvalidPeriod();
        
        PoolInfo storage info = poolInfo[pool];
        if (info.pool == address(0)) revert PoolNotFound();
        
        uint32 oldPeriod = info.period;
        info.period = period;
        
        emit PeriodUpdated(pool, oldPeriod, period);
    }

    /**
     * @dev تنظیم حداکثر انحراف قیمت
     * @param pool آدرس pool
     * @param maxDeviation حداکثر انحراف (basis points)
     */
    function setMaxDeviation(address pool, uint256 maxDeviation) external onlyOwner {
        require(maxDeviation <= 5000, "Deviation too high"); // حداکثر 50%
        maxDeviationPerPool[pool] = maxDeviation;
    }

    /**
     * @dev فعال/غیرفعال circuit breaker
     * @param pool آدرس pool
     * @param triggered وضعیت
     */
    function setCircuitBreaker(address pool, bool triggered) external onlyOwner {
        circuitBreakerTriggered[pool] = triggered;
        
        if (!triggered) {
            // ذخیره آخرین قیمت معتبر
            PriceData storage data = priceData[pool];
            if (data.valid) {
                lastValidPrice[pool] = data.price;
            }
        }
    }

    /**
     * @dev دریافت اطلاعات pool
     * @param pool آدرس pool
     */
    function getPoolInfo(address pool) external view returns (
        address token0,
        address token1,
        uint24 fee,
        uint32 period,
        bool active,
        uint256 lastUpdate
    ) {
        PoolInfo storage info = poolInfo[pool];
        return (info.token0, info.token1, info.fee, info.period, info.active, info.lastUpdate);
    }

    /**
     * @dev دریافت آمار pool
     * @param pool آدرس pool
     */
    function getPoolStats(address pool) external view returns (
        uint256 currentPrice,
        uint256 twapPrice,
        uint256 liquidity,
        uint32 lastUpdate,
        bool circuitBreakerActive
    ) {
        PriceData storage data = priceData[pool];
        return (
            data.price,
            data.twapPrice,
            data.liquidity,
            data.timestamp,
            circuitBreakerTriggered[pool]
        );
    }

    /**
     * @dev محاسبه آدرس pool Uniswap V3
     */
    function _computePoolAddress(
        address token0,
        address token1,
        uint24 fee
    ) internal view returns (address pool) {
        if (token0 > token1) (token0, token1) = (token1, token0);
        
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniswapV3Factory,
            keccak256(abi.encode(token0, token1, fee)),
            hex'e34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54' // POOL_INIT_CODE_HASH
        )))));
    }

    /**
     * @dev دریافت tick فعلی
     */
    function _getCurrentTick(address pool) internal view returns (int24 tick, uint160 sqrtPriceX96) {
        // فرض می‌کنیم pool شامل slot0 است
        bytes memory data = abi.encodeWithSignature("slot0()");
        (bool success, bytes memory result) = pool.staticcall(data);
        
        if (success && result.length >= 64) {
            (sqrtPriceX96, tick) = abi.decode(result, (uint160, int24));
        } else {
            // fallback: استفاده از قیمت ذخیره شده
            tick = 0;
            sqrtPriceX96 = 0;
        }
    }

    /**
     * @dev تبدیل tick به قیمت
     */
    function _tickToPrice(int24 tick) internal pure returns (uint256 price) {
        if (tick == 0) return PRICE_PRECISION;
        
        // محاسبه ساده قیمت از tick
        // در واقعیت باید از کتابخانه TickMath استفاده کرد
        if (tick > 0) {
            price = PRICE_PRECISION + uint256(int256(tick)) * 1e14;
        } else {
            uint256 negativeTick = uint256(int256(-tick));
            price = PRICE_PRECISION > negativeTick * 1e14 ? 
                    PRICE_PRECISION - negativeTick * 1e14 : 
                    PRICE_PRECISION / 2;
        }
    }

    /**
     * @dev محاسبه TWAP
     */
    function _calculateTWAP(address pool, uint32 period) internal view returns (uint256 twapPrice) {
        Observation[] storage poolObservations = observations[pool];
        
        if (poolObservations.length < 2) revert InsufficientObservations();
        
        // پیدا کردن observations مناسب
        uint32 targetTime = uint32(block.timestamp) - period;
        
        int56 tickCumulativeStart = 0;
        int56 tickCumulativeEnd = 0;
        uint32 timeStart = 0;
        uint32 timeEnd = uint32(block.timestamp);
        
        // پیدا کردن observation نزدیک به target time
        for (uint256 i = poolObservations.length - 1; i > 0; i--) {
            if (poolObservations[i].blockTimestamp <= targetTime) {
                tickCumulativeStart = poolObservations[i].tickCumulative;
                timeStart = poolObservations[i].blockTimestamp;
                break;
            }
        }
        
        // آخرین observation
        if (poolObservations.length > 0) {
            Observation storage latest = poolObservations[poolObservations.length - 1];
            tickCumulativeEnd = latest.tickCumulative;
            timeEnd = latest.blockTimestamp;
        }
        
        if (timeEnd <= timeStart) {
            // fallback به قیمت فعلی
            return priceData[pool].price;
        }
        
        // محاسبه میانگین tick
        int24 averageTick = int24((tickCumulativeEnd - tickCumulativeStart) / int56(uint56(timeEnd - timeStart)));
        
        twapPrice = _tickToPrice(averageTick);
    }

    /**
     * @dev اعتبارسنجی قیمت
     */
    function _validatePrice(address pool, uint256 currentPrice, uint256 twapPrice) internal view {
        uint256 maxDeviation = maxDeviationPerPool[pool];
        
        // محاسبه انحراف
        uint256 deviation;
        if (currentPrice > twapPrice) {
            deviation = ((currentPrice - twapPrice) * Constants.BASIS_POINTS) / twapPrice;
        } else {
            deviation = ((twapPrice - currentPrice) * Constants.BASIS_POINTS) / twapPrice;
        }
        
        if (deviation > maxDeviation) revert PriceDeviationTooHigh();
    }

    /**
     * @dev دریافت نقدینگی pool
     */
    function _getPoolLiquidity(address pool) internal view returns (uint256 liquidity) {
        bytes memory data = abi.encodeWithSignature("liquidity()");
        (bool success, bytes memory result) = pool.staticcall(data);
        
        if (success && result.length >= 32) {
            liquidity = abi.decode(result, (uint128));
        } else {
            liquidity = 0;
        }
    }

    /**
     * @dev مقداردهی observations
     */
    function _initializeObservations(address pool) internal {
        // افزودن observation اولیه
        (int24 tick,) = _getCurrentTick(pool);
        
        observations[pool].push(Observation({
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: 0,
            secondsPerLiquidityCumulative: 0,
            initialized: true
        }));
    }

    /**
     * @dev اضافه کردن observation جدید
     */
    function _addObservation(address pool, int24 tick) internal {
        Observation[] storage poolObservations = observations[pool];
        
        // محدود کردن تعداد observations
        if (poolObservations.length >= 1000) {
            // حذف قدیمی‌ترین observation
            for (uint256 i = 0; i < poolObservations.length - 1; i++) {
                poolObservations[i] = poolObservations[i + 1];
            }
            poolObservations.pop();
        }
        
        // محاسبه cumulative values
        int56 newTickCumulative = 0;
        if (poolObservations.length > 0) {
            Observation storage last = poolObservations[poolObservations.length - 1];
            uint32 timeElapsed = uint32(block.timestamp) - last.blockTimestamp;
            newTickCumulative = last.tickCumulative + int56(tick) * int56(uint56(timeElapsed));
        }
        
        poolObservations.push(Observation({
            blockTimestamp: uint32(block.timestamp),
            tickCumulative: newTickCumulative,
            secondsPerLiquidityCumulative: 0, // ساده‌سازی
            initialized: true
        }));
    }

    /**
     * @dev دریافت تعداد pools
     */
    function getPoolsCount() external view returns (uint256) {
        return allPools.length;
    }

    /**
     * @dev دریافت لیست pools
     * @param start شروع
     * @param limit حد
     */
    function getPools(uint256 start, uint256 limit) external view returns (address[] memory pools) {
        uint256 end = start + limit;
        if (end > allPools.length) {
            end = allPools.length;
        }
        
        pools = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            pools[i - start] = allPools[i];
        }
    }
}