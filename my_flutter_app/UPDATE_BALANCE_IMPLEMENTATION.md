# Update Balance API Implementation - Flutter مطابق با Kotlin

## 📋 خلاصه پیاده‌سازی

API `update-balance` اکنون دقیقاً مطابق با منطق Kotlin MainActivity.kt در Flutter پیاده‌سازی شده است.

## 🔧 **UpdateBalanceHelper** - کلاس کمکی

### فایل: `lib/services/update_balance_helper.dart`

```dart
class UpdateBalanceHelper {
  static const int maxRetries = 3; // مطابق با Kotlin
  static const Duration initialDelay = Duration(seconds: 5); // مطابق با Kotlin
  static const Duration apiTimeout = Duration(seconds: 10); // مطابق با Kotlin

  /// به‌روزرسانی موجودی با چک و retry logic (مطابق با Kotlin updateBalanceWithCheck)
  static Future<void> updateBalanceWithCheck(
    String userId, 
    Function(bool success) onResult,
  )

  /// تابع ساده برای به‌روزرسانی موجودی بدون callback
  static Future<bool> updateUserBalance(String userId)
}
```

**ویژگی‌های کلیدی:**
- ✅ 3 بار تلاش مجدد در صورت شکست
- ✅ تأخیر 5 ثانیه قبل از ارسال اولین درخواست
- ✅ timeout 10 ثانیه برای هر درخواست
- ✅ callback برای اطلاع از نتیجه
- ✅ منطق retry با افزایش تدریجی تأخیر

---

## 📍 **مکان‌های استفاده** (مطابق با Kotlin)

### 1. **CreateNewWalletScreen** ✅
**فایل:** `lib/screens/create_new_wallet_screen.dart`

**کاربرد:** بعد از ساخت موفقیت‌آمیز کیف پول جدید

```dart
// Kotlin equivalent: generateWallet() -> updateBalanceWithCheck()
final apiResults = await Future.wait([
  // 1. Call update-balance API مطابق با Kotlin
  Future<bool>(() async {
    final completer = Completer<bool>();
    UpdateBalanceHelper.updateBalanceWithCheck(response.userID!, (success) {
      updateBalanceSuccess = success;
      completer.complete(success);
    });
    return completer.future;
  }),
  
  // 2. Register device مطابق با Kotlin
  Future<bool>(() async {
    // Device registration logic
  }),
]);
```

### 2. **ImportWalletScreen** ✅
**فایل:** `lib/screens/import_wallet_screen.dart`

**کاربرد:** بعد از ایمپورت موفقیت‌آمیز کیف پول

```dart
// Kotlin equivalent: importWallet() -> updateBalanceWithCheck()
final apiResults = await Future.wait([
  // 1. Call update-balance API مطابق با Kotlin
  Future<bool>(() async {
    final completer = Completer<bool>();
    UpdateBalanceHelper.updateBalanceWithCheck(walletData.userID!, (success) {
      updateBalanceSuccess = success;
      completer.complete(success);
    });
    return completer.future;
  }),
  
  // 2. Register device مطابق با Kotlin
  Future<bool>(() async {
    // Device registration logic
  }),
]);
```

### 3. **InsideNewWalletScreen** ✅
**فایل:** `lib/screens/inside_new_wallet_screen.dart`

**کاربرد:** بعد از ساخت موفقیت‌آمیز کیف پول (نسخه inside)

```dart
// Kotlin equivalent: generateWallet() -> updateBalanceWithCheck()
UpdateBalanceHelper.updateBalanceWithCheck(response.userID!, (success) {
  updateBalanceSuccess = success;
});
```

### 4. **InsideImportWalletScreen** ✅
**فایل:** `lib/screens/inside_import_wallet_screen.dart`

**کاربرد:** بعد از ایمپورت موفقیت‌آمیز کیف پول (نسخه inside)

```dart
// Kotlin equivalent: importWallet() -> updateBalanceWithCheck()
UpdateBalanceHelper.updateBalanceWithCheck(response.data!.userID ?? '', (success) {
  updateBalanceSuccess = success;
});
```

---

## ⚡ **منطق هماهنگی APIها**

### مطابق با Kotlin CountDownLatch:

**Kotlin:**
```kotlin
val allApisDone = java.util.concurrent.CountDownLatch(2)

// Call update-balance API
updateBalanceWithCheck(context, userId) { success ->
    updateBalanceSuccess = success
    allApisDone.countDown()
}

// Call other API
// ...
allApisDone.countDown()

// Wait for both
allApisDone.await()
```

**Flutter:**
```dart
final apiResults = await Future.wait([
  // API 1: update-balance
  Future<bool>(() async {
    final completer = Completer<bool>();
    UpdateBalanceHelper.updateBalanceWithCheck(userId, (success) {
      completer.complete(success);
    });
    return completer.future;
  }),
  
  // API 2: device registration
  Future<bool>(() async {
    // Device registration
    return true;
  }),
]);

final allApisSuccessful = apiResults.every((result) => result == true);
```

---

## 🎯 **مقایسه با Kotlin**

| ویژگی | Kotlin MainActivity.kt | Flutter Implementation |
|--------|------------------------|----------------------|
| **Retry Count** | `maxRetries = 3` | ✅ `maxRetries = 3` |
| **Initial Delay** | `delay(5000)` | ✅ `Duration(seconds: 5)` |
| **API Timeout** | `10 seconds` | ✅ `Duration(seconds: 10)` |
| **Callback** | `onResult: (Boolean) -> Unit` | ✅ `Function(bool success)` |
| **Coordination** | `CountDownLatch` | ✅ `Future.wait` |
| **Error Handling** | Try-catch با retry | ✅ Try-catch با retry |
| **Logging** | Detailed logs | ✅ Detailed logs |

---

## 🚀 **نتیجه**

### ✅ **موفقیت‌های حاصل شده:**

1. **مطابقت کامل با Kotlin:** تمام ویژگی‌ها و منطق Kotlin پیاده‌سازی شده
2. **Retry Logic:** 3 بار تلاش مجدد با تأخیر افزایشی  
3. **Timeout Management:** مدیریت timeout 10 ثانیه‌ای
4. **Async Coordination:** هماهنگی بین APIها با Future.wait
5. **Error Handling:** مدیریت خطا و لاگ جامع
6. **Callback Support:** پشتیبانی از callback برای نتیجه

### 📊 **آمار استفاده:**

| صفحه | نوع عملیات | API های فراخوانی شده |
|------|-------------|----------------------|
| CreateNewWalletScreen | ساخت کیف پول | update-balance + device registration |
| ImportWalletScreen | ایمپورت کیف پول | update-balance + device registration |
| InsideNewWalletScreen | ساخت کیف پول | update-balance + device registration |
| InsideImportWalletScreen | ایمپورت کیف پول | update-balance |

### 🎯 **مطابقت با الگوی Kotlin:**

```
✅ Generate Wallet → updateBalanceWithCheck()
✅ Import Wallet → updateBalanceWithCheck()  
✅ 3 Retry attempts with exponential backoff
✅ 5-second initial delay
✅ 10-second timeout per request
✅ CountDownLatch equivalent coordination
✅ Comprehensive error handling and logging
```

🚀 **همه چیز آماده و مطابق با ساختار Kotlin!** 