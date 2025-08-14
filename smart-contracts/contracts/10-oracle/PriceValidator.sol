// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./OracleLibrary.sol";
import "./UniswapV3Oracle.sol";
import "../libraries/Constants.sol";

/**
 * @title PriceValidator
 * @dev اعتبارسنجی قیمت‌ها و تشخیص manipulation
 */
contract PriceValidator is Ownable, ReentrancyGuard {

    struct ValidationRule {
        uint256 maxDeviation;          // حداکثر انحراف مجاز (basis points)
        uint256 minLiquidity;          // حداقل نقدینگی مورد نیاز
        uint256 maxPriceAge;           // حداکثر سن قیمت (ثانیه)
        uint256 minSources;            // حداقل تعداد منابع
        bool requireConsensus;         // آیا نیاز به consensus دارد
        bool active;                   // فعال/غیرفعال
    }

    struct PriceSource {
        address oracle;                // آدرس oracle
        uint256 weight;                // وزن در محاسبات
        uint256 reliability;           // قابلیت اعتماد (0-100)
        bool active;                   // فعال/غیرفعال
        uint256 lastUpdate;            // آخرین به‌روزرسانی
        uint256 errorCount;            // تعداد خطاها
        string sourceType;             // نوع منبع
    }

    struct ValidationResult {
        bool valid;                    // آیا معتبر است
        uint256 confidence;            // درجه اعتماد (0-100)
        uint256 finalPrice;            // قیمت نهایی
        string[] warnings;             // هشدارها
        string[] errors;               // خطاها
        uint256 timestamp;             // زمان validation
    }

    struct ManipulationDetection {
        bool detected;                 // آیا manipulation تشخیص داده شده
        uint256 severity;              // شدت (0-100)
        string manipulationType;       // نوع manipulation
        uint256 detectionTime;         // زمان تشخیص
        address[] suspiciousOracles;   // oracles مشکوک
    }

    struct CircuitBreaker {
        bool triggered;                // آیا فعال شده
        uint256 triggerTime;           // زمان فعال‌سازی
        uint256 cooldownPeriod;        // دوره خنک‌سازی
        string reason;                 // دلیل فعال‌سازی
        uint256 triggerCount;          // تعداد فعال‌سازی
    }

    // Events
    event PriceValidated(
        address indexed token0,
        address indexed token1,
        uint256 price,
        uint256 confidence,
        bool valid
    );

    event ManipulationDetected(
        address indexed token0,
        address indexed token1,
        string manipulationType,
        uint256 severity,
        address[] suspiciousOracles
    );

    event CircuitBreakerTriggered(
        address indexed token0,
        address indexed token1,
        string reason,
        uint256 cooldownPeriod
    );

    event SourceAdded(address indexed oracle, uint256 weight, string sourceType);
    event SourceRemoved(address indexed oracle);
    event ValidationRuleUpdated(address indexed token, uint256 maxDeviation, uint256 minLiquidity);

    // State variables
    mapping(address => mapping(address => ValidationRule)) public validationRules;
    mapping(address => PriceSource) public priceSources;
    mapping(address => mapping(address => CircuitBreaker)) public circuitBreakers;
    mapping(address => mapping(address => uint256[])) public priceHistory; // token pair => price history
    mapping(address => mapping(address => ManipulationDetection)) public manipulationStatus;
    
    address[] public allSources;
    UniswapV3Oracle public uniswapV3Oracle;
    
    // Global settings
    uint256 public constant MAX_SOURCES = 10;
    uint256 public constant HISTORY_SIZE = 100;              // تعداد قیمت‌های ذخیره شده
    uint256 public constant DEFAULT_MAX_DEVIATION = 500;     // 5% default deviation
    uint256 public constant DEFAULT_MIN_LIQUIDITY = 10000 * 10**18;
    uint256 public constant DEFAULT_MAX_PRICE_AGE = 3600;    // 1 hour
    uint256 public constant CIRCUIT_BREAKER_COOLDOWN = 1 hours;
    
    // Manipulation detection thresholds
    uint256 public constant PUMP_DUMP_THRESHOLD = 2000;      // 20% price change
    uint256 public constant VOLUME_SPIKE_THRESHOLD = 500;    // 5x volume increase
    uint256 public constant CONSENSUS_THRESHOLD = 67;        // 67% consensus required
    
    // Emergency controls
    bool public emergencyPaused = false;
    address public guardian;
    mapping(address => bool) public trustedValidators;

    error InvalidSource();
    error TooManySources();
    error InsufficientSources();
    error ValidationFailed();
    error ManipulationDetected();
    error CircuitBreakerActive();
    error EmergencyPaused();
    error UnauthorizedValidator();

    modifier onlyTrustedValidator() {
        if (!trustedValidators[msg.sender] && msg.sender != owner()) revert UnauthorizedValidator();
        _;
    }

    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPaused();
        _;
    }

    modifier circuitBreakerCheck(address token0, address token1) {
        CircuitBreaker storage breaker = circuitBreakers[token0][token1];
        if (breaker.triggered && block.timestamp < breaker.triggerTime + breaker.cooldownPeriod) {
            revert CircuitBreakerActive();
        }
        _;
    }

    constructor(address _uniswapV3Oracle, address _guardian) Ownable(msg.sender) {
        uniswapV3Oracle = UniswapV3Oracle(_uniswapV3Oracle);
        guardian = _guardian;
        trustedValidators[msg.sender] = true;
    }

    /**
     * @dev اعتبارسنجی قیمت
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     * @return result نتیجه validation
     */
    function validatePrice(
        address token0,
        address token1
    ) external view notPaused circuitBreakerCheck(token0, token1) returns (ValidationResult memory result) {
        ValidationRule storage rule = validationRules[token0][token1];
        if (!rule.active) {
            rule = validationRules[address(0)][address(0)]; // Default rule
        }
        
        // جمع‌آوری قیمت‌ها از منابع مختلف
        uint256[] memory prices = new uint256[](allSources.length);
        uint256[] memory weights = new uint256[](allSources.length);
        uint256[] memory confidences = new uint256[](allSources.length);
        uint256 validSources = 0;
        
        for (uint256 i = 0; i < allSources.length; i++) {
            PriceSource storage source = priceSources[allSources[i]];
            if (!source.active) continue;
            
            try this._getPriceFromSource(allSources[i], token0, token1) returns (uint256 price, uint256 confidence) {
                if (price > 0 && confidence >= 50) { // حداقل 50% confidence
                    prices[validSources] = price;
                    weights[validSources] = source.weight;
                    confidences[validSources] = confidence;
                    validSources++;
                }
            } catch {
                // Source failed, skip
                continue;
            }
        }
        
        if (validSources < rule.minSources) {
            result.valid = false;
            result.errors = new string[](1);
            result.errors[0] = "Insufficient price sources";
            return result;
        }
        
        // محاسبه قیمت نهایی
        result = _calculateFinalPrice(prices, weights, confidences, validSources, rule);
        
        // تشخیص manipulation
        ManipulationDetection memory manipulation = _detectManipulation(token0, token1, result.finalPrice);
        if (manipulation.detected && manipulation.severity > 70) {
            result.valid = false;
            result.errors = new string[](1);
            result.errors[0] = manipulation.manipulationType;
        }
        
        result.timestamp = block.timestamp;
    }

    /**
     * @dev به‌روزرسانی قیمت و validation
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     */
    function updateAndValidatePrice(
        address token0,
        address token1
    ) external onlyTrustedValidator nonReentrant notPaused returns (ValidationResult memory result) {
        result = this.validatePrice(token0, token1);
        
        if (result.valid) {
            // ذخیره قیمت در تاریخچه
            _updatePriceHistory(token0, token1, result.finalPrice);
            
            emit PriceValidated(token0, token1, result.finalPrice, result.confidence, true);
        } else {
            // بررسی trigger circuit breaker
            _checkCircuitBreakerTrigger(token0, token1, result);
        }
        
        return result;
    }

    /**
     * @dev اضافه کردن منبع قیمت
     * @param oracle آدرس oracle
     * @param weight وزن منبع
     * @param reliability قابلیت اعتماد
     * @param sourceType نوع منبع
     */
    function addPriceSource(
        address oracle,
        uint256 weight,
        uint256 reliability,
        string calldata sourceType
    ) external onlyOwner {
        if (oracle == address(0)) revert InvalidSource();
        if (allSources.length >= MAX_SOURCES) revert TooManySources();
        require(weight > 0 && weight <= 100, "Invalid weight");
        require(reliability <= 100, "Invalid reliability");
        
        priceSources[oracle] = PriceSource({
            oracle: oracle,
            weight: weight,
            reliability: reliability,
            active: true,
            lastUpdate: block.timestamp,
            errorCount: 0,
            sourceType: sourceType
        });
        
        allSources.push(oracle);
        
        emit SourceAdded(oracle, weight, sourceType);
    }

    /**
     * @dev حذف منبع قیمت
     * @param oracle آدرس oracle
     */
    function removePriceSource(address oracle) external onlyOwner {
        PriceSource storage source = priceSources[oracle];
        if (source.oracle == address(0)) revert InvalidSource();
        
        source.active = false;
        
        // حذف از آرایه
        for (uint256 i = 0; i < allSources.length; i++) {
            if (allSources[i] == oracle) {
                allSources[i] = allSources[allSources.length - 1];
                allSources.pop();
                break;
            }
        }
        
        emit SourceRemoved(oracle);
    }

    /**
     * @dev تنظیم قانون validation
     * @param token0 آدرس token0 (0x0 برای default)
     * @param token1 آدرس token1 (0x0 برای default)
     * @param maxDeviation حداکثر انحراف
     * @param minLiquidity حداقل نقدینگی
     * @param maxPriceAge حداکثر سن قیمت
     * @param minSources حداقل منابع
     * @param requireConsensus نیاز به consensus
     */
    function setValidationRule(
        address token0,
        address token1,
        uint256 maxDeviation,
        uint256 minLiquidity,
        uint256 maxPriceAge,
        uint256 minSources,
        bool requireConsensus
    ) external onlyOwner {
        require(maxDeviation <= 5000, "Deviation too high"); // حداکثر 50%
        require(minSources <= allSources.length, "Too many sources required");
        
        validationRules[token0][token1] = ValidationRule({
            maxDeviation: maxDeviation,
            minLiquidity: minLiquidity,
            maxPriceAge: maxPriceAge,
            minSources: minSources,
            requireConsensus: requireConsensus,
            active: true
        });
        
        emit ValidationRuleUpdated(token0, maxDeviation, minLiquidity);
    }

    /**
     * @dev فعال‌سازی circuit breaker
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     * @param reason دلیل
     * @param cooldownPeriod دوره خنک‌سازی
     */
    function triggerCircuitBreaker(
        address token0,
        address token1,
        string calldata reason,
        uint256 cooldownPeriod
    ) external onlyTrustedValidator {
        CircuitBreaker storage breaker = circuitBreakers[token0][token1];
        
        breaker.triggered = true;
        breaker.triggerTime = block.timestamp;
        breaker.cooldownPeriod = cooldownPeriod > 0 ? cooldownPeriod : CIRCUIT_BREAKER_COOLDOWN;
        breaker.reason = reason;
        breaker.triggerCount++;
        
        emit CircuitBreakerTriggered(token0, token1, reason, breaker.cooldownPeriod);
    }

    /**
     * @dev غیرفعال‌سازی circuit breaker
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     */
    function resetCircuitBreaker(address token0, address token1) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[token0][token1];
        breaker.triggered = false;
        breaker.triggerTime = 0;
        breaker.reason = "";
    }

    /**
     * @dev تنظیم emergency pause
     * @param paused وضعیت
     */
    function setEmergencyPaused(bool paused) external {
        require(msg.sender == guardian || msg.sender == owner(), "Not authorized");
        emergencyPaused = paused;
    }

    /**
     * @dev اضافه کردن trusted validator
     * @param validator آدرس validator
     */
    function addTrustedValidator(address validator) external onlyOwner {
        trustedValidators[validator] = true;
    }

    /**
     * @dev دریافت تاریخچه قیمت
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     * @return history آرایه قیمت‌ها
     */
    function getPriceHistory(address token0, address token1) external view returns (uint256[] memory history) {
        return priceHistory[token0][token1];
    }

    /**
     * @dev دریافت وضعیت manipulation
     * @param token0 آدرس token0
     * @param token1 آدرس token1
     */
    function getManipulationStatus(address token0, address token1) external view returns (
        bool detected,
        uint256 severity,
        string memory manipulationType,
        uint256 detectionTime
    ) {
        ManipulationDetection storage status = manipulationStatus[token0][token1];
        return (status.detected, status.severity, status.manipulationType, status.detectionTime);
    }

    /**
     * @dev دریافت قیمت از منبع
     */
    function _getPriceFromSource(
        address source,
        address token0,
        address token1
    ) external view returns (uint256 price, uint256 confidence) {
        PriceSource storage sourceInfo = priceSources[source];
        
        // بررسی سن آخرین به‌روزرسانی
        if (block.timestamp > sourceInfo.lastUpdate + DEFAULT_MAX_PRICE_AGE) {
            return (0, 0);
        }
        
        // دریافت قیمت بر اساس نوع منبع
        if (source == address(uniswapV3Oracle)) {
            try uniswapV3Oracle.getPrice(token0, token1) returns (uint256 oraclePrice) {
                price = oraclePrice;
                confidence = sourceInfo.reliability;
            } catch {
                price = 0;
                confidence = 0;
            }
        } else {
            // سایر منابع oracle
            try IOracle(source).getPrice(token0, token1) returns (uint256 oraclePrice) {
                price = oraclePrice;
                confidence = sourceInfo.reliability;
            } catch {
                price = 0;
                confidence = 0;
            }
        }
    }

    /**
     * @dev محاسبه قیمت نهایی
     */
    function _calculateFinalPrice(
        uint256[] memory prices,
        uint256[] memory weights,
        uint256[] memory confidences,
        uint256 validSources,
        ValidationRule storage rule
    ) internal pure returns (ValidationResult memory result) {
        // تشخیص outliers
        bool[] memory outliers = OracleLibrary.detectOutliers(prices, 1000); // 10% threshold
        
        // حذف outliers
        uint256[] memory filteredPrices = new uint256[](validSources);
        uint256[] memory filteredWeights = new uint256[](validSources);
        uint256 filteredCount = 0;
        
        for (uint256 i = 0; i < validSources; i++) {
            if (!outliers[i]) {
                filteredPrices[filteredCount] = prices[i];
                filteredWeights[filteredCount] = weights[i] * confidences[i] / 100; // وزن‌دهی با confidence
                filteredCount++;
            }
        }
        
        if (filteredCount == 0) {
            result.valid = false;
            result.errors = new string[](1);
            result.errors[0] = "All prices are outliers";
            return result;
        }
        
        // محاسبه قیمت وزن‌دار
        result.finalPrice = OracleLibrary.combineWeightedPrices(filteredPrices, filteredWeights);
        
        // محاسبه confidence
        result.confidence = _calculateOverallConfidence(filteredPrices, filteredWeights, filteredCount);
        
        // بررسی consensus
        if (rule.requireConsensus) {
            uint256 consensusLevel = _calculateConsensusLevel(prices, result.finalPrice, validSources);
            if (consensusLevel < CONSENSUS_THRESHOLD) {
                result.warnings = new string[](1);
                result.warnings[0] = "Low consensus among sources";
                result.confidence = result.confidence / 2; // کاهش confidence
            }
        }
        
        result.valid = result.confidence >= 50; // حداقل 50% confidence برای valid
    }

    /**
     * @dev تشخیص manipulation
     */
    function _detectManipulation(
        address token0,
        address token1,
        uint256 currentPrice
    ) internal view returns (ManipulationDetection memory detection) {
        uint256[] storage history = priceHistory[token0][token1];
        
        if (history.length < 5) {
            detection.detected = false;
            return detection;
        }
        
        // بررسی pump and dump
        uint256 recentAvg = 0;
        for (uint256 i = history.length - 5; i < history.length; i++) {
            recentAvg += history[i];
        }
        recentAvg = recentAvg / 5;
        
        uint256 deviation;
        if (currentPrice > recentAvg) {
            deviation = ((currentPrice - recentAvg) * Constants.BASIS_POINTS) / recentAvg;
        } else {
            deviation = ((recentAvg - currentPrice) * Constants.BASIS_POINTS) / recentAvg;
        }
        
        if (deviation > PUMP_DUMP_THRESHOLD) {
            detection.detected = true;
            detection.severity = deviation > 5000 ? 100 : (deviation * 100) / 5000; // scale to 0-100
            detection.manipulationType = currentPrice > recentAvg ? "Pump detected" : "Dump detected";
            detection.detectionTime = block.timestamp;
        }
        
        // بررسی volatility غیرطبیعی
        uint256 volatility = OracleLibrary.calculateVolatility(history);
        if (volatility > 3000) { // 30% volatility
            detection.detected = true;
            detection.severity = volatility > 5000 ? 100 : (volatility * 100) / 5000;
            detection.manipulationType = "Abnormal volatility";
            detection.detectionTime = block.timestamp;
        }
    }

    /**
     * @dev محاسبه overall confidence
     */
    function _calculateOverallConfidence(
        uint256[] memory prices,
        uint256[] memory weights,
        uint256 count
    ) internal pure returns (uint256 confidence) {
        if (count == 0) return 0;
        
        // محاسبه میانگین وزن‌ها
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < count; i++) {
            totalWeight += weights[i];
        }
        
        confidence = totalWeight / count;
        
        // کاهش confidence بر اساس پراکندگی
        uint256 variance = 0;
        uint256 mean = OracleLibrary.combineWeightedPrices(prices, weights);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 diff = prices[i] > mean ? prices[i] - mean : mean - prices[i];
            variance += (diff * diff) / mean;
        }
        variance = variance / count;
        
        // کاهش confidence بر اساس variance
        uint256 variancePenalty = variance > 100 ? 50 : (variance * 50) / 100;
        confidence = confidence > variancePenalty ? confidence - variancePenalty : confidence / 2;
        
        if (confidence > 100) confidence = 100;
    }

    /**
     * @dev محاسبه consensus level
     */
    function _calculateConsensusLevel(
        uint256[] memory prices,
        uint256 finalPrice,
        uint256 count
    ) internal pure returns (uint256 consensusLevel) {
        if (count == 0) return 0;
        
        uint256 agreeingPrices = 0;
        uint256 threshold = finalPrice / 20; // 5% threshold
        
        for (uint256 i = 0; i < count; i++) {
            uint256 diff = prices[i] > finalPrice ? prices[i] - finalPrice : finalPrice - prices[i];
            if (diff <= threshold) {
                agreeingPrices++;
            }
        }
        
        consensusLevel = (agreeingPrices * 100) / count;
    }

    /**
     * @dev به‌روزرسانی تاریخچه قیمت
     */
    function _updatePriceHistory(address token0, address token1, uint256 price) internal {
        uint256[] storage history = priceHistory[token0][token1];
        
        // محدود کردن اندازه تاریخچه
        if (history.length >= HISTORY_SIZE) {
            // جابجایی آیتم‌ها
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = price;
        } else {
            history.push(price);
        }
    }

    /**
     * @dev بررسی trigger circuit breaker
     */
    function _checkCircuitBreakerTrigger(
        address token0,
        address token1,
        ValidationResult memory result
    ) internal {
        // اگر validation fail شد و خطای جدی وجود دارد
        if (!result.valid && result.confidence < 20) {
            this.triggerCircuitBreaker(
                token0,
                token1,
                "Low confidence validation failure",
                CIRCUIT_BREAKER_COOLDOWN
            );
        }
    }
}

// Interface برای oracles خارجی
interface IOracle {
    function getPrice(address token0, address token1) external view returns (uint256 price);
}