# Pool Layer - لایه استخر

## مسئولیت‌ها

این لایه مسئول مدیریت استخرهای نقدینگی است:

### 1. Pool Management
- ایجاد و مدیریت pools
- Pool state management
- Pool parameters

### 2. Pool Factory
- ایجاد pools جدید
- Pool registry
- Template management

### 3. Pool Pairs
- Token pair management
- Pool discovery
- Price oracles

## فایل‌های این لایه

- `Pool.sol` - قرارداد اصلی pool
- `PoolFactory.sol` - کارخانه pools
- `PoolPair.sol` - مدیریت جفت توکن‌ها
- `PoolLibrary.sol` - توابع کمکی pool
- `PoolStorage.sol` - ذخیره‌سازی داده‌ها

## ویژگی‌ها

- Constant Product Formula (x * y = k)
- Multi-token pools support
- Dynamic fee structures
- Flash loan capabilities 