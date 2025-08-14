// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Constants.sol";
import "../libraries/FullMath.sol";
import "./FeeCalculator.sol";

/**
 * @title FeeOptimizer
 * @dev بهینه‌سازی کارمزدها بر اساس شرایط بازار
 */
contract FeeOptimizer is Ownable, ReentrancyGuard {
    using FullMath for uint256;

    struct MarketCondition {
        uint256 volatility;         // نوسانات بازار (basis points)
        uint256 liquidity;          // میزان نقدینگی
        uint256 volume24h;          // حجم 24 ساعته
        uint256 priceImpact;        // تأثیر قیمت
        uint256 lastUpdate;         // آخرین به‌روزرسانی
    }

    struct OptimizationRule {
        uint256 minVolume;          // حداقل volume
        uint256 maxVolume;          // حداکثر volume
        uint256 minVolatility;      // حداقل volatility
        uint256 maxVolatility;      // حداکثر volatility
        uint256 feeAdjustment;      // تعدیل fee (basis points, positive = increase, negative = decrease)
        bool active;                // فعال/غیرفعال
    }

    struct GasOptimization {
        uint256 gasPrice;           // قیمت gas فعلی
        uint256 optimalFee;         // fee بهینه بر اساس gas
        uint256 lastUpdate;         // آخرین به‌روزرسانی
        bool dynamicEnabled;        // آیا dynamic gas optimization فعال است
    }

    // Events
    event FeeOptimized(
        address indexed pool,
        address indexed tokenA,
        address indexed tokenB,
        uint256 oldFee,
        uint256 newFee,
        string reason
    );

    event MarketConditionUpdated(
        address indexed pool,
        uint256 volatility,
        uint256 liquidity,
        uint256 volume24h
    );

    event OptimizationRuleAdded(
        uint256 indexed ruleId,
        uint256 minVolume,
        uint256 maxVolume,
        uint256 feeAdjustment
    );

    event GasOptimizationUpdated(
        uint256 gasPrice,
        uint256 optimalFee
    );

    // State variables
    FeeCalculator public feeCalculator;
    
    mapping(address => MarketCondition) public marketConditions;
    mapping(uint256 => OptimizationRule) public optimizationRules;
    mapping(address => GasOptimization) public gasOptimizations;
    mapping(address => mapping(address => uint256)) public optimizedFees; // tokenA => tokenB => fee
    
    uint256 public totalRules = 0;
    uint256 public constant MAX_FEE_ADJUSTMENT = 500;    // حداکثر 5% تعدیل
    uint256 public constant MIN_FEE = 1;                 // حداقل 0.01% fee
    uint256 public constant MAX_FEE = 1000;              // حداکثر 10% fee
    
    // Market analysis parameters
    uint256 public constant HIGH_VOLATILITY_THRESHOLD = 500;   // 5%
    uint256 public constant LOW_LIQUIDITY_THRESHOLD = 10000;   // تعریف liquidity کم
    uint256 public constant HIGH_VOLUME_THRESHOLD = 1000000;   // حجم بالا
    
    // Gas optimization parameters
    uint256 public constant HIGH_GAS_THRESHOLD = 50 gwei;
    uint256 public constant LOW_GAS_THRESHOLD = 10 gwei;
    
    // Update intervals
    uint256 public marketUpdateInterval = 1 hours;
    uint256 public gasUpdateInterval = 15 minutes;
    
    // Permissions
    mapping(address => bool) public authorizedOptimizers;
    mapping(address => bool) public marketDataProviders;

    error UnauthorizedOptimizer();
    error UnauthorizedDataProvider();
    error InvalidRule();
    error InvalidFee();
    error InvalidPool();
    error UpdateTooFrequent();

    modifier onlyAuthorizedOptimizer() {
        if (!authorizedOptimizers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedOptimizer();
        }
        _;
    }

    modifier onlyMarketDataProvider() {
        if (!marketDataProviders[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedDataProvider();
        }
        _;
    }

    constructor(address _feeCalculator) Ownable(msg.sender) {
        if (_feeCalculator == address(0)) revert InvalidPool();
        feeCalculator = FeeCalculator(_feeCalculator);
        
        authorizedOptimizers[msg.sender] = true;
        marketDataProviders[msg.sender] = true;
        
        _initializeDefaultRules();
    }

    /**
     * @dev بهینه‌سازی fee برای pool
     * @param pool آدرس pool
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @return optimizedFee fee بهینه شده
     */
    function optimizeFee(
        address pool,
        address tokenA,
        address tokenB
    ) external onlyAuthorizedOptimizer returns (uint256 optimizedFee) {
        MarketCondition storage condition = marketConditions[pool];
        
        // دریافت fee پایه
        uint256 baseFee = _getBaseFee(pool, tokenA, tokenB);
        
        // اعمال بهینه‌سازی بر اساس شرایط بازار
        optimizedFee = _applyMarketOptimization(baseFee, condition);
        
        // اعمال بهینه‌سازی بر اساس gas
        optimizedFee = _applyGasOptimization(optimizedFee, pool);
        
        // اعمال محدودیت‌ها
        optimizedFee = _applyLimits(optimizedFee);
        
        // ذخیره fee بهینه شده
        optimizedFees[tokenA][tokenB] = optimizedFee;
        optimizedFees[tokenB][tokenA] = optimizedFee; // symmetric
        
        emit FeeOptimized(pool, tokenA, tokenB, baseFee, optimizedFee, "market_and_gas_optimization");
        
        return optimizedFee;
    }

    /**
     * @dev بهینه‌سازی batch برای چندین pool
     * @param pools آرایه pools
     * @param tokenPairs آرایه جفت tokens
     */
    function optimizeBatchFees(
        address[] calldata pools,
        address[2][] calldata tokenPairs
    ) external onlyAuthorizedOptimizer {
        require(pools.length == tokenPairs.length, "Array length mismatch");
        
        for (uint256 i = 0; i < pools.length; i++) {
            this.optimizeFee(pools[i], tokenPairs[i][0], tokenPairs[i][1]);
        }
    }

    /**
     * @dev به‌روزرسانی شرایط بازار
     * @param pool آدرس pool
     * @param volatility نوسانات
     * @param liquidity نقدینگی
     * @param volume24h حجم 24 ساعته
     * @param priceImpact تأثیر قیمت
     */
    function updateMarketCondition(
        address pool,
        uint256 volatility,
        uint256 liquidity,
        uint256 volume24h,
        uint256 priceImpact
    ) external onlyMarketDataProvider {
        MarketCondition storage condition = marketConditions[pool];
        
        if (block.timestamp < condition.lastUpdate + marketUpdateInterval) {
            revert UpdateTooFrequent();
        }
        
        condition.volatility = volatility;
        condition.liquidity = liquidity;
        condition.volume24h = volume24h;
        condition.priceImpact = priceImpact;
        condition.lastUpdate = block.timestamp;
        
        emit MarketConditionUpdated(pool, volatility, liquidity, volume24h);
    }

    /**
     * @dev به‌روزرسانی gas optimization
     * @param gasPrice قیمت gas فعلی
     */
    function updateGasOptimization(uint256 gasPrice) external onlyMarketDataProvider {
        GasOptimization storage gasOpt = gasOptimizations[address(0)]; // global gas optimization
        
        if (block.timestamp < gasOpt.lastUpdate + gasUpdateInterval) {
            revert UpdateTooFrequent();
        }
        
        gasOpt.gasPrice = gasPrice;
        gasOpt.optimalFee = _calculateOptimalGasFee(gasPrice);
        gasOpt.lastUpdate = block.timestamp;
        
        emit GasOptimizationUpdated(gasPrice, gasOpt.optimalFee);
    }

    /**
     * @dev اضافه کردن قانون بهینه‌سازی
     * @param minVolume حداقل volume
     * @param maxVolume حداکثر volume
     * @param minVolatility حداقل volatility
     * @param maxVolatility حداکثر volatility
     * @param feeAdjustment تعدیل fee
     */
    function addOptimizationRule(
        uint256 minVolume,
        uint256 maxVolume,
        uint256 minVolatility,
        uint256 maxVolatility,
        int256 feeAdjustment
    ) external onlyOwner {
        if (maxVolume <= minVolume || maxVolatility <= minVolatility) revert InvalidRule();
        if (uint256(feeAdjustment > 0 ? feeAdjustment : -feeAdjustment) > MAX_FEE_ADJUSTMENT) revert InvalidRule();
        
        uint256 ruleId = totalRules++;
        optimizationRules[ruleId] = OptimizationRule({
            minVolume: minVolume,
            maxVolume: maxVolume,
            minVolatility: minVolatility,
            maxVolatility: maxVolatility,
            feeAdjustment: uint256(feeAdjustment), // ذخیره به صورت unsigned
            active: true
        });
        
        emit OptimizationRuleAdded(ruleId, minVolume, maxVolume, uint256(feeAdjustment));
    }

    /**
     * @dev فعال/غیرفعال کردن قانون
     * @param ruleId شناسه قانون
     * @param active وضعیت
     */
    function setRuleActive(uint256 ruleId, bool active) external onlyOwner {
        if (ruleId >= totalRules) revert InvalidRule();
        optimizationRules[ruleId].active = active;
    }

    /**
     * @dev اضافه کردن authorized optimizer
     * @param optimizer آدرس optimizer
     */
    function addAuthorizedOptimizer(address optimizer) external onlyOwner {
        if (optimizer == address(0)) revert InvalidPool();
        authorizedOptimizers[optimizer] = true;
    }

    /**
     * @dev اضافه کردن market data provider
     * @param provider آدرس provider
     */
    function addMarketDataProvider(address provider) external onlyOwner {
        if (provider == address(0)) revert InvalidPool();
        marketDataProviders[provider] = true;
    }

    /**
     * @dev دریافت fee بهینه شده
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @return fee
     */
    function getOptimizedFee(address tokenA, address tokenB) external view returns (uint256 fee) {
        fee = optimizedFees[tokenA][tokenB];
        if (fee == 0) {
            // اگر بهینه‌سازی نشده، از fee پایه استفاده کن
            fee = 30; // default 0.3%
        }
    }

    /**
     * @dev پیش‌بینی fee بر اساس شرایط
     * @param pool آدرس pool
     * @param tokenA توکن A
     * @param tokenB توکن B
     * @param predictedVolatility volatility پیش‌بینی شده
     * @param predictedVolume volume پیش‌بینی شده
     * @return predictedFee fee پیش‌بینی شده
     */
    function predictOptimizedFee(
        address pool,
        address tokenA,
        address tokenB,
        uint256 predictedVolatility,
        uint256 predictedVolume
    ) external view returns (uint256 predictedFee) {
        uint256 baseFee = _getBaseFee(pool, tokenA, tokenB);
        
        // ایجاد شرایط فرضی
        MarketCondition memory predictedCondition = MarketCondition({
            volatility: predictedVolatility,
            liquidity: marketConditions[pool].liquidity,
            volume24h: predictedVolume,
            priceImpact: marketConditions[pool].priceImpact,
            lastUpdate: block.timestamp
        });
        
        // اعمال بهینه‌سازی
        predictedFee = _applyMarketOptimization(baseFee, predictedCondition);
        predictedFee = _applyGasOptimization(predictedFee, pool);
        predictedFee = _applyLimits(predictedFee);
    }

    /**
     * @dev دریافت fee پایه
     */
    function _getBaseFee(address pool, address tokenA, address tokenB) internal view returns (uint256) {
        // این باید از FeeCalculator دریافت شود
        // فعلاً مقدار پیش‌فرض برمی‌گرداند
        return 30; // 0.3%
    }

    /**
     * @dev اعمال بهینه‌سازی بازار
     */
    function _applyMarketOptimization(
        uint256 baseFee,
        MarketCondition memory condition
    ) internal view returns (uint256 optimizedFee) {
        optimizedFee = baseFee;
        
        // اعمال قوانین بهینه‌سازی
        for (uint256 i = 0; i < totalRules; i++) {
            OptimizationRule storage rule = optimizationRules[i];
            
            if (!rule.active) continue;
            
            // بررسی شرایط
            if (condition.volume24h >= rule.minVolume &&
                condition.volume24h <= rule.maxVolume &&
                condition.volatility >= rule.minVolatility &&
                condition.volatility <= rule.maxVolatility) {
                
                // اعمال تعدیل
                if (rule.feeAdjustment <= MAX_FEE_ADJUSTMENT) {
                    optimizedFee += rule.feeAdjustment;
                } else {
                    optimizedFee -= (rule.feeAdjustment - MAX_FEE_ADJUSTMENT);
                }
            }
        }
        
        // تعدیل بر اساس نقدینگی
        if (condition.liquidity < LOW_LIQUIDITY_THRESHOLD) {
            optimizedFee += 10; // افزایش 0.1% برای نقدینگی کم
        }
        
        // تعدیل بر اساس نوسانات
        if (condition.volatility > HIGH_VOLATILITY_THRESHOLD) {
            optimizedFee += 20; // افزایش 0.2% برای نوسانات بالا
        }
    }

    /**
     * @dev اعمال بهینه‌سازی gas
     */
    function _applyGasOptimization(uint256 fee, address pool) internal view returns (uint256) {
        GasOptimization storage gasOpt = gasOptimizations[pool];
        if (!gasOpt.dynamicEnabled) return fee;
        
        if (gasOpt.gasPrice > HIGH_GAS_THRESHOLD) {
            // gas بالا: کاهش fee برای جبران
            return fee > 5 ? fee - 5 : fee;
        } else if (gasOpt.gasPrice < LOW_GAS_THRESHOLD) {
            // gas پایین: افزایش fee
            return fee + 3;
        }
        
        return fee;
    }

    /**
     * @dev محاسبه fee بهینه بر اساس gas
     */
    function _calculateOptimalGasFee(uint256 gasPrice) internal pure returns (uint256) {
        if (gasPrice > HIGH_GAS_THRESHOLD) {
            return 25; // 0.25%
        } else if (gasPrice < LOW_GAS_THRESHOLD) {
            return 35; // 0.35%
        }
        return 30; // 0.3% default
    }

    /**
     * @dev اعمال محدودیت‌ها
     */
    function _applyLimits(uint256 fee) internal pure returns (uint256) {
        if (fee < MIN_FEE) return MIN_FEE;
        if (fee > MAX_FEE) return MAX_FEE;
        return fee;
    }

    /**
     * @dev مقداردهی قوانین پیش‌فرض
     */
    function _initializeDefaultRules() internal {
        // قانون 1: حجم بالا = fee کمتر
        optimizationRules[0] = OptimizationRule({
            minVolume: HIGH_VOLUME_THRESHOLD,
            maxVolume: type(uint256).max,
            minVolatility: 0,
            maxVolatility: type(uint256).max,
            feeAdjustment: MAX_FEE_ADJUSTMENT - 50, // کاهش 5 basis points
            active: true
        });
        
        // قانون 2: نوسانات بالا = fee بیشتر
        optimizationRules[1] = OptimizationRule({
            minVolume: 0,
            maxVolume: type(uint256).max,
            minVolatility: HIGH_VOLATILITY_THRESHOLD,
            maxVolatility: type(uint256).max,
            feeAdjustment: 100, // افزایش 10 basis points
            active: true
        });
        
        totalRules = 2;
    }
}