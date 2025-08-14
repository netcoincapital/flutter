# Shared Libraries - کتابخانه‌های مشترک

## مسئولیت‌ها

این پوشه شامل کتابخانه‌های مشترک و توابع کمکی است که در چندین لایه استفاده می‌شوند:

## کتابخانه‌های اصلی

### 1. Math Libraries
- `FullMath.sol` - محاسبات ریاضی دقیق (mulDiv)
- `FixedPoint.sol` - اعداد اعشاری ثابت
- `SqrtPriceMath.sol` - محاسبات قیمت مربعی
- `TickMath.sol` - تبدیل tick به price و برعکس

### 2. Transfer Libraries
- `TransferHelper.sol` - انتقال امن توکن‌ها
- `SafeERC20.sol` - عملیات امن ERC20
- `CallbackValidation.sol` - اعتبارسنجی callback ها

### 3. Utility Libraries
- `Constants.sol` - ثابت‌های سیستم
- `Errors.sol` - کدهای خطای مشترک
- `Events.sol` - Event های مشترک
- `DataTypes.sol` - ساختارهای داده مشترک

### 4. Security Libraries
- `ReentrancyGuard.sol` - محافظت از reentrancy (یکی برای همه)
- `Pausable.sol` - قابلیت توقف اضطراری
- `AccessControlLib.sol` - توابع کمکی دسترسی

### 5. Price Libraries
- `PriceOracle.sol` - محاسبات قیمت
- `TWAPOracle.sol` - قیمت میانگین وزنی زمانی
- `PriceImpact.sol` - محاسبه تأثیر قیمت

## استفاده

```solidity
import "../libraries/FullMath.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/ReentrancyGuard.sol";

contract MyContract {
    using FullMath for uint256;
    
    function example() external {
        uint256 result = amount.mulDiv(price, 1e18);
        TransferHelper.safeTransfer(token, to, amount);
    }
}
```

## اصول طراحی

- **Pure Functions**: بیشتر توابع pure یا view هستند
- **Gas Optimized**: بهینه‌سازی شده برای کمترین مصرف gas
- **Reusable**: قابل استفاده در تمام لایه‌ها
- **Well-tested**: تست شده با coverage 100%
- **No Circular Imports**: جلوگیری از وابستگی دایره‌ای 