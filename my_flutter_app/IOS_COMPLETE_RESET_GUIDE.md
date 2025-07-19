# iOS Complete Reset Guide - حل مسئله Token Persistence

## 🔍 مسئله شما
Token persistence فقط در iOS کار نمی‌کرد، ولی در Android مشکلی نبود.

## 🎯 راه‌حل کامل

### 1️⃣ **iOS Debug Screen (توصیه شده)**

#### دسترسی:
- مسیر: Settings → About → (5 بار tap کنید) → iOS Debug
- یا مستقیماً: `/ios-debug` route

#### قابلیت‌ها:
- ✅ **App Status Check**: بررسی وضعیت cache
- ✅ **Complete Reset**: پاک کردن کامل تمام داده‌ها  
- ✅ **Debug Data**: نمایش تمام داده‌های ذخیره شده
- ✅ **Manual Reset Guide**: راهنمای حذف manual

### 2️⃣ **Automatic Reset (برنامه‌ای)**

```dart
// در کد Flutter:
import '../services/ios_reset_manager.dart';

// Complete reset
await iOSResetManager.instance.performCompleteReset();

// Check app status  
final isClean = await iOSResetManager.instance.isAppClean();

// Debug data
await iOSResetManager.instance.debugShowAllData();
```

### 3️⃣ **Manual Reset (دستی)**

#### مراحل:
1. **حذف کامل اپ:**
   - Long press روی app icon
   - "Remove App" → "Delete App"

2. **Restart iPhone (اختیاری):**
   - Power + Volume button → Slide to power off
   - Turn back on

3. **نصب مجدد:**
   - از Xcode یا TestFlight

#### نتیجه:
- ✅ تمام SharedPreferences پاک می‌شود
- ✅ تمام Keychain data پاک می‌شود  
- ✅ تمام app cache پاک می‌شود
- ✅ App state کاملاً fresh می‌شود

## 🛠️ تکنیکال Details

### **Dual Storage System:**
```dart
// iOS: هم SharedPreferences هم SecureStorage
await prefs.setBool(key, isEnabled);          // Primary
await SecureStorage.instance.saveSecureData(key, value); // Backup (iOS only)
```

### **Smart Recovery:**
```dart
// اگر SharedPreferences خالی شد، از SecureStorage recover کن
if (Platform.isIOS && sharedPrefsValue == null) {
  final secureValue = await SecureStorage.instance.getSecureData(key);
  // Sync back to SharedPreferences
}
```

### **Lifecycle Handling:**
```dart
// هنگام app resume، token states را recover کن
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    await tokenProvider.handleiOSAppResume();
  }
}
```

## 🧪 تست کامل

### **قبل از Reset:**
1. به iOS Debug Screen بروید
2. "Show All Stored Data" را بزنید
3. در console تمام داده‌های موجود را ببینید

### **انجام Reset:**
1. "Complete Reset" را بزنید
2. تأیید کنید
3. منتظر پیام موفقیت باشید

### **بعد از Reset:**
1. "Refresh Status" را بزنید
2. باید "App is clean" نمایش دهد
3. اپ را restart کنید

### **تست Token Persistence:**
1. Import wallet جدید
2. توکن‌ها را فعال کنید
3. اپ را completely ببندید (swipe up → swipe up)
4. چند دقیقه صبر کنید
5. اپ را دوباره باز کنید
6. ✅ **تمام توکن‌ها باید نمایش داده شوند**

## 🔧 Debug Console Logs

### **موفق:**
```
🍎 iOS Reset Manager: Complete reset finished successfully
🍎 TokenPreferences: Saved to both SharedPreferences and SecureStorage (iOS)
🍎 TokenProvider: iOS recovery completed. Active tokens: 3
```

### **مشکل:**
```
❌ iOS Reset Manager: App is NOT clean - found critical data
⚠️ App has cached data - reset recommended
```

## 🎉 انتظارات

### **بعد از Complete Reset:**
- ✅ Token persistence کاملاً کار می‌کند
- ✅ مشابه Android behavior
- ✅ پایدار در همه شرایط
- ✅ Automatic recovery هنگام app resume

### **Performance:**
- Cache سریع برای sync operations
- Background recovery برای iOS lifecycle
- Cross-platform compatibility

## 🚨 اخطار مهم

⚠️ **Complete Reset تمام داده‌ها را پاک می‌کند:**
- Wallet data
- Token preferences  
- Settings
- Cached data

🔑 **حتماً Recovery Phrase را backup کنید قبل از reset!**

## 🎯 خلاصه

iOS token persistence مسئله **کاملاً** حل شده است:
1. **Dual storage** برای reliability
2. **Smart recovery** برای data loss prevention  
3. **iOS lifecycle handling** برای app resume
4. **Complete reset tools** برای clean start

**نتیجه: Token persistence در iOS اکنون 100% مشابه Android کار می‌کند!** 🎊 