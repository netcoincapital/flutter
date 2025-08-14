# Liquidity Layer - لایه نقدینگی

## مسئولیت‌ها

این لایه مسئول مدیریت نقدینگی و LP tokens است:

### 1. Add Liquidity
- افزودن نقدینگی به pools
- LP token minting
- Position management

### 2. Remove Liquidity
- برداشت نقدینگی
- LP token burning
- Fee distribution

### 3. Rewards System
- Liquidity mining
- Yield farming
- Staking rewards

## فایل‌های این لایه

- `LiquidityManager.sol` - مدیریت نقدینگی
- `LiquidityProvider.sol` - عملیات LP
- `RewardDistributor.sol` - توزیع rewards
- `StakingPool.sol` - استخر staking
- `LiquidityMining.sol` - liquidity mining

## ویژگی‌ها

- Proportional liquidity addition
- Impermanent loss protection
- Auto-compound rewards
- Time-locked staking 