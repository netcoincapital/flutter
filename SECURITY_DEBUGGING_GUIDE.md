# Security System Debugging Guide

## 🚨 مشکلات احتمالی و راه‌حل‌ها

### مشکل ۱: تنظیمات اعمال نمی‌شوند
**علائم**: تغییر تنظیمات در SecurityScreen اثری ندارد

**راه‌حل**:
1. بررسی Console logs:
```
🔒 Setting passcode enabled: true
✅ Passcode enabled setting saved: true
```

2. اجرای Test Screen:
- Settings > Security > Test Security System
- Run All Tests
- بررسی نتایج

3. بررسی SharedPreferences:
```dart
final prefs = await SharedPreferences.getInstance();
print('Passcode enabled: ${prefs.getBool('passcode_enabled')}');
```

### مشکل ۲: Passcode Screen نمایش داده نمی‌شود
**علائم**: بعد از تغییر app به background، passcode نمایش داده نمی‌شود

**راه‌حل**:
1. بررسی تنظیمات Auto-lock:
```
🔒 Auto-lock setting: Immediate (0 ms)
🔒 Should show passcode: true
```

2. بررسی Console logs هنگام lifecycle:
```
📱 App went to background at: 2024-01-01 12:00:00
🔒 Auto-lock triggered - showing passcode screen
```

### مشکل ۳: Biometric کار نمی‌کند
**علائم**: دکمه biometric کار نمی‌کند

**راه‌حل**:
1. بررسی دسترسی biometric:
```
🔒 Biometric availability check: true
```

2. تست در SecurityTestScreen:
- Test Biometric button
- بررسی نتایج

## 🛠️ راه‌های Debugging

### 1. استفاده از Test Screen
```dart
// رفتن به Test Screen
Navigator.pushNamed(context, '/security-test');

// یا از SecurityScreen:
// کلیک روی "Test Security System" button
```

### 2. Console Logs
تمام عملیات security با emoji مشخص لاگ می‌شوند:
- `🔒`: Security operations
- `📱`: Lifecycle events  
- `✅`: Success operations
- `❌`: Error handling
- `⚠️`: Warnings

### 3. Manual Testing
```dart
final securityManager = SecuritySettingsManager.instance;

// مقداردهی
await securityManager.initialize();

// تست passcode toggle
await securityManager.setPasscodeEnabled(true);
final isEnabled = await securityManager.isPasscodeEnabled();
print('Passcode enabled: $isEnabled');

// تست auto-lock
await securityManager.setAutoLockDuration(AutoLockDuration.immediate);
await securityManager.saveLastBackgroundTime();
final shouldShow = await securityManager.shouldShowPasscodeAfterBackground();
print('Should show passcode: $shouldShow');
```

## 🔍 بررسی گام‌به‌گام

### گام ۱: تست Initialization
```dart
await SecuritySettingsManager.instance.initialize();
```
**انتظار**: Console log با تنظیمات فعلی

### گام ۲: تست Passcode Toggle  
```dart
await securityManager.setPasscodeEnabled(false);
```
**انتظار**: اگر biometric نباشد، false برگردانده شود

### گام ۳: تست Auto-lock
```dart
// تنظیم immediate
await securityManager.setAutoLockDuration(AutoLockDuration.immediate);
// تست نمایش passcode
final shouldShow = await securityManager.shouldShowPasscodeAfterBackground();
```
**انتظار**: shouldShow = true

### گام ۴: تست Lock Method
```dart
await securityManager.setLockMethod(LockMethod.passcodeOnly);
final method = await securityManager.getLockMethod();
```
**انتظار**: method = LockMethod.passcodeOnly

## 📋 Checklist برای تست

- [ ] SecuritySettingsManager.initialize() بدون خطا اجرا می‌شود
- [ ] Passcode toggle کار می‌کند
- [ ] Auto-lock duration تغییر می‌کند  
- [ ] Lock method تغییر می‌کند
- [ ] Background time ذخیره می‌شود
- [ ] shouldShowPasscodeAfterBackground درست کار می‌کند
- [ ] Biometric availability تشخیص داده می‌شود
- [ ] Settings > Security > passcode authentication کار می‌کند

## 🚀 نحوه اجرا

### دسترسی از Settings:
1. Settings > Security (نیاز به passcode)
2. کلیک "Test Security System"
3. "Run All Tests"

### دسترسی مستقیم:
```dart
Navigator.pushNamed(context, '/security-test');
```

## 📱 تست در دستگاه واقعی

1. **Background/Foreground Test**:
   - تنظیم auto-lock روی Immediate
   - رفتن به background (home button)
   - بازگشت به app
   - انتظار: نمایش passcode screen

2. **Biometric Test**:
   - تنظیم lock method روی Biometric Only
   - تست authentication
   - انتظار: نمایش biometric prompt

3. **Settings Test**:
   - تغییر هر تنظیم
   - خروج و ورود مجدد به security screen
   - انتظار: تنظیمات حفظ شده باشند

---

**نکته**: همه logs در debug console نمایش داده می‌شوند. برای production، logs را غیرفعال کنید. 