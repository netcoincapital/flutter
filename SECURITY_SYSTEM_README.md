# Security System Implementation

این سیستم امنیتی جامع مطابق با درخواست کاربر پیاده‌سازی شده است و شامل سه قابلیت اصلی می‌باشد:

## 📋 ویژگی‌های اصلی

### 1. گزینه اول: Toggle Passcode
- **فعال/غیرفعال کردن passcode**: کاربر می‌تواند نمایش passcode را فعال یا غیرفعال کند
- **فعال**: اپلیکیشن همیشه صفحه passcode را نمایش می‌دهد
- **غیرفعال**: اپلیکیشن بدون نمایش passcode وارد صفحه home می‌شود

### 2. گزینه دوم: Auto-Lock
کاربر می‌تواند یکی از 5 گزینه زیر را انتخاب کند:
- **Immediate**: فوری
- **1 Min**: 1 دقیقه
- **5 Min**: 5 دقیقه
- **10 Min**: 10 دقیقه
- **15 Min**: 15 دقیقه

### 3. گزینه سوم: Lock Method
سه حالت مختلف برای روش قفل:
- **Passcode/Biometric (توصیه شده)**: هم با passcode و هم با biometric
- **Passcode Only**: فقط با passcode
- **Biometric Only**: فقط با biometric

## 🏗️ Architecture

### کلاس‌های اصلی:

1. **SecuritySettingsManager**: مدیریت تنظیمات امنیتی
2. **SecurityScreen**: صفحه تنظیمات امنیتی
3. **PasscodeScreen**: صفحه passcode بهبود یافته
4. **Main App**: lifecycle management

### Enums:
- `AutoLockDuration`: مدت‌های زمانی auto-lock
- `LockMethod`: روش‌های قفل

## 🔧 نحوه استفاده

### 1. تنظیم پایه

```dart
final securityManager = SecuritySettingsManager.instance;

// فعال کردن passcode
await securityManager.setPasscodeEnabled(true);

// تنظیم auto-lock
await securityManager.setAutoLockDuration(AutoLockDuration.fiveMinutes);

// تنظیم lock method
await securityManager.setLockMethod(LockMethod.passcodeAndBiometric);
```

### 2. Lifecycle Management

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    securityManager.saveLastBackgroundTime();
  } else if (state == AppLifecycleState.resumed) {
    final shouldShow = await securityManager.shouldShowPasscodeAfterBackground();
    if (shouldShow) {
      // نمایش passcode screen
    }
  }
}
```

### 3. بررسی تنظیمات

```dart
// خلاصه تنظیمات
final summary = await securityManager.getSecuritySettingsSummary();
print('Passcode Enabled: ${summary['passcodeEnabled']}');
print('Auto-lock: ${summary['autoLockDurationText']}');
print('Lock Method: ${summary['lockMethodText']}');
```

## 📱 UI Components

### SecurityScreen
- Toggle برای passcode
- انتخاب auto-lock duration
- انتخاب lock method
- نمایش وضعیت biometric

### PasscodeScreen
- پشتیبانی از biometric
- سازگاری با lock methods مختلف
- نمایش روش‌های احراز هویت موجود

## 🔒 Security Features

### Data Storage
- تنظیمات در SharedPreferences
- Passcode hash امن
- Background time tracking

### Biometric Integration
- تشخیص خودکار در دسترس بودن
- پشتیبانی از انواع مختلف biometric
- Fallback به passcode

### Auto-Lock Logic
- محاسبه دقیق زمان background
- تنظیمات قابل تغییر
- Immediate lock option

## 🧪 Testing

فایل `security_demo.dart` برای تست و نمایش استفاده:

```dart
// اجرای تست کامل
await SecurityDemo.runCompleteDemo();

// تست biometric
await SecurityDemo.demonstrateAuthentication();

// تست lifecycle
await SecurityDemo.demonstrateLifecycleHandling();
```

## 📋 Navigation

### Routes اضافه شده:
- `/security`: صفحه تنظیمات امنیتی
- `/enter-passcode`: صفحه ورود passcode

### از Settings Screen:
```dart
Navigator.pushNamed(context, '/security');
```

## ⚠️ نکات مهم

1. **Biometric Availability**: همیشه بررسی کنید که biometric در دسترس است
2. **Passcode Verification**: از PasscodeManager برای verify استفاده کنید
3. **Background Handling**: زمان background را ذخیره کنید
4. **UI Updates**: بعد از تغییر تنظیمات، UI را refresh کنید

## 🔄 Future Enhancements

- پشتیبانی از PIN patterns
- تنظیمات اضافی برای lockout
- Analytics برای security events
- Integration با server-side security

---

**نکته**: این سیستم طراحی شده تا در عملکرد کلی پروژه تداخلی ایجاد نکند و به راحتی قابل استفاده باشد. 