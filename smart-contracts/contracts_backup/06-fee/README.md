# Fee Layer - لایه کارمزد

## مسئولیت‌ها

این لایه مسئول مدیریت کارمزدها و توزیع آن‌ها است:

### 1. Fee Calculation
- محاسبه کارمزد swaps
- Dynamic fee rates
- Fee tiers management

### 2. Fee Distribution
- توزیع fees بین LPs
- Protocol fee collection
- Treasury management

### 3. Fee Optimization
- Gas optimization
- Fee rebates
- Volume-based discounts

## فایل‌های این لایه

- `FeeManager.sol` - مدیریت کارمزدها
- `FeeCalculator.sol` - محاسبه fees
- `FeeDistributor.sol` - توزیع fees (فقط واریز به Treasury)
- `FeeOptimizer.sol` - بهینه‌سازی fees
- `ProtocolFeeCollector.sol` - جمع‌آوری protocol fees

## Treasury Integration

**توجه مهم**: این لایه خزانه ندارد و فقط fees را به Treasury اصلی در Governance Layer واریز می‌کند تا:
- Centralized treasury management
- جلوگیری از scattered funds
- Unified governance control

## ویژگی‌ها

- Dynamic fee tiers (0.01%, 0.05%, 0.3%, 1%)
- Volume-based discounts
- LP fee sharing
- Protocol revenue 