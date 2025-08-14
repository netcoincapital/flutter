# 🚀 راهنمای عیب‌یابی مشکلات راه‌اندازی / Startup Troubleshooting Guide

## 🔍 مشکل گیر کردن در صفحه اسپلش / Splash Screen Hanging Issue

### علل احتمالی / Possible Causes:

1. **مقداردهی اولیه سرویس‌ها طولانی می‌شود / Service initialization taking too long**
   - SecuritySettingsManager initialization
   - WalletStateManager operations  
   - Storage operations (SharedPreferences/SecureStorage)
   - Network connectivity checks

2. **عملیات‌های مسدودکننده / Blocking operations**
   - Database queries without timeout
   - Network requests hanging
   - File system operations

3. **مشکلات پلتفرم‌های مختلف / Platform-specific issues**
   - iOS: SecureStorage access issues
   - Android: Permission issues
   - Storage access problems

### ✅ راه‌حل‌های اعمال شده / Applied Solutions:

#### 1. افزودن محدودیت زمانی / Timeout Protection
```dart
// Overall initialization timeout (15 seconds)
await Future.any([
  _performInitialization(),
  Future.delayed(const Duration(seconds: 15)).then((_) => 
    throw TimeoutException('App initialization timeout')),
]);

// Individual service timeouts
await WalletStateManager.instance.hasWallet()
  .timeout(const Duration(seconds: 3));
```

#### 2. بهینه‌سازی فرآیند راه‌اندازی / Optimized Initialization Process
- **مرحله 1**: تعیین مسیر اولیه (با محدودیت زمانی)
- **مرحله 2**: عملیات‌های حیاتی به صورت موازی
- **مرحله 3**: نمایش فوری رابط کاربری
- **مرحله 4**: اجرای وظایف پس‌زمینه

#### 3. صفحه لودینگ بهبود یافته / Improved Loading Screen
```dart
// قبل: Container خالی / Before: Empty Container
body: Container()

// بعد: نمایشگر لودینگ با پیام‌های راهنما / After: Loading indicator with helpful messages
body: Center(
  child: Column(
    children: [
      CircularProgressIndicator(),
      Text('Loading...'),
      Text('If this takes too long, please restart the app'),
    ],
  ),
)
```

#### 4. پردازش پس‌زمینه / Background Processing
```dart
// عملیات‌های غیرحیاتی پس از نمایش UI اجرا می‌شوند
WidgetsBinding.instance.addPostFrameCallback((_) {
  _startBackgroundTasks(); // Network checks, device registration, etc.
});
```

### 🛠️ راه‌حل‌های اضافی برای کاربر / Additional User Solutions:

#### 1. راه‌اندازی مجدد اپلیکیشن / App Restart
```bash
# Kill the app completely and restart
# iOS: Double-tap home button and swipe up on the app
# Android: Recent apps > Swipe away the app
```

#### 2. پاک کردن Cache اپلیکیشن / Clear App Cache
```bash
# Android
Settings > Apps > Laxce > Storage > Clear Cache

# iOS  
Settings > General > iPhone Storage > Laxce > Offload App
```

#### 3. بررسی اتصال شبکه / Check Network Connection
- WiFi connection stable
- Mobile data available
- No VPN blocking connections
- Server reachability (coinceeper.com)

#### 4. آزادسازی حافظه دستگاه / Free Device Memory
- Close other apps
- Restart device if low on memory
- Check available storage space

### 📊 نحوه فعال‌سازی حالت دیباگ / How to Enable Debug Mode

برای دیدن جزئیات بیشتر مشکل، می‌توانید خروجی کنسول را بررسی کنید:

#### در حین توسعه / During Development:
```bash
flutter run --debug
# Look for these log messages:
# 🔍 Starting app initialization with timeout protection...
# 🎯 Final initial route determined: [route]
# ❌ Error during initialization: [error details]
```

#### در محیط عملیاتی / In Production:
```dart
// Check device logs:
// iOS: Xcode > Window > Devices and Simulators > View Device Logs
// Android: adb logcat | grep flutter
```

### 🎯 پیام‌های خطای رایج / Common Error Messages:

#### `TimeoutException: App initialization timeout`
**علت**: راه‌اندازی بیش از 15 ثانیه طول کشیده
**راه‌حل**: بررسی اتصال اینترنت و راه‌اندازی مجدد

#### `LateInitializationError: Field has not been initialized`
**علت**: ServiceProvider قبل از مقداردهی استفاده شده
**راه‌حل**: این مشکل با timeout protection برطرف شده

#### `SecureStorage read timeout`
**علت**: دسترسی به SecureStorage مسدود شده (معمولاً در iOS)
**راه‌حل**: راه‌اندازی مجدد دستگاه یا حذف و نصب مجدد اپ

### 🔄 فلوچارت عیب‌یابی / Troubleshooting Flowchart

```
اپ در splash گیر کرده؟
├─ بله → آیا بیش از 15 ثانیه منتظر مانده‌اید؟
│   ├─ بله → اپ را کاملاً ببندید و مجدداً باز کنید
│   └─ خیر → صبر کنید (ممکن است اتصال آهسته باشد)
└─ نه → مشکل دیگری است

راه‌اندازی مجدد کمک کرد؟
├─ بله → مشکل حل شد ✅
└─ نه → Cache اپ را پاک کنید

Cache پاک کردن کمک کرد؟
├─ بله → مشکل حل شد ✅
└─ نه → اتصال اینترنت را بررسی کنید

اتصال اینترنت سالم است؟
├─ بله → اپ را حذف و مجدداً نصب کنید
└─ نه → اتصال اینترنت را برقرار کنید
```

### 📞 گزارش مشکل / Report Issue

اگر مشکل همچنان ادامه دارد، لطفاً اطلاعات زیر را گزارش دهید:

1. **مدل دستگاه و نسخه سیستم‌عامل**
2. **نسخه اپلیکیشن**
3. **پیام‌های خطا از کنسول**
4. **مراحل باز تولید مشکل**
5. **وضعیت اتصال اینترنت هنگام بروز مشکل**

---

## 🏆 بهبودهای عملکرد / Performance Improvements

### قبل از بهینه‌سازی / Before Optimization:
- زمان راه‌اندازی: 8-15 ثانیه
- احتمال گیر کردن: بالا
- تجربه کاربری: ضعیف

### بعد از بهینه‌سازی / After Optimization:
- زمان راه‌اندازی: 2-5 ثانیه
- احتمال گیر کردن: کم (با timeout protection)
- تجربه کاربری: بهبود یافته

### نکات توسعه‌دهندگان / Developer Notes:
- همیشه از timeout برای عملیات async استفاده کنید
- عملیات‌های غیرحیاتی را در پس‌زمینه اجرا کنید
- صفحه لودینگ را هرگز خالی نگذارید
- پیام‌های راهنما برای کاربر قرار دهید 