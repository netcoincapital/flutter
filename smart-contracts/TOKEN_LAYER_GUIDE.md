# 🎉 Token Layer (Layer 2) - آماده و قابل استفاده!

## خلاصه

**لایه Token با تمام ویژگی‌های Revenue & Incentives با موفقیت تکمیل شد** و شامل موارد زیر است:

### ✅ Contracts آماده شده:

#### 1. **LAXCE.sol** - توکن اصلی با قابلیت‌های پیشرفته
- ✅ **Token Locking** برای fee discounts و voting power
- ✅ **Revenue Sharing** - کاربران از protocol fees سهم می‌گیرند
- ✅ **Dynamic Fee Discounts** - تا 50% تخفیف بر اساس lock amount/duration
- ✅ **Governance Voting** - voting power بر اساس locked tokens
- ✅ **Lock/Unlock System** با مدت‌های مختلف (30 روز تا 4 سال)

#### 2. **LPToken.sol** - LP tokens با mining rewards
- ✅ **LP Mining** - کاربران با نگهداری LP پاداش می‌گیرند
- ✅ **Trading Mining** - پاداش برای انجام trades
- ✅ **Withdraw Fee** - کارمزد برداشت زودهنگام (0.5% کاهشی بر اساس زمان)
- ✅ **Staking Rewards** - پاداش‌های قابل تنظیم per-block
- ✅ **Trading Volume Tracking** - ثبت حجم معاملات

#### 3. **TokenRegistry.sol** - مدیریت tokens با listing fee
- ✅ **Listing Fee System** - 0.1 ETH base fee با تخفیف‌های LAXCE
- ✅ **Token Tiers** - BASIC, VERIFIED, PREMIUM, FEATURED
- ✅ **LAXCE Holder Discounts** - تا 90% تخفیف برای دارندگان بزرگ
- ✅ **Whitelist/Blacklist** - مدیریت کامل tokens
- ✅ **Auto-approval** option برای راحتی

## 💰 ویژگی‌های درآمدزایی پیاده‌سازی شده:

### برای خزانه/تیم:
- ✅ **Protocol Revenue Sharing** - درصدی از درآمد به token holders
- ✅ **Listing Fees** - 0.1 ETH per token (با تخفیف برای LAXCE holders)
- ✅ **Withdraw Fees** - 0.5% کارمزد برداشت زودهنگام LP
- ✅ **Fee Collection System** - جمع‌آوری خودکار fees

### برای کاربران:
- ✅ **LP Mining Rewards** - پاداش برای liquidity providers
- ✅ **Trading Mining** - پاداش برای traders (2x multiplier)
- ✅ **Dynamic Fee Discounts** - تخفیف‌های fee تا 50%
- ✅ **Revenue Share Claims** - دریافت سهم از protocol revenue
- ✅ **Voting Power** - حق رای در governance

## 🧪 تست کردن

```bash
# تست Token Layer
npm run test:token

# تست همه لایه‌ها
npm test

# Coverage report
npm run coverage
```

## 🚀 Deployment

```bash
# Deploy به local network
npm run deploy:token

# Deploy به testnet
npm run deploy:token:testnet
```

## 💻 نحوه استفاده

### 1. LAXCE Token Features

```solidity
// Lock tokens برای fee discount و voting power
await laxce.lockTokens(amount, duration);

// محاسبه fee discount
uint256 discount = await laxce.calculateFeeDiscount(user);

// Claim revenue share
await laxce.claimRevenue();

// دریافت voting power
uint256 votingPower = await laxce.getVotingPower(user);
```

### 2. LP Token Mining

```solidity
// Stake LP tokens برای rewards
await lpToken.stakeLPTokens(amount);

// Claim mining rewards
await lpToken.claimRewards();

// ثبت trading volume (توسط pool)
await lpToken.recordTradingVolume(trader, volume);
```

### 3. Token Registry

```solidity
// Submit token for listing (با fee)
await tokenRegistry.submitToken{value: fee}(
    tokenAddress, logoUrl, description, website
);

// محاسبه listing fee با تخفیف
uint256 fee = await tokenRegistry.calculateListingFee(user);

// Approve token (admin only)
await tokenRegistry.approveToken(token, tier);
```

## 📊 Dashboard و Analytics

### LAXCE Token Metrics:
- Total Supply: 100M LAXCE max
- Current Locked: Real-time tracking
- Revenue Pool: مقدار ETH برای توزیع
- Average Lock Duration: آمار locks

### LP Token Metrics:
- Total Staked: LP tokens در حال stake
- Rewards Distributed: کل rewards پرداخت شده
- Trading Volume: حجم معاملات ثبت شده
- APR: سالانه return برای LPs

### Token Registry Metrics:
- Total Fees Collected: کل listing fees
- Approved Tokens: تعداد tokens تایید شده
- Pending Approvals: tokens در انتظار بررسی
- Fee Discounts Given: مقدار تخفیف‌های اعطا شده

## 🔐 Security Features

### LAXCE Token:
- ✅ ReentrancyGuard در همه functions حساس
- ✅ Access control برای admin functions
- ✅ Max supply limit enforcement
- ✅ Safe transfer mechanisms

### LP Token:
- ✅ onlyPool modifier برای pool-specific functions
- ✅ Safe reward transfer with balance checks
- ✅ Proper fee calculation و handling
- ✅ Anti-gaming mechanisms

### Token Registry:
- ✅ Safe token metadata retrieval
- ✅ ETH transfer safety
- ✅ Admin-only critical functions
- ✅ Input validation و sanitization

## 🎯 Revenue Model خلاصه:

| منبع | مقدار | مخاطب |
|------|--------|--------|
| **Listing Fee** | 0.1 ETH (تا 90% تخفیف) | پروژه‌های token جدید |
| **Withdraw Fee** | 0.5% (کاهشی بر اساس زمان) | LPs با برداشت زودهنگام |
| **LP Mining** | قابل تنظیم per-block | Liquidity Providers |
| **Trading Mining** | 2x multiplier | Active Traders |
| **Revenue Share** | بر اساس locked LAXCE | LAXCE Holders |
| **Fee Discounts** | تا 50% تخفیف | LAXCE Holders |

## 📋 Integration با Flutter

Token Layer آماده اتصال به `dex_screen.dart` است:

```dart
// در Flutter app
class DexContractService {
  Future<double> getUserFeeDiscount(String userAddress) async {
    // فراخوانی calculateFeeDiscount
  }
  
  Future<double> getClaimableRevenue(String userAddress) async {
    // فراخوانی calculateClaimableRevenue
  }
  
  Future<void> stakeLPTokens(double amount) async {
    // فراخوانی stakeLPTokens
  }
}
```

## 🚀 Next Steps

**Token Layer کامل است!** اکنون می‌توانیم به سراغ **Pool Layer (Layer 3)** برویم:

1. **Pool Management** - ایجاد و مدیریت pools
2. **Pool Factory** - تولید خودکار pools
3. **Pool Pairs** - مدیریت جفت توکن‌ها
4. **Integration** - اتصال LP Tokens به pools واقعی

---

**🔥 Token Layer production-ready است و تمام ویژگی‌های Revenue & Incentives را شامل می‌شود!**

### Commands آماده:

```bash
# تست Token Layer
npm run test:token

# Deploy Token Layer
npm run deploy:token:testnet

# Deploy همه (Core + Token)
npm run deploy:testnet
``` 