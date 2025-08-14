# Oracle Layer - لایه اوراکل (Layer 10)

## مسئولیت‌ها

این لایه مسئول تأمین قیمت‌های دقیق و TWAP (Time-Weighted Average Price) است:

### 1. Price Oracle
- قیمت‌های فعلی توکن‌ها
- Integration با Chainlink
- Fallback price sources

### 2. TWAP (Time-Weighted Average Price)
- میانگین قیمت وزنی در زمان
- محافظت از manipulation
- Historical price data

### 3. Price Validation
- اعتبارسنجی قیمت‌ها
- Deviation detection
- Circuit breaker برای قیمت‌های غیرعادی

## فایل‌های این لایه

- `PriceOracle.sol` - اوراکل اصلی قیمت
- `TWAPOracle.sol` - میانگین قیمت وزنی زمانی
- `ChainlinkOracle.sol` - اتصال به Chainlink
- `UniswapV3Oracle.sol` - استفاده از Uniswap V3 TWAP
- `OracleLibrary.sol` - توابع کمکی اوراکل
- `PriceValidator.sol` - اعتبارسنجی قیمت‌ها

## ویژگی‌ها

### Time-Weighted Average Price (TWAP)
```solidity
// محاسبه TWAP در بازه زمانی مشخص
function getTWAP(
    address token0,
    address token1,
    uint32 secondsAgo
) external view returns (uint256);
```

### Multiple Oracle Sources
- **Primary**: Chainlink Price Feeds
- **Secondary**: Uniswap V3 TWAP
- **Fallback**: Internal pool prices

### Price Manipulation Protection
- **Minimum observation time**: حداقل 10 دقیقه
- **Maximum deviation**: حداکثر 5% انحراف
- **Circuit breaker**: توقف در صورت تغییرات شدید

## Integration با لایه‌های دیگر

### Pool Layer (Layer 3)
- ارائه قیمت‌های pool
- Observation storage

### Swap Layer (Layer 4)
- Price impact calculation
- Slippage validation

### Liquidity Layer (Layer 5)
- LP position valuation
- Impermanent loss calculation

### Security Layer (Layer 9)
- Price manipulation detection
- Emergency pause triggers

## Security Considerations

- **Oracle manipulation resistance**
- **Multi-source price aggregation**
- **Time-delay mechanisms**
- **Price bounds checking**
- **Fallback mechanisms**

## Gas Optimization

- **Efficient storage patterns**
- **Minimal external calls**
- **Cached price updates**
- **Batch price queries** 