# Swap Layer - لایه مبادله

## مسئولیت‌ها

این لایه مسئول منطق مبادله توکن‌ها است:

### 1. Swap Operations
- Token-to-token swaps
- Price calculation
- Slippage protection

### 2. Price Calculation
- AMM price formulas
- Impact calculation
- Arbitrage detection

### 3. Swap Execution
- Atomic swaps
- Multi-hop swaps
- Batch operations

## فایل‌های این لایه

- `SwapEngine.sol` - موتور اصلی swap (state-changing)
- `SwapQuoter.sol` - محاسبه off-chain quotes (view-only)
- `PriceCalculator.sol` - محاسبه قیمت
- `SlippageProtection.sol` - حفاظت از slippage
- `SwapLibrary.sol` - توابع کمکی
- `SwapValidator.sol` - اعتبارسنجی تراکنش‌ها

## Quoter vs Engine

### SwapQuoter (View-only)
- محاسبه مقدار خروجی بدون تغییر state
- برای UI و frontend استفاده می‌شود
- Gas-free برای کاربران
- Batch quote calculations

### SwapEngine (State-changing)
- اجرای واقعی swaps
- تغییر reserves و state
- Gas consumption دارد
- Security checks کامل

## الگوریتم‌ها

- Constant Product AMM
- Slippage tolerance
- Deadline protection
- MEV protection 