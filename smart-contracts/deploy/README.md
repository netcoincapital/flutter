# Deploy Configuration - پیکربندی استقرار

## مسئولیت‌ها

این پوشه شامل فایل‌های پیکربندی و آدرس‌های deployed contracts است:

## فایل‌ها

### Network Configurations
- `mainnet.json` - پیکربندی Ethereum Mainnet
- `sepolia.json` - پیکربندی Sepolia Testnet
- `polygon.json` - پیکربندی Polygon Mainnet
- `mumbai.json` - پیکربندی Mumbai Testnet
- `bsc.json` - پیکربندی BSC Mainnet
- `bsc-testnet.json` - پیکربندی BSC Testnet
- `arbitrum.json` - پیکربندی Arbitrum

### Deployed Addresses
- `addresses/` - آدرس‌های contracts deployed شده
- `abis/` - فایل‌های ABI
- `metadata/` - متادیتای contracts

### Migration Files
- `migrations/` - فایل‌های migration
- `upgrades/` - تاریخچه upgrades
- `backups/` - پشتیبان‌گیری از configs

## ساختار فایل پیکربندی

```json
{
  "network": "mainnet",
  "rpcUrl": "https://mainnet.infura.io/v3/YOUR_KEY",
  "gasPrice": "auto",
  "contracts": {
    "factory": {
      "address": "0x...",
      "deployedAt": "2024-01-01",
      "verified": true
    }
  },
  "tokens": {
    "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    "USDC": "0xA0b86a33E6d2c20f84c0AB49e8b03FFDEF38aFa4"
  }
}
```

## استفاده

```bash
# Deploy به شبکه testnet
npm run deploy:testnet

# بررسی آدرس‌های deployed
cat deploy/addresses/sepolia.json

# Backup configurations
cp deploy/*.json deploy/backups/
``` 