# Balance API Implementation - Flutter مطابق با Kotlin

## 📋 خلاصه تغییرات انجام شده

تمام استفاده‌های API `getBalance` در Flutter اکنون دقیقاً مطابق با منطق Kotlin پیاده‌سازی شده‌اند:

## 1. **CryptoDetailsScreen** 
### Kotlin: `crypto_details.kt`
```kotlin
val balanceResponse = api.getBalance(
    BalanceRequest(
        userId = userId.orEmpty(),
        currencyNames = listOf(tokenSymbol), // فقط یک توکن
        blockchain = emptyMap()
    )
)
```

### Flutter: `crypto_details_screen.dart` ✅
```dart
final response = await apiService.getBalance(
  userId,
  currencyNames: [widget.tokenSymbol], // فقط یک توکن مانند Kotlin
  blockchain: {},
);
```

**عملکرد:** دریافت و نمایش موجودی یک توکن خاص

---

## 2. **SendScreen**
### Kotlin: `send_screen.kt`
```kotlin
val request = BalanceRequest(
    userId = userId,
    currencyNames = emptyList(), // همه موجودی‌ها
    blockchain = emptyMap()
)
val response = api.getBalance(request)
// فیلتر کردن موجودی‌های مثبت
val positiveBalances = response.balances.filter { balanceItem -> 
    val balance = balanceItem.balance.toDoubleOrNull() ?: 0.0
    balance > 0.0
}
```

### Flutter: `send_screen.dart` ✅
```dart
final response = await apiService.getBalance(
  userId!,
  currencyNames: [], // خالی برای دریافت همه موجودی‌ها مانند Kotlin
  blockchain: {},
);

// فیلتر کردن موجودی‌های مثبت مطابق با Kotlin
for (final balanceItem in response.balances!) {
  final balance = double.tryParse(balanceItem.balance) ?? 0.0;
  if (balance > 0.0) {
    // فقط موجودی‌های مثبت مانند Kotlin send_screen.kt
  }
}
```

**عملکرد:** نمایش فقط توکن‌هایی که موجودی مثبت دارند برای ارسال

---

## 3. **TokenProvider** 
### Kotlin: `token_view_model.kt`
```kotlin
val response = api.getBalance(request)
// به‌روزرسانی موجودی‌های فعال
// مرتب‌سازی توکن‌ها بر اساس ارزش
```

### Flutter: `token_provider.dart` ✅
```dart
// fetchBalancesForActiveTokens method
final response = await apiService.getBalance(
  _userId,
  currencyNames: [], // خالی برای دریافت همه موجودی‌ها مانند Kotlin
  blockchain: {},
);

// مرتب‌سازی توکن‌ها بر اساس ارزش دلاری مانند Kotlin
final sortedTokens = sortTokensByDollarValue(_activeTokens);
_activeTokens = sortedTokens;
```

**عملکرد:** به‌روزرسانی موجودی‌های توکن‌های فعال و مرتب‌سازی

---

## 4. **HomeScreen**
### Kotlin: `Home.kt`
```kotlin
// تست مستقیم API برای دیباگ
val response = api.getBalance(request)
val request = BalanceRequest(
    userId = "0d32dfd0-f7ba-4d5a-a408-75e6c2961e23", // UserID ثابت
    currencyNames = emptyList(),
    blockchain = emptyMap()
)
```

### Flutter: `home_screen.dart` ✅
```dart
// تست API با double tap روی wallet name
Future<void> _testGetBalanceAPI() async {
  final response = await apiService.getBalance(
    userId,
    currencyNames: [], // خالی مانند Kotlin Home.kt
    blockchain: {},
  );
}
```

**عملکرد:** تست و دیباگ API (double tap روی نام کیف پول)

---

## 5. **Update Balance API** ✅
### استفاده در TokenProvider:
```dart
// updateBalance method
final response = await apiService.updateBalance(_userId);
// پردازش نتایج مانند getBalance
```

**عملکرد:** به‌روزرسانی موجودی با دکمه Refresh در Home

---

## 🔧 تغییرات کلیدی انجام شده:

### ✅ **اصلاح شده:**
1. **CryptoDetailsScreen**: اضافه شدن `_loadTokenBalance()` برای دریافت موجودی توکن خاص
2. **SendScreen**: تغییر از `getUserBalance` به `getBalance` + فیلتر موجودی‌های مثبت
3. **TokenProvider**: تغییر `fetchBalancesForActiveTokens()` برای استفاده از `getBalance`
4. **HomeScreen**: اضافه شدن تست API با double tap
5. **Import Screens**: حذف `getUserBalance` غیرضروری

### ❌ **حذف شده:**
- `_getBlockchainForToken()` method (اطلاعات blockchain از API می‌آید)
- فراخوانی‌های غیرضروری `getUserBalance` در import screens

### 🆕 **اضافه شده:**
- تست API در HomeScreen (double tap wallet name)
- Loading states برای balance fetching
- بهتر شدن error handling
- دقیق‌تر شدن logging برای debug

---

## 🎯 **نتیجه:**

اکنون تمام استفاده‌های API balance در Flutter دقیقاً مطابق با منطق و ساختار Kotlin پیاده‌سازی شده‌اند:

| صفحه/فایل | عملکرد | API استفاده شده | پارامترها |
|-----------|---------|-----------------|-----------|
| CryptoDetailsScreen | موجودی یک توکن | `getBalance` | currencyNames: [tokenSymbol] |
| SendScreen | موجودی‌های مثبت | `getBalance` | currencyNames: [] |
| TokenProvider | موجودی‌های فعال | `getBalance` | currencyNames: [] |
| HomeScreen | تست/دیباگ | `getBalance` | currencyNames: [] |
| HomeScreen Refresh | به‌روزرسانی | `updateBalance` | UserID |

🚀 **همه چیز آماده و مطابق با Kotlin!** 