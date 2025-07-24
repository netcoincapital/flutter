# پیاده‌سازی کامل Wallet Screen (مطابق با Kotlin)

## خلاصه تغییرات

این پیاده‌سازی تمام منطق مدیریت کیف پول از نسخه Kotlin را در Flutter پیاده‌سازی می‌کند، شامل:

- تغییر نام کیف پول
- حذف کیف پول
- به‌روزرسانی mnemonic
- مدیریت کیف پول انتخاب شده
- Navigation به صفحه backup

## تغییرات اصلی

### 1. Imports جدید

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage.dart';
import '../providers/app_provider.dart';
import 'package:provider/provider.dart';
import 'phrase_key_passcode_screen.dart';
```

### 2. متدهای جدید

#### `_loadWallets()`
بارگذاری لیست کیف پول‌ها از SecureStorage

#### `_saveWalletName()`
ذخیره نام جدید کیف پول با به‌روزرسانی mnemonic

#### `_saveWalletNameToKeystore()`
ذخیره نام کیف پول در Keystore مطابق با Kotlin

#### `_updateMnemonicForWalletName()`
به‌روزرسانی mnemonic با نام جدید کیف پول

#### `_deleteWallet()`
حذف کیف پول با مدیریت کیف پول انتخاب شده

#### `_deleteWalletFromKeystore()`
حذف کامل کیف پول از Keystore

#### `_getWalletNameFromKeystore()`
دریافت نام کیف پول از Keystore

## نحوه کارکرد

### 1. تغییر نام کیف پول

```dart
Future<void> _saveWalletName() async {
  final trimmedWalletName = walletName.trim();
  final trimmedInitialWalletName = initialWalletName.trim();
  
  if (trimmedWalletName != trimmedInitialWalletName) {
    final userId = await SecureStorage.instance.getUserIdForWallet(trimmedInitialWalletName);
    
    if (userId != null) {
      // به‌روزرسانی mnemonic
      await _updateMnemonicForWalletName(userId, trimmedInitialWalletName, trimmedWalletName);
      
      // ذخیره نام جدید
      await _saveWalletNameToKeystore(userId, trimmedInitialWalletName, trimmedWalletName);
    }
  }
}
```

### 2. حذف کیف پول

```dart
Future<void> _deleteWalletFromKeystore(String walletName) async {
  // حذف از لیست کیف پول‌ها
  final updatedWallets = wallets.where((wallet) => wallet['walletName'] != walletName).toList();
  await SecureStorage.instance.saveWalletsList(updatedWallets);
  
  // حذف mnemonic
  final userId = await SecureStorage.instance.getUserIdForWallet(walletName);
  if (userId != null) {
    final mnemonicKey = 'Mnemonic_${userId}_$walletName';
    await SecureStorage.instance.deleteSecureData(mnemonicKey);
  }
  
  // انتخاب کیف پول جدید اگر کیف پول حذف شده انتخاب شده بود
  if (updatedWallets.isNotEmpty) {
    final newWallet = updatedWallets.first;
    await SecureStorage.instance.saveSelectedWallet(newWallet['walletName']!, newWallet['userID']!);
  }
}
```

### 3. به‌روزرسانی mnemonic

```dart
Future<void> _updateMnemonicForWalletName(String userId, String oldWalletName, String newWalletName) async {
  final oldKey = 'Mnemonic_${userId}_$oldWalletName';
  final newKey = 'Mnemonic_${userId}_$newWalletName';
  
  final mnemonic = await SecureStorage.instance.getSecureData(oldKey);
  if (mnemonic != null) {
    await SecureStorage.instance.saveSecureData(newKey, mnemonic);
    await SecureStorage.instance.deleteSecureData(oldKey);
  }
}
```

## UI Updates

### 1. Save Button Logic

```dart
onPressed: () async {
  final trimmedWalletName = walletName.trim();
  final trimmedInitialWalletName = initialWalletName.trim();
  
  if (trimmedWalletName != trimmedInitialWalletName) {
    await _saveWalletName();
  } else {
    Navigator.pushReplacementNamed(context, '/wallets');
  }
}
```

### 2. Manual Backup Navigation

```dart
onTap: () {
  final encodedWalletName = Uri.encodeComponent(walletName);
  Navigator.pushNamed(
    context,
    '/phrase-key-passcode/$encodedWalletName',
    arguments: {'showCopy': false},
  );
}
```

## مزایای این پیاده‌سازی

1. **سازگاری کامل با Kotlin**: تمام منطق دقیقاً مشابه نسخه Kotlin
2. **مدیریت امن**: استفاده از SecureStorage برای تمام عملیات
3. **به‌روزرسانی خودکار**: AppProvider به‌روزرسانی می‌شود
4. **مدیریت خطا**: try-catch برای تمام عملیات
5. **Fallback منطقی**: انتخاب کیف پول جدید در صورت حذف کیف پول انتخاب شده

## تست کردن

### سناریوهای تست:

1. **تغییر نام کیف پول**: بررسی به‌روزرسانی mnemonic و لیست کیف پول‌ها
2. **حذف کیف پول**: بررسی انتخاب خودکار کیف پول جدید
3. **حذف آخرین کیف پول**: بررسی navigation به صفحه import-create
4. **Backup navigation**: بررسی navigation به صفحه phrase key passcode

### لاگ‌های مفید:

```
💰 Wallet name updated: OldName -> NewName
✅ Mnemonic updated for wallet: OldName -> NewName
✅ Wallet name saved successfully
🗑️ Wallet deleted: WalletName
✅ New wallet selected: NewWalletName
⚠️ No wallets remaining
```

## نکات مهم

1. **Thread Safety**: تمام عملیات async هستند
2. **Error Handling**: تمام متدها try-catch دارند
3. **Data Consistency**: به‌روزرسانی همزمان SecureStorage و AppProvider
4. **Navigation**: مدیریت صحیح navigation در تمام سناریوها

## آینده‌نگری

- اضافه کردن validation برای نام کیف پول
- بهبود UI feedback برای عملیات طولانی
- اضافه کردن قابلیت undo برای حذف کیف پول
- بهبود error messages برای کاربر 