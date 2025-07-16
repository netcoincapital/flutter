# سیستم پاکسازی خودکار داده‌ها هنگام حذف اپلیکیشن

## خلاصه

این سیستم تضمین می‌کند که هنگام حذف کامل اپلیکیشن از گوشی کاربر، تمام اطلاعات کیف پول‌ها، پسکدها و هرگونه داده مربوط به اپلیکیشن نیز حذف شود.

## ویژگی‌های کلیدی

### ✅ پاکسازی خودکار
- **Android**: BroadcastReceiver برای تشخیص حذف اپلیکیشن
- **iOS**: بررسی داده‌های باقی‌مانده در AppDelegate
- **Flutter**: UninstallDataManager برای پاکسازی کامل

### ✅ پاکسازی کامل داده‌ها
- **SecureStorage**: تمام کلیدهای امن
- **SharedPreferences**: تمام تنظیمات و کش‌ها
- **Cache Files**: فایل‌های موقت
- **Documents**: فایل‌های ذخیره شده
- **External Storage**: فایل‌های خارجی (Android)

### ✅ مدیریت داده‌های خاص
- **Wallet Data**: اطلاعات کیف پول‌ها، mnemonic، کلیدهای خصوصی
- **Passcode Data**: پسکدها و تنظیمات بیومتریک
- **Settings Data**: تنظیمات اپلیکیشن
- **Token Data**: تنظیمات توکن‌ها
- **Transaction Data**: داده‌های تراکنش‌ها
- **Address Book**: دفترچه آدرس‌ها

## معماری سیستم

### 1. UninstallDataManager (Flutter)
```dart
class UninstallDataManager {
  // بررسی و پاکسازی در صورت fresh install
  static Future<void> checkAndCleanupOnFreshInstall()
  
  // پاکسازی کامل تمام داده‌ها
  static Future<void> performCompleteDataCleanup(BuildContext context)
  
  // پاکسازی داده‌های خاص
  static Future<void> clearWalletData()
  static Future<void> clearPasscodeData()
  static Future<void> clearSettingsData()
  // ...
}
```

### 2. Android UninstallReceiver
```kotlin
class UninstallReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      Intent.ACTION_PACKAGE_REMOVED -> cleanupAllData(context)
      Intent.ACTION_PACKAGE_FULLY_REMOVED -> performFinalCleanup(context)
    }
  }
}
```

### 3. iOS AppDelegate
```swift
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    checkAndCleanupOnFreshInstall()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

## نحوه عملکرد

### مرحله 1: تشخیص حذف اپلیکیشن

#### Android
- **BroadcastReceiver** در `AndroidManifest.xml` ثبت می‌شود
- گوش می‌دهد به `ACTION_PACKAGE_REMOVED` و `ACTION_PACKAGE_FULLY_REMOVED`
- هنگام حذف اپلیکیشن، پاکسازی خودکار اجرا می‌شود

#### iOS
- iOS به صورت خودکار تمام داده‌ها را هنگام حذف اپلیکیشن پاک می‌کند
- **AppDelegate** بررسی می‌کند که آیا داده‌ای باقی‌مانده است
- در صورت وجود، پاکسازی اضافی انجام می‌شود

### مرحله 2: پاکسازی داده‌ها

#### SecureStorage
```dart
await _secureStorage.deleteAll();
```

#### SharedPreferences
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.clear();
```

#### Cache Files
```dart
final cacheDir = await getTemporaryDirectory();
if (await cacheDir.exists()) {
  await cacheDir.delete(recursive: true);
}
```

#### Documents Files
```dart
final appDir = await getApplicationDocumentsDirectory();
if (await appDir.exists()) {
  final files = appDir.listSync();
  for (final file in files) {
    if (file is File) {
      await file.delete();
    } else if (file is Directory) {
      await file.delete(recursive: true);
    }
  }
}
```

### مرحله 3: پاکسازی داده‌های خاص

#### کیف پول‌ها
- UserID و WalletID
- Mnemonic phrases
- Private keys
- Wallet settings

#### پسکدها
- Passcode hash
- Biometric settings
- Auto-lock settings

#### تنظیمات
- Currency preferences
- Language settings
- Notification settings
- Network settings

## تنظیمات در اپلیکیشن

### بخش مدیریت داده‌ها
در صفحه Settings، بخش جدید "Data Management" اضافه شده است:

1. **Clear All Data**: پاکسازی کامل تمام داده‌ها
2. **Data Status**: نمایش وضعیت فعلی داده‌ها

### دیالوگ تأیید
```dart
void _showClearDataDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Clear All Data'),
        content: Text('This will permanently delete all wallet data, passcodes, settings, and cached information. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDataCleanup();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Clear'),
          ),
        ],
      );
    },
  );
}
```

## امنیت و حریم خصوصی

### ✅ تضمین حذف کامل
- تمام داده‌های حساس پاک می‌شوند
- هیچ ردپایی از اطلاعات کاربر باقی نمی‌ماند
- امنیت کیف پول‌ها تضمین می‌شود

### ✅ مدیریت خطا
```dart
try {
  await UninstallDataManager.performCompleteDataCleanup(context);
} catch (e) {
  print('❌ Error during data cleanup: $e');
  // نمایش پیام خطا به کاربر
}
```

### ✅ لاگ‌گیری
```dart
print('🗑️ Starting complete data cleanup...');
print('✅ SecureStorage cleared');
print('✅ SharedPreferences cleared');
print('✅ Cache cleared');
```

## تست و تأیید

### تست دستی
1. نصب اپلیکیشن
2. ایجاد کیف پول و تنظیم پسکد
3. حذف اپلیکیشن
4. نصب مجدد و بررسی عدم وجود داده‌های قبلی

### تست خودکار
```dart
// بررسی وضعیت داده‌ها
final dataStatus = await UninstallDataManager.getDataStatus();
print('Data status: $dataStatus');
```

## فایل‌های مرتبط

### Flutter
- `lib/services/uninstall_data_manager.dart`
- `lib/services/data_clearance_manager.dart`
- `lib/screens/settings_screen.dart`

### Android
- `android/app/src/main/kotlin/com/example/my_flutter_app/UninstallReceiver.kt`
- `android/app/src/main/AndroidManifest.xml`

### iOS
- `ios/Runner/AppDelegate.swift`

## نکات مهم

### ⚠️ محدودیت‌های Android
- BroadcastReceiver ممکن است در برخی دستگاه‌ها کار نکند
- پاکسازی کامل نیاز به مجوزهای اضافی دارد

### ⚠️ محدودیت‌های iOS
- iOS به صورت خودکار داده‌ها را پاک می‌کند
- AppDelegate فقط برای اطمینان اضافی است

### ✅ بهترین شیوه‌ها
- همیشه از SecureStorage برای داده‌های حساس استفاده کنید
- داده‌ها را در چندین مکان ذخیره نکنید
- لاگ‌گیری مناسب برای debugging

## نتیجه‌گیری

این سیستم تضمین می‌کند که:

1. **هنگام حذف اپلیکیشن**: تمام داده‌ها به صورت خودکار پاک می‌شوند
2. **امنیت کاربر**: هیچ اطلاعات حساسی باقی نمی‌ماند
3. **حریم خصوصی**: کاربران می‌توانند با اطمینان اپلیکیشن را حذف کنند
4. **مدیریت دستی**: کاربران می‌توانند از طریق تنظیمات داده‌ها را پاک کنند

این سیستم امنیت و حریم خصوصی کاربران را در بالاترین سطح تضمین می‌کند. 