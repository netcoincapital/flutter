# Firebase Push Notifications Setup Guide

این راهنما شامل مراحل کامل setup کردن Firebase برای فعال‌سازی push notifications در اپ Laxce Wallet است.

## 📋 فهرست مطالب

1. [ایجاد Firebase Project](#1-ایجاد-firebase-project)
2. [اضافه کردن Android App](#2-اضافه-کردن-android-app)
3. [اضافه کردن iOS App](#3-اضافه-کردن-ios-app)
4. [فعال‌سازی Cloud Messaging](#4-فعالسازی-cloud-messaging)
5. [تست Push Notifications](#5-تست-push-notifications)
6. [Backend Integration](#6-backend-integration)

---

## 1. ایجاد Firebase Project

### مرحله 1: ورود به Firebase Console
1. به [Firebase Console](https://console.firebase.google.com/) بروید
2. با حساب Google خود وارد شوید
3. روی **"Create a project"** کلیک کنید

### مرحله 2: تنظیمات Project
1. **Project name**: `laxce-wallet` (یا نام دلخواه)
2. **Project ID**: `laxce-wallet-xxxxx` (ID یکتا انتخاب کنید)
3. **Analytics**: می‌توانید غیرفعال کنید (اختیاری)
4. روی **"Create project"** کلیک کنید

---

## 2. اضافه کردن Android App

### مرحله 1: Add Android App
1. در Firebase Console، روی **"Add app"** کلیک کنید
2. آیکون Android را انتخاب کنید

### مرحله 2: Register App
```
Android package name: com.example.my_flutter_app
App nickname: Laxce Wallet Android
Debug signing certificate SHA-1: (اختیاری - برای testing)
```

### مرحله 3: Download Config File
1. فایل **`google-services.json`** را دانلود کنید
2. آن را در مسیر زیر قرار دهید:
```
my_flutter_app/android/app/google-services.json
```

### مرحله 4: جایگزینی Template
فایل template موجود را با فایل دانلود شده جایگزین کنید:
- فایل فعلی: `android/app/google-services.json` (template)
- فایل جدید: فایل دانلود شده از Firebase Console

---

## 3. اضافه کردن iOS App

### مرحله 1: Add iOS App
1. در Firebase Console، روی **"Add app"** کلیک کنید
2. آیکون iOS را انتخاب کنید

### مرحله 2: Register App
```
iOS bundle ID: com.laxce.myFlutterApp
App nickname: Laxce Wallet iOS
App Store ID: (اختیاری)
```

### مرحله 3: Download Config File
1. فایل **`GoogleService-Info.plist`** را دانلود کنید
2. آن را در مسیر زیر قرار دهید:
```
my_flutter_app/ios/Runner/GoogleService-Info.plist
```

### مرحله 4: جایگزینی Template
فایل template موجود را با فایل دانلود شده جایگزین کنید:
- فایل فعلی: `ios/Runner/GoogleService-Info.plist` (template)
- فایل جدید: فایل دانلود شده از Firebase Console

---

## 4. فعال‌سازی Cloud Messaging

### مرحله 1: Enable FCM API
1. در Firebase Console، به **"Project Settings"** بروید
2. تب **"Cloud Messaging"** را انتخاب کنید
3. **Cloud Messaging API** را فعال کنید

### مرحله 2: Server Key
1. در تب Cloud Messaging، **Server key** را کپی کنید
2. این key را برای backend API نیاز خواهید داشت

---

## 5. تست Push Notifications

### مرحله 1: اجرای App
```bash
cd my_flutter_app
flutter run
```

### مرحله 2: فعال‌سازی در App
1. به **Settings** → **Notifications** بروید
2. روی **"Enable Notifications"** کلیک کنید
3. Permissions را تایید کنید
4. FCM Token دریافت می‌شود

### مرحله 3: ارسال Test Message
1. در Firebase Console به **"Cloud Messaging"** بروید
2. روی **"Send your first message"** کلیک کنید
3. عنوان و متن پیام را وارد کنید
4. Target را **"Single device"** انتخاب کنید
5. FCM Token از app را وارد کنید
6. **"Send"** کنید

---

## 6. Backend Integration

### مرحله 1: API Endpoint برای Registration
Backend باید endpoint زیر را داشته باشد:
```
POST /api/register-fcm-token
{
  "userId": "user_id",
  "fcmToken": "FCM_TOKEN_HERE",
  "platform": "android" | "ios"
}
```

### مرحله 2: کد Sample Backend (Node.js)
```javascript
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./path/to/service-account-key.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Send notification
async function sendNotification(fcmToken, title, body, data = {}) {
  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: data,
    token: fcmToken,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message:', response);
    return response;
  } catch (error) {
    console.log('Error sending message:', error);
    throw error;
  }
}
```

### مرحله 3: اضافه کردن به API Service
در فایل `lib/services/api_service.dart`:
```dart
Future<bool> registerFCMToken(String userId, String fcmToken) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/register-fcm-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'fcmToken': fcmToken,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      }),
    );
    
    return response.statusCode == 200;
  } catch (e) {
    print('Error registering FCM token: $e');
    return false;
  }
}
```

---

## 🔧 Troubleshooting

### مشکل: Firebase not initialized
**حل:** مطمئن شوید فایل‌های config در مکان صحیح قرار دارند

### مشکل: Permission denied
**حل:** در Settings دستگاه، notification permissions را بررسی کنید

### مشکل: Token not received
**حل:** 
1. اتصال اینترنت را بررسی کنید
2. Firebase project تنظیمات را دوباره بررسی کنید
3. Clean build و rebuild کنید:
```bash
flutter clean
flutter pub get
flutter run
```

### مشکل: Build error
**حل:**
1. Gradle sync کنید
2. Dependencies را update کنید
3. Android SDK و tools را update کنید

---

## 📱 Test Notification Types

### 1. Transaction Notification
```json
{
  "notification": {
    "title": "Transaction Confirmed",
    "body": "Your transaction of 0.5 ETH has been confirmed"
  },
  "data": {
    "type": "transaction",
    "transactionId": "0x123...",
    "action": "view_transaction"
  }
}
```

### 2. Security Alert
```json
{
  "notification": {
    "title": "Security Alert",
    "body": "New device login detected"
  },
  "data": {
    "type": "security",
    "action": "view_security"
  }
}
```

### 3. Price Alert
```json
{
  "notification": {
    "title": "Price Alert",
    "body": "BTC reached your target price of $50,000"
  },
  "data": {
    "type": "price",
    "symbol": "BTC",
    "price": "50000",
    "action": "view_chart"
  }
}
```

---

## ✅ Final Checklist

- [ ] Firebase project ایجاد شده
- [ ] Android app اضافه شده
- [ ] iOS app اضافه شده  
- [ ] `google-services.json` در محل صحیح قرار دارد
- [ ] `GoogleService-Info.plist` در محل صحیح قرار دارد
- [ ] Cloud Messaging API فعال است
- [ ] App compile و run می‌شود
- [ ] Notification permission granted است
- [ ] FCM token دریافت می‌شود
- [ ] Test notification ارسال شده
- [ ] Backend integration انجام شده

---

## 🔗 مراجع مفید

- [Firebase Console](https://console.firebase.google.com/)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [FCM Documentation](https://firebase.google.com/docs/cloud-messaging)
- [Android Setup Guide](https://firebase.google.com/docs/android/setup)
- [iOS Setup Guide](https://firebase.google.com/docs/ios/setup)

---

**نکته مهم:** پس از setup کامل Firebase، فایل‌های template را با فایل‌های واقعی Firebase جایگزین کنید تا push notifications به درستی کار کند. 