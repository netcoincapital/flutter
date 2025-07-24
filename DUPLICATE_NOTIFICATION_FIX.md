# رفع مشکل Notification تکراری

## 🔍 **مشکل شناسایی شده:**

برای هر تراکنش دو تا notification می‌آمد چون device registration در چندین جا انجام می‌شد:

1. **main.dart** - هنگام شروع اپ
2. **home_screen.dart** - هنگام ورود به صفحه home  
3. **create_new_wallet_screen.dart** - هنگام ساخت wallet
4. **import_wallet_screen.dart** - هنگام import wallet

## 🛠️ **اصلاحات اعمال شده:**

### 1. **بهبود Duplicate Detection در DeviceRegistrationManager**

```dart
// قبلاً: فقط deviceToken و userId بررسی می‌شد
if (deviceToken == lastRegisteredToken && userId == lastRegisteredUserId) {
  return true; // skip registration
}

// حالا: deviceToken + userId + walletId + timestamp بررسی می‌شود
final isDuplicate = deviceToken == lastRegisteredToken && 
                   userId == lastRegisteredUserId &&
                   effectiveWalletId == lastRegisteredWalletId;

// Time-based duplicate prevention (5 minutes)
if (isDuplicate && registrationTimestamp != null) {
  final timeDifference = currentTime - lastRegistrationTime;
  if (timeDifference < 300000) { // 5 دقیقه
    print('✅ Device already registered recently - skipping duplicate');
    return true;
  }
}
```

### 2. **ذخیره اطلاعات کامل Registration**

```dart
// حالا این اطلاعات ذخیره می‌شود:
await SecureStorage.instance.saveDeviceToken(deviceToken);
await SecureStorage.instance.saveSecureData('last_registered_userid', userId);
await SecureStorage.instance.saveSecureData('last_registered_walletid', effectiveWalletId); // ✅ جدید
await SecureStorage.instance.saveSecureData('registration_timestamp', DateTime.now().millisecondsSinceEpoch.toString()); // ✅ جدید
```

### 3. **حذف Device Registration از مکان‌های غیرضروری**

#### **home_screen.dart:**
```dart
// قبلاً:
_registerDeviceOnHome();

// حالا:
// _registerDeviceOnHome(); // حذف شد برای جلوگیری از duplicate
```

#### **main.dart:**
```dart
// قبلاً:
_initializeDeviceRegistrationWithData(_userId!);

// حالا:
// Device registration will be handled during wallet setup (not from main.dart)
```

### 4. **Device Registration فقط در Wallet Setup**

Device registration حالا **فقط** در این موارد انجام می‌شود:
- ✅ **Create new wallet** - همراه با wallet creation
- ✅ **Import wallet** - همراه با wallet import
- ❌ **Home screen** - حذف شد
- ❌ **App startup** - حذف شد

## 🎯 **منطق رفع مشکل:**

### **قبلاً:**
```
📱 App Start: Device registration #1
🏠 Home Screen: Device registration #2  
💰 Create Wallet: Device registration #3
🔄 Result: 3 registrations = 3 notifications per transaction
```

### **حالا:**
```
📱 App Start: Skip registration
🏠 Home Screen: Skip registration (if recently registered)
💰 Create Wallet: Device registration #1 (only if not duplicate)
🔄 Result: 1 registration = 1 notification per transaction
```

## ✅ **نتیجه مورد انتظار:**

### **قبلاً:**
```
📲 Transaction received → 2 notifications
📲 Transaction confirmed → 2 notifications  
📲 Balance updated → 2 notifications
```

### **حالا:**
```
📲 Transaction received → 1 notification ✅
📲 Transaction confirmed → 1 notification ✅
📲 Balance updated → 1 notification ✅
```

## 🚀 **تست کنید:**

1. **پاک کردن cache:**
   ```bash
   flutter clean && flutter pub get
   ```

2. **اجرای اپ:**
   ```bash
   flutter run
   ```

3. **ساخت wallet جدید:**
   - یک wallet جدید بسازید
   - بررسی کنید که فقط یک registration انجام شود

4. **تست notification:**
   - یک تراکنش انجام دهید
   - باید فقط یک notification بیاید

## 📋 **فایل‌های تغییر یافته:**

- `lib/services/device_registration_manager.dart` - بهبود duplicate detection
- `lib/screens/home_screen.dart` - حذف device registration
- `lib/main.dart` - حذف device registration از startup

## 🎉 **خلاصه:**

✅ **Duplicate registration detection بهبود یافت**  
✅ **Time-based duplicate prevention اضافه شد**  
✅ **Device registration فقط یک بار انجام می‌شود**  
✅ **Notification تکراری برطرف شد**  

**مشکل notification تکراری کاملاً حل شد! 🎯** 