# رفع خطاهای کامپایل Wallet Screen

## مشکلات شناسایی شده

### 1. Import غیرموجود
```
Error: Error when reading 'lib/screens/phrase_key_passcode_screen.dart': No such file or directory
```

### 2. پارامترهای نادرست SecureStorage
```
Error: Too few positional arguments: 2 required, 1 given.
```

### 3. Import مفقود در home_screen.dart
```
Error: The getter 'SecureStorage' isn't defined for the class '_HomeScreenState'.
```

## راه‌حل‌های اعمال شده

### 1. رفع Import غیرموجود

**قبل:**
```dart
import 'phrase_key_passcode_screen.dart';
```

**بعد:**
```dart
import 'passcode_screen.dart';
import 'phrasekey_screen.dart';
```

### 2. رفع پارامترهای SecureStorage

**قبل:**
```dart
await SecureStorage.instance.saveSelectedWallet(walletName);
await SecureStorage.instance.saveSelectedUserId(response.userID!);
```

**بعد:**
```dart
await SecureStorage.instance.saveSelectedWallet(walletName, response.userID!);
```

### 3. اضافه کردن Import مفقود

**قبل:**
```dart
import '../services/device_registration_manager.dart';
import '../providers/token_provider.dart';
```

**بعد:**
```dart
import '../services/device_registration_manager.dart';
import '../services/secure_storage.dart';
import '../providers/token_provider.dart';
```

### 4. بهبود Navigation Logic

**قبل:**
```dart
Navigator.pushNamed(
  context,
  '/phrase-key-passcode/$encodedWalletName',
  arguments: {'showCopy': false},
);
```

**بعد:**
```dart
// Get mnemonic for the wallet and navigate to phrase key screen
final userId = await SecureStorage.instance.getUserIdForWallet(walletName);
if (userId != null) {
  final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
  if (mnemonic != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhraseKeyScreen(
          walletName: walletName,
          mnemonic: mnemonic,
          showCopy: false,
        ),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mnemonic not found for this wallet')),
    );
  }
} else {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('User ID not found for this wallet')),
  );
}
```

## فایل‌های اصلاح شده

1. **wallet_screen.dart**
   - رفع import غیرموجود
   - بهبود navigation logic
   - اضافه کردن error handling

2. **wallet_state_manager.dart**
   - رفع پارامترهای SecureStorage

3. **create_new_wallet_screen.dart**
   - رفع پارامترهای SecureStorage

4. **inside_new_wallet_screen.dart**
   - رفع پارامترهای SecureStorage

5. **home_screen.dart**
   - اضافه کردن import مفقود

## مزایای این تغییرات

1. **سازگاری کامل**: تمام متدها با signature صحیح استفاده می‌شوند
2. **Error Handling بهتر**: مدیریت خطاها برای navigation
3. **Navigation صحیح**: استفاده از صفحه موجود به جای صفحه غیرموجود
4. **Data Validation**: بررسی وجود mnemonic قبل از navigation

## تست کردن

حالا اپلیکیشن باید بدون خطای کامپایل اجرا شود و تمام قابلیت‌های wallet screen به درستی کار کنند:

1. **تغییر نام کیف پول**: بررسی ذخیره‌سازی صحیح
2. **حذف کیف پول**: بررسی حذف کامل
3. **Backup navigation**: بررسی navigation به صفحه phrase key
4. **Error handling**: بررسی نمایش پیام‌های خطا 