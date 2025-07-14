# پیاده‌سازی منطق کیف پول انتخاب شده (Selected Wallet Logic)

## خلاصه تغییرات

این پیاده‌سازی منطق انتخاب کیف پول را مطابق با نسخه Kotlin پیاده‌سازی می‌کند تا کاربر بتواند بین کیف پول‌های مختلف جابه‌جا شود و تمام اپلیکیشن از کیف پول انتخاب شده استفاده کند.

## تغییرات اصلی

### 1. SecureStorage Updates

#### متدهای جدید:
- `saveSelectedWallet(String walletName, String userId)` - ذخیره کیف پول و userId با هم
- `getUserIdForSelectedWallet()` - دریافت userId برای کیف پول انتخاب شده
- `getSelectedWalletInfo()` - دریافت اطلاعات کامل کیف پول انتخاب شده

#### تغییرات موجود:
- `getUserId()` - حالا از `getUserIdForSelectedWallet()` استفاده می‌کند

### 2. AppProvider Updates

#### متدهای بهبود یافته:
- `selectWallet(String walletName)` - انتخاب کیف پول با اطلاع‌رسانی به سایر Provider ها
- `_notifyWalletChange()` - اطلاع‌رسانی تغییر کیف پول

### 3. Screen Updates

#### WalletsScreen:
- `_saveSelectedWallet()` - ذخیره کیف پول انتخاب شده مطابق با Kotlin
- به‌روزرسانی AppProvider هنگام انتخاب کیف پول

#### HomeScreen:
- `_loadSelectedWallet()` - بارگذاری کیف پول انتخاب شده در ابتدای صفحه
- انتخاب اولین کیف پول موجود در صورت عدم وجود کیف پول انتخاب شده

#### SendScreen:
- `_loadSelectedWallet()` - بارگذاری کیف پول انتخاب شده
- استفاده از SecureStorage برای دریافت اطلاعات کیف پول

#### ReceiveScreen:
- بهبود `_initUserAndLoadTokens()` - استفاده از منطق جدید انتخاب کیف پول
- Fallback به اولین کیف پول موجود

## نحوه کارکرد

### 1. انتخاب کیف پول در صفحه Wallets

```dart
void _saveSelectedWallet(String walletName, String userId) async {
  // ذخیره در SecureStorage
  await SecureStorage.instance.saveSelectedWallet(walletName, userId);
  
  // به‌روزرسانی AppProvider
  final appProvider = Provider.of<AppProvider>(context, listen: false);
  await appProvider.selectWallet(walletName);
}
```

### 2. بارگذاری کیف پول انتخاب شده در صفحات

```dart
Future<void> _loadSelectedWallet() async {
  final selectedWallet = await SecureStorage.instance.getSelectedWallet();
  final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
  
  if (selectedWallet != null && selectedUserId != null) {
    // استفاده از کیف پول انتخاب شده
    print('💰 Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
  } else {
    // Fallback به اولین کیف پول موجود
    final wallets = await SecureStorage.instance.getWalletsList();
    if (wallets.isNotEmpty) {
      final firstWallet = wallets.first;
      // انتخاب اولین کیف پول
    }
  }
}
```

### 3. استفاده در API Calls

```dart
// دریافت userId برای API calls
final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
if (userId != null) {
  // استفاده از userId در API calls
}
```

## مزایای این پیاده‌سازی

1. **سازگاری با Kotlin**: منطق دقیقاً مشابه نسخه Kotlin
2. **مدیریت متمرکز**: تمام اطلاعات کیف پول در SecureStorage ذخیره می‌شود
3. **Fallback منطقی**: در صورت عدم وجود کیف پول انتخاب شده، اولین کیف پول موجود انتخاب می‌شود
4. **اطلاع‌رسانی خودکار**: تغییر کیف پول به تمام Provider ها اطلاع داده می‌شود
5. **Debugging بهتر**: لاگ‌های مفصل برای ردیابی مشکلات

## تست کردن

### سناریوهای تست:

1. **ایجاد کیف پول جدید**: بررسی انتخاب خودکار کیف پول جدید
2. **تغییر کیف پول**: بررسی تغییر داده‌ها در تمام صفحات
3. **حذف کیف پول انتخاب شده**: بررسی انتخاب خودکار کیف پول دیگر
4. **Restart اپ**: بررسی حفظ کیف پول انتخاب شده

### لاگ‌های مفید:

```
💰 Selected wallet: MyWallet with userId: 12345
💰 Loaded selected wallet: MyWallet with userId: 12345
🔄 Notifying wallet change: MyWallet -> 12345
⚠️ No selected wallet found, using first available wallet
```

## نکات مهم

1. **Thread Safety**: تمام عملیات SecureStorage async هستند
2. **Error Handling**: تمام متدها try-catch دارند
3. **Performance**: کش کردن اطلاعات برای بهبود عملکرد
4. **Security**: استفاده از SecureStorage برای اطلاعات حساس

## آینده‌نگری

- اضافه کردن قابلیت Backup/Restore کیف پول انتخاب شده
- بهبود UI برای نمایش کیف پول انتخاب شده
- اضافه کردن قابلیت تغییر نام کیف پول
- بهبود مدیریت خطاها 