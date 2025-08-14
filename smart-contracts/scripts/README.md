# Scripts - اسکریپت‌های پروژه

## مسئولیت‌ها

این پوشه شامل اسکریپت‌های deployment و مدیریت پروژه است:

## فایل‌ها

### Deployment Scripts
- `deploy.js` - اسکریپت اصلی deployment
- `deploy-core.js` - deploy لایه Core
- `deploy-tokens.js` - deploy لایه Token
- `deploy-pools.js` - deploy لایه Pool
- `deploy-swap.js` - deploy لایه Swap
- `deploy-liquidity.js` - deploy لایه Liquidity
- `deploy-fees.js` - deploy لایه Fee
- `deploy-router.js` - deploy لایه Router
- `deploy-governance.js` - deploy لایه Governance
- `deploy-security.js` - deploy لایه Security

### Management Scripts
- `verify-contracts.js` - تایید قراردادها
- `upgrade.js` - ارتقاء قراردادها
- `initialize.js` - راه‌اندازی اولیه
- `configure.js` - پیکربندی سیستم

### Utility Scripts
- `flatten.js` - تخت کردن قراردادها
- `gas-estimation.js` - تخمین gas
- `network-config.js` - پیکربندی شبکه‌ها

## استفاده

```bash
# Deploy همه قراردادها
npm run deploy:testnet

# Deploy یک لایه خاص
npx hardhat run scripts/deploy-core.js --network sepolia

# Verify قراردادها
npx hardhat run scripts/verify-contracts.js --network polygon
``` 