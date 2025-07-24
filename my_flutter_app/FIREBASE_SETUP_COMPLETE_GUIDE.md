# 🔥 راهنمای کامل پیکربندی Firebase

## ⚠️ مشکل فعلی
فایل‌های Firebase پیکربندی نشده‌اند و حاوی مقادیر placeholder هستند.

## 📱 راه‌حل کامل

### مرحله 1: ایجاد پروژه Firebase

1. به [Firebase Console](https://console.firebase.google.com) برید
2. روی "Add project" کلیک کنید
3. نام پروژه: `laxce-dex` (یا نام دلخواه)
4. Google Analytics را فعال کنید (اختیاری)

### مرحله 2: اضافه کردن اپلیکیشن‌ها

#### **برای Android:**
1. در پروژه Firebase روی "Add app" > Android کلیک کنید
2. Package name: `com.laxce.myFlutterApp`
3. App nickname: `Laxce DEX Android`
4. SHA-1 certificate را اضافه کنید (برای release)
5. فایل `google-services.json` را دانلود کرده و در `android/app/` قرار دهید

#### **برای iOS:**
1. در پروژه Firebase روی "Add app" > iOS کلیک کنید
2. Bundle ID: `com.laxce.myFlutterApp`
3. App nickname: `Laxce DEX iOS`
4. فایل `GoogleService-Info.plist` را دانلود کرده و در `ios/Runner/` قرار دهید

### مرحله 3: نصب FlutterFire CLI

```bash
# نصب FlutterFire CLI
dart pub global activate flutterfire_cli

# پیکربندی خودکار
flutterfire configure
```

### مرحله 4: فعالسازی سرویس‌ها

در Firebase Console:

1. **Authentication** > Sign-in method > Anonymous را فعال کنید
2. **Cloud Messaging** را فعال کنید  
3. **Firestore Database** ایجاد کنید (اختیاری)

### مرحله 5: تست پیکربندی

```bash
# اجرای اپلیکیشن
flutter run
```

## 🔧 راه‌حل موقت (اعمال شده)

تا زمان پیکربندی کامل Firebase، این تغییرات اعمال شده:

✅ **محافظت از Crash** - اپلیکیشن با خطای Firebase متوقف نمی‌شود  
✅ **Log مناسب** - خطاهای Firebase به صورت واضح نمایش داده می‌شوند  
✅ **Core Features** - ویژگی‌های اصلی کیف پول بدون Firebase کار می‌کنند  

## 📂 فایل‌های تغییر یافته

- `lib/main.dart` - اضافه شدن error handling
- `lib/services/firebase_messaging_service.dart` - محافظت از crash

## ⚡ نتیجه

🟢 **اپلیکیشن اکنون اجرا می‌شود** بدون crash  
🟡 **ویژگی‌های Firebase غیرفعال** تا پیکربندی کامل  
🔵 **Core crypto features** کاملاً کار می‌کنند  

## 🎯 مراحل بعدی

1. یک پروژه Firebase واقعی ایجاد کنید
2. فایل‌های configuration صحیح را دانلود کنید
3. از FlutterFire CLI استفاده کنید
4. Push notifications و analytics را فعال کنید 