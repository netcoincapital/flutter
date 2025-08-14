# Test Suite - مجموعه تست‌ها

## ساختار تست‌ها

این پوشه شامل تست‌های جامع برای تمام 9 لایه DEX است:

## فایل‌های تست

### Unit Tests
- `01-core/` - تست‌های لایه Core
- `02-token/` - تست‌های لایه Token
- `03-pool/` - تست‌های لایه Pool
- `04-swap/` - تست‌های لایه Swap
- `05-liquidity/` - تست‌های لایه Liquidity
- `06-fee/` - تست‌های لایه Fee
- `07-router/` - تست‌های لایه Router
- `08-governance/` - تست‌های لایه Governance
- `09-security/` - تست‌های لایه Security

### Integration Tests
- `integration/` - تست‌های یکپارچگی
- `end-to-end/` - تست‌های E2E
- `performance/` - تست‌های عملکرد

### Utility Files
- `helpers/` - توابع کمکی تست
- `fixtures/` - داده‌های آزمایشی
- `mocks/` - Mock contracts

## اجرای تست‌ها

```bash
# اجرای همه تست‌ها
npm test

# تست یک لایه خاص
npx hardhat test test/01-core/**/*.test.js

# تست با coverage
npm run coverage

# تست gas usage
REPORT_GAS=true npm test
```

## ابزارهای تست

- **Hardhat**: Test runner
- **Chai**: Assertion library
- **Waffle**: Ethereum testing utilities
- **OpenZeppelin Test Helpers**: Testing utilities

## Coverage Target

- **Line Coverage**: > 95%
- **Branch Coverage**: > 90%
- **Function Coverage**: > 95% 