# 🎉 Core Layer (Layer 1) - آماده و قابل استفاده!

## خلاصه

**لایه Core با موفقیت تکمیل شد** و شامل موارد زیر است:

### ✅ Contracts آماده شده:
1. **AccessControl.sol** - مدیریت نقش‌ها و دسترسی‌ها
2. **ReentrancyGuard.sol** - محافظت از reentrancy attacks (Libraries)
3. **Constants.sol** - ثابت‌های سیستم (Libraries)
4. **ILaxceCore.sol** - Interface های اصلی

### ✅ ویژگی‌های پیاده‌سازی شده:
- ✅ Role-based access control
- ✅ Hierarchical role management
- ✅ Owner → Admin → Operator hierarchy
- ✅ Emergency و Upgrader roles
- ✅ Shared security libraries
- ✅ Gas-optimized implementations

## 🧪 تست کردن

```bash
# نصب dependencies
npm install

# Compile contracts
npm run compile

# اجرای تست‌های Core Layer
npm run test:core

# اجرای همه تست‌ها
npm test

# Coverage report
npm run coverage
```

## 🚀 Deployment

### Local Development
```bash
# راه‌اندازی local node
npm run node

# Deploy به local network (در terminal جدید)
npm run deploy:core
```

### Testnet Deployment
```bash
# تنظیم .env file
cp env.example .env
# ویرایش PRIVATE_KEY, SEPOLIA_RPC_URL

# Deploy به Sepolia testnet
npm run deploy:core:testnet
```

## 💻 استفاده در کد

### نحوه import
```solidity
// استفاده از AccessControl
import "./01-core/AccessControl.sol";

// استفاده از کتابخانه‌ها
import "./libraries/ReentrancyGuard.sol";
import "./libraries/Constants.sol";

contract MyContract is AccessControl, ReentrancyGuard {
    constructor(address owner) AccessControl(owner) {}
    
    function sensitiveFunction() 
        external 
        onlyAdmin 
        nonReentrant 
    {
        // کد ایمن شما
    }
}
```

### مدیریت نقش‌ها
```solidity
// چک کردن نقش
bool isAdmin = accessControl.hasRole(ADMIN_ROLE, user);

// اعطای نقش (فقط توسط owner)
accessControl.grantRole(ADMIN_ROLE, newAdmin);

// لغو نقش
accessControl.revokeRole(ADMIN_ROLE, oldAdmin);
```

## 🔐 Security Features

### 1. Role-based Access Control
- **OWNER_ROLE**: حداکثر دسترسی، مدیریت admins
- **ADMIN_ROLE**: مدیریت عملیات روزانه
- **OPERATOR_ROLE**: عملیات محدود
- **PAUSER_ROLE**: قابلیت pause/unpause
- **UPGRADER_ROLE**: ارتقاء contracts
- **EMERGENCY_ROLE**: عملیات اضطراری

### 2. Reentrancy Protection
```solidity
function swap() external nonReentrant {
    // محافظت شده از reentrancy attacks
}
```

### 3. Constants Library
```solidity
// استفاده از ثابت‌های سیستم
require(fee <= Constants.MAX_FEE_BPS, Constants.SLIPPAGE_TOO_HIGH);
```

## 📊 Gas Optimization

- ✅ **Packed storage**: حداقل storage slots
- ✅ **Efficient mapping structures**
- ✅ **No duplicate event emissions**
- ✅ **Optimized role checking**

## 🧩 Integration با سایر لایه‌ها

### برای Layer 2 (Token):
```solidity
import "../01-core/AccessControl.sol";

contract TokenRegistry is AccessControl {
    constructor(address owner) AccessControl(owner) {}
    
    function addToken(address token) external onlyAdmin {
        // اضافه کردن توکن جدید
    }
}
```

### برای Layer 3 (Pool):
```solidity
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Constants.sol";

contract Pool is ReentrancyGuard {
    function addLiquidity() external nonReentrant {
        require(amount > 0, Constants.ZERO_AMOUNT);
        // منطق pool
    }
}
```

## 🎯 آماده برای Layer 2

Core Layer آماده است! اکنون می‌توانیم به سراغ **Token Layer (Layer 2)** برویم که شامل:
- ERC20 Token standard
- LP Token management  
- Position NFT (Uniswap V3 style)
- Token Registry
- Token Factory

## 📋 Next Steps

1. **Token Layer**: ERC20, LP tokens, Position NFTs
2. **Pool Layer**: Pool management و factory
3. **Integration Testing**: تست یکپارچگی لایه‌ها
4. **Frontend Integration**: اتصال به Flutter app

---

**🔥 Core Layer production-ready است و می‌تواند به عنوان foundation برای بقیه سیستم استفاده شود!** 