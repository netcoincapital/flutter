# Oracle Layer (Layer 5) - راهنمای کامل

## 🎯 خلاصه

**Oracle Layer** قلب سیستم قیمت‌گذاری در LAXCE DEX است که از طریق ترکیب مختلف منابع قیمت (TWAP و Chainlink)، قیمت‌های دقیق و قابل اعتماد ارائه می‌دهد.

## 📋 ساختار کامل

```
05-oracle/
├── TWAPOracle.sol         # Time-Weighted Average Price Oracle
├── ChainlinkOracle.sol    # Chainlink Price Feed Integration  
├── PriceOracle.sol        # Main Price Aggregation Contract
└── OracleManager.sol      # Central Oracle Management System
```

## 🔧 قراردادهای Oracle Layer

### 1. TWAPOracle.sol

**هدف**: محاسبه قیمت Time-Weighted Average Price (TWAP) بر اساس pool observationsها

#### ویژگی‌های کلیدی:
- ✅ **Pool Management**: اضافه/حذف pool برای monitoring
- ✅ **Observation Storage**: ذخیره سازی observations با cardinality قابل تنظیم
- ✅ **TWAP Calculation**: محاسبه TWAP برای period های مختلف
- ✅ **Price Validation**: تشخیص قیمت‌های غیرطبیعی
- ✅ **Emergency Mode**: حالت اضطراری با fallback mechanisms

#### توابع اصلی:

```solidity
// اضافه کردن pool جدید
function addPool(address pool, uint32 period, uint16 cardinality) external;

// به‌روزرسانی TWAP
function updateTWAP(address pool) external;

// دریافت قیمت TWAP
function getTWAPPrice(address pool, uint32 period) external view 
    returns (uint256 price0, uint256 price1);

// دریافت قیمت فوری
function getSpotPrice(address pool) external view 
    returns (uint256 price0, uint256 price1);
```

### 2. ChainlinkOracle.sol

**هدف**: ادغام Chainlink price feeds برای دریافت قیمت‌های خارجی

#### ویژگی‌های کلیدی:
- ✅ **Price Feed Management**: مدیریت Chainlink aggregators
- ✅ **Price Validation**: اعتبارسنجی قیمت با heartbeat check
- ✅ **Fallback Prices**: قیمت‌های پشتیبان در صورت خرابی
- ✅ **Historical Data**: نگهداری تاریخچه قیمت برای validation
- ✅ **Multi-decimal Support**: پشتیبانی از decimals مختلف

#### توابع اصلی:

```solidity
// اضافه کردن price feed
function addPriceFeed(
    address token0, 
    address token1, 
    address aggregator, 
    uint256 heartbeat
) external;

// دریافت آخرین قیمت
function getLatestPrice(address token0, address token1) 
    external view returns (PriceData memory);

// دریافت قیمت در round مشخص
function getPriceAtRound(address token0, address token1, uint80 roundId) 
    external view returns (PriceData memory);

// چک کردن سلامت feed
function isPriceFeedHealthy(address token0, address token1) 
    external view returns (bool);
```

### 3. PriceOracle.sol

**هدف**: ترکیب قیمت‌های TWAP و Chainlink برای ایجاد قیمت نهایی

#### ویژگی‌های کلیدی:
- ✅ **Price Aggregation**: ترکیب weighted average از منابع مختلف
- ✅ **Confidence Scoring**: امتیاز اعتماد برای هر قیمت
- ✅ **Deviation Detection**: تشخیص انحراف بین منابع
- ✅ **Emergency Handling**: مدیریت حالات اضطراری
- ✅ **Token Pair Management**: مدیریت پیکربندی هر جفت توکن

#### توابع اصلی:

```solidity
// اضافه کردن جفت توکن
function addTokenPair(
    address token0, 
    address token1, 
    OracleConfig calldata config
) external;

// دریافت قیمت تجمیعی
function getPrice(address token0, address token1) 
    external view returns (AggregatedPrice memory);

// دریافت قیمت با به‌روزرسانی
function getLatestPrice(address token0, address token1) 
    external returns (AggregatedPrice memory);

// دریافت همه قیمت‌ها برای مقایسه
function getAllPrices(address token0, address token1) 
    external view returns (uint256 twapPrice, uint256 chainlinkPrice, AggregatedPrice memory);
```

### 4. OracleManager.sol

**هدف**: مدیریت مرکزی تمام oracle ها با قابلیت monitoring و automation

#### ویژگی‌های کلیدی:
- ✅ **Oracle Registration**: ثبت و مدیریت oracle های مختلف
- ✅ **Health Monitoring**: نظارت بر سلامت تمام oracle ها
- ✅ **Batch Updates**: به‌روزرسانی دسته‌ای قیمت‌ها
- ✅ **Emergency Management**: مدیریت شرایط اضطراری
- ✅ **Automation**: به‌روزرسانی خودکار قیمت‌ها

#### توابع اصلی:

```solidity
// ثبت oracle جدید
function registerOracle(
    address oracle, 
    OracleType oracleType, 
    string calldata name, 
    uint256 priority
) external;

// دریافت قیمت با validation
function getValidatedPrice(address token0, address token1) 
    external view returns (AggregatedPrice memory);

// به‌روزرسانی دسته‌ای قیمت‌ها
function batchUpdatePrices(
    address[] calldata token0s, 
    address[] calldata token1s, 
    bool forceUpdate
) external returns (uint256 batchId);

// انجام health check کامل
function performGlobalHealthCheck() external;
```

## 🚀 راهنمای استفاده

### 1. راه‌اندازی اولیه

```javascript
// Deploy Oracle Layer
const twapOracle = await TWAPOracle.deploy();
const chainlinkOracle = await ChainlinkOracle.deploy();
const priceOracle = await PriceOracle.deploy(twapOracle.address, chainlinkOracle.address);
const oracleManager = await OracleManager.deploy(
    priceOracle.address, 
    twapOracle.address, 
    chainlinkOracle.address
);
```

### 2. پیکربندی TWAP Oracle

```javascript
// اضافه کردن pool برای TWAP
await twapOracle.addPool(
    poolAddress,
    3600,  // 1 hour period
    100    // cardinality
);

// تنظیم پیکربندی پیش‌فرض
await twapOracle.setDefaultConfiguration(3600, 100, 300);
```

### 3. پیکربندی Chainlink Oracle

```javascript
// اضافه کردن price feed
await chainlinkOracle.addPriceFeed(
    tokenA.address,
    tokenB.address,
    chainlinkAggregator.address,
    3600  // heartbeat
);

// تنظیم validation config
await chainlinkOracle.setValidationConfig({
    maxPriceDeviation: 1000,      // 10%
    stalePriceThreshold: 3600,    // 1 hour
    enableValidation: true,
    requireMinAnswers: false,
    minAnswers: 1
});
```

### 4. پیکربندی Price Oracle

```javascript
// اضافه کردن token pair
const oracleConfig = {
    useTWAP: true,
    useChainlink: true,
    requireBothSources: false,
    maxDeviation: 1000,         // 10%
    twapWeight: 6000,           // 60%
    chainlinkWeight: 4000,      // 40%
    confidenceThreshold: 7000,  // 70%
    stalePriceThreshold: 3600   // 1 hour
};

await priceOracle.addTokenPair(tokenA.address, tokenB.address, oracleConfig);
```

### 5. استفاده در DEX

```javascript
// دریافت قیمت برای swap
const price = await oracleManager.getValidatedPrice(tokenA.address, tokenB.address);

if (price.isValid && price.confidence >= 7000) {
    // استفاده از قیمت برای محاسبه swap
    const amountOut = calculateSwapAmount(amountIn, price.price);
}

// چک کردن انحراف قیمت
if (price.deviation > 500) { // 5%
    console.warn("High price deviation detected!");
}
```

## 🔐 امنیت و بهترین روش‌ها

### 1. اعتبارسنجی قیمت

```javascript
// همیشه confidence را چک کنید
function validatePrice(price) {
    require(price.isValid, "Invalid price");
    require(price.confidence >= 7000, "Low confidence");
    require(block.timestamp - price.timestamp <= 3600, "Stale price");
}
```

### 2. مدیریت حالت اضطراری

```javascript
// فعال کردن emergency mode
await oracleManager.activateEmergencyMode("High price deviation detected");

// تنظیم قیمت اضطراری
await priceOracle.setEmergencyPrice(tokenA.address, tokenB.address, emergencyPrice);
```

### 3. نظارت بر سلامت

```javascript
// انجام health check منظم
await oracleManager.performGlobalHealthCheck();

// چک کردن گزارش سلامت
const healthReport = await oracleManager.getHealthReport();
for (const report of healthReport) {
    if (!report.isHealthy) {
        console.warn(`Oracle ${report.oracle} is unhealthy`);
    }
}
```

## 📊 نظارت و Analytics

### 1. متریک‌های کلیدی

- **Price Accuracy**: انحراف بین TWAP و Chainlink
- **Update Frequency**: تعدد به‌روزرسانی قیمت‌ها
- **Oracle Health**: وضعیت سلامت oracle ها
- **Confidence Scores**: میانگین امتیاز اعتماد

### 2. هشدارهای مهم

- انحراف قیمت بالای 5%
- عدم به‌روزرسانی بیش از 1 ساعت
- کاهش confidence زیر 70%
- خرابی Chainlink feeds

## 🧪 تست‌ها

```bash
# اجرای تست‌های Oracle Layer
npm run test:oracle

# تست‌های مشخص
npx hardhat test test/05-oracle/TWAPOracle.test.js
npx hardhat test test/05-oracle/ChainlinkOracle.test.js
npx hardhat test test/05-oracle/PriceOracle.test.js
npx hardhat test test/05-oracle/OracleManager.test.js
```

## 🚀 Deploy کردن

```bash
# Deploy به localhost
npm run deploy:oracle

# Deploy به testnet
npm run deploy:oracle:testnet

# Deploy به mainnet
npx hardhat run scripts/deploy-oracle.js --network mainnet
```

## 🔗 ادغام با Flutter

### دریافت قیمت‌ها در Flutter:

```dart
// lib/services/oracle_service.dart
class OracleService {
  Future<PriceData> getTokenPrice(String tokenA, String tokenB) async {
    final contract = DeployedContract(oracleManagerAbi, oracleManagerAddress);
    final getPrice = contract.function('getValidatedPrice');
    
    final result = await web3client.call(
      contract: contract,
      function: getPrice,
      params: [EthereumAddress.fromHex(tokenA), EthereumAddress.fromHex(tokenB)],
    );
    
    return PriceData.fromBlockchain(result);
  }
}
```

## 🎯 **نتیجه**

✅ **Oracle Layer کامل شد!** 

این لایه شامل:
- 📊 TWAPOracle برای قیمت‌های on-chain
- 🔗 ChainlinkOracle برای قیمت‌های خارجی  
- 💰 PriceOracle برای تجمیع قیمت‌ها
- 🎛️ OracleManager برای مدیریت مرکزی
- ✅ تست‌های کامل و deployment scripts

**Layer بعدی**: Layer 6 - Governance 🗳️ 