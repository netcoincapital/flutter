# Token Layer - لایه توکن

## مسئولیت‌ها

این لایه مسئول مدیریت توکن‌ها و استانداردهای آن‌ها است:

### 1. ERC20 Tokens
- پیاده‌سازی استاندارد ERC20
- Token metadata management
- Transfer mechanics

### 2. LP Tokens
- Liquidity Provider tokens
- Pool representation
- Stake management

### 3. Token Registry
- فهرست توکن‌های پشتیبانی شده
- Token validation
- Whitelist/Blacklist management

### 4. Position NFT (ERC-721)
- NFT-based liquidity positions (مشابه Uniswap V3)
- Concentrated liquidity ranges
- Position metadata و visualization

## فایل‌های این لایه

- `ERC20Token.sol` - پیاده‌سازی ERC20
- `LPToken.sol` - توکن‌های نقدینگی (برای full-range positions)
- `PositionNFT.sol` - NFT positions برای concentrated liquidity
- `TokenRegistry.sol` - ثبت نام توکن‌ها
- `TokenFactory.sol` - ایجاد توکن‌های جدید
- `WETH.sol` - Wrapped Ether

## Dependencies

```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
```

## ویژگی‌ها

- Mintable/Burnable tokens
- Pausable functionality
- Fee-on-transfer support
- Deflationary token support 