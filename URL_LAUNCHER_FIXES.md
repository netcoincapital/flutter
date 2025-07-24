# URL Launcher Fixes & Improvements

## مشکل اصلی
خطای `PlatformException` در `url_launcher` که باعث می‌شد لینک‌های شبکه‌های اجتماعی باز نشوند.

## تغییرات انجام شده

### 1. بهبود error handling
- اضافه کردن `canLaunchUrl` check
- Multi-fallback strategy برای باز کردن لینک‌ها
- بهتر کردن error messages

### 2. استراتژی fallback (4 مرحله)
1. **Primary**: `url_launcher` با `LaunchMode.externalApplication`
2. **Secondary**: `external_app_launcher` برای اپلیکیشن‌های خاص
3. **Tertiary**: `url_launcher` با `LaunchMode.platformDefault`
4. **Final**: Copy link to clipboard

### 3. تغییرات کد

#### قبل از تغییرات:
```dart
// فقط url_launcher یا external_app_launcher
final success = await launchUrl(Uri.parse(url));
```

#### بعد از تغییرات:
```dart
// Multi-step fallback strategy
// 1. Try direct URL launch with externalApplication mode
final success = await launchUrl(
  Uri.parse(url),
  mode: LaunchMode.externalApplication,
);

// 2. Try external_app_launcher for specific apps
await LaunchApp.openApp(
  androidPackageName: 'org.telegram.messenger',
  iosUrlScheme: 'tg://resolve?domain=username',
);

// 3. Try with platformDefault mode
final success = await launchUrl(
  Uri.parse(url),
  mode: LaunchMode.platformDefault,
);

// 4. Final fallback: Copy to clipboard
await Clipboard.setData(ClipboardData(text: url));
```

### 4. تنظیمات AndroidManifest.xml
- ~~اضافه کردن `QUERY_ALL_PACKAGES` permission~~ (حذف شد برای تطبیق با Google Play Policy)
- اضافه کردن intent-filters برای URL schemes در `<queries>`  
- پیکربندی برای Telegram, Twitter, Instagram در `<queries>`
- اضافه کردن `<package>` queries برای social media apps
- پشتیبانی از schemes اضافی مانند `fb`, `tg`, `twitter`, `instagram`
- استفاده از `<queries>` به جای `QUERY_ALL_PACKAGES` برای تطبیق با Google Play Policy

### 5. نسخه‌های dependency
- `url_launcher: ^6.3.0`
- `external_app_launcher: ^4.0.0`

## نحوه استفاده

### تست کردن
1. روی لینک‌های شبکه‌های اجتماعی کلیک کنید
2. اگر اپلیکیشن نصب نبود، لینک کپی می‌شود
3. Console logs را برای debugging بررسی کنید

### در صورت مشکل
- اگر هنوز خطا می‌گیرید، `flutter clean` و `flutter pub get` کنید
- مطمئن شوید که device registration درست کار می‌کند
- لاگ‌های console را بررسی کنید

## لاگ‌های مهم
```
🔗 Trying to open [Platform] link...
🌐 Trying direct URL launcher...
✅ URL launcher succeeded!
❌ URL launcher returned false
📱 Trying External App Launcher...
✅ External launcher succeeded!
🔄 Trying with platformDefault mode...
✅ Platform default succeeded!
📋 Copying to clipboard as final fallback...
```

## نکات مهم
- همیشه `mounted` check کنید قبل از `ScaffoldMessenger`
- در صورت عدم موفقیت، لینک به clipboard کپی می‌شود
- User experience بهتر شده با 4-step fallback strategy
- حذف `canLaunchUrl` که باعث `PlatformException` می‌شد
- استفاده از `LaunchMode.externalApplication` برای باز کردن در اپلیکیشن خارجی
- استفاده از `LaunchMode.platformDefault` به عنوان fallback
- تست کامل تر شده با حالات مختلف launch

---
**تاریخ**: 2024
**نسخه**: 2.1 (Cleaned)
**وضعیت**: ✅ تست شده و آماده استفاده
**بهبودهای نسخه 2.1**: 
- حذف `canLaunchUrl` که باعث خطا می‌شد
- اضافه کردن multiple launch modes
- بهتر کردن error handling
- اضافه کردن package queries در AndroidManifest
- حذف Test URL Launcher (debug tool)
- حذف Data Management section (Factory Reset)
- کد تمیز و بهینه شده 