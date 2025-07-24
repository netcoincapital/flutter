# 🔔 سیستم کامل نوتیفیکیشن - مستندات جامع

## 📋 فهرست مطالب

1. [نمای کلی سیستم](#نمای-کلی-سیستم)
2. [معماری چندلایه](#معماری-چندلایه)
3. [جریان کامل کار](#جریان-کامل-کار)
4. [فایل‌های کلیدی](#فایل‌های-کلیدی)
5. [انواع نوتیفیکیشن](#انواع-نوتیفیکیشن)
6. [ساختار پیام](#ساختار-پیام)
7. [کانال‌ها و صداها](#کانال‌ها-و-صداها)
8. [تست و عیب‌یابی](#تست-و-عیب‌یابی)

---

## 🎯 نمای کلی سیستم

سیستم نوتیفیکیشن این اپلیکیشن با **معماری چندلایه** و **Firebase Cloud Messaging** پیاده‌سازی شده که قابلیت‌های زیر را ارائه می‌دهد:

### ✨ ویژگی‌های کلیدی:
- **🔥 Firebase Cloud Messaging (FCM)** برای ارسال از سرور
- **📱 Native Android/iOS Services** برای مدیریت پیام‌های background
- **🎵 صداهای مخصوص** برای انواع مختلف نوتیفیکیشن
- **🔊 کانال‌های جداگانه** برای مدیریت بهتر
- **🌐 پشتیبانی از چندین زبان** (فارسی، انگلیسی، عربی، چینی، ترکی، اسپانیایی)
- **🛡️ مدیریت مجوزها** و امنیت
- **📊 پردازش خودکار** تراکنش‌ها

---

## 🏗️ معماری چندلایه

```
📊 Backend Server (Django/Node.js)
    ↓ (Firebase Admin SDK)
☁️ Firebase Cloud Messaging (FCM)
    ↓ (Push Notification)
📱 Device (iOS/Android)
    ↓
🔥 Native Layer (Kotlin/Swift)
    ↓ (Method Channel)
📱 Flutter Layer (Dart)
    ↓
🔔 Local Notifications
    ↓
👤 User Interface
```

### **لایه ۱: Backend Server**
- **Django API** با Firebase Admin SDK
- **URL:** `https://coinceeper.com/api/`
- **Endpoint:** `/api/notifications/register-device`
- **ارسال پیام** با ساختار JSON استاندارد

### **لایه ۲: Firebase Cloud Messaging**
- **Project:** `coinceeper-f2eaf`
- **API Key:** `AIzaSyBnmgQ6SVmxoAXUq4x5HvfA0bppDD_HO3Y`
- **تحویل پیام** به دستگاه‌های هدف

### **لایه ۳: Native Layer**
- **Android:** `MyFirebaseMessagingService.kt`
- **iOS:** `AppDelegate.swift` + notification handling
- **پردازش پیام‌های background/terminated**

### **لایه ۴: Flutter Layer**
- **Service:** `FirebaseMessagingService.dart`
- **Helper:** `NotificationHelper.dart`
- **پردازش پیام‌های foreground**

### **لایه ۵: UI Layer**
- **Settings:** `NotificationManagementScreen.dart`
- **Provider:** `AppProvider.dart`
- **نمایش و مدیریت** تنظیمات کاربر

---

## 🔄 جریان کامل کار

### **1️⃣ مقداردهی اولیه (App Startup)**

```dart
// main.dart
void main() async {
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Initialize services in parallel
  await Future.wait([
    NotificationHelper.initialize(),
    FirebaseMessagingService().initialize(),
  ]);
}
```

**اتفاقات:**
- ✅ Firebase Core initialize می‌شود
- ✅ FCM token دریافت می‌شود
- ✅ کانال‌های نوتیفیکیشن ساخته می‌شوند
- ✅ مجوزهای ضروری درخواست می‌شوند

### **2️⃣ ثبت دستگاه (Device Registration)**

```dart
// FirebaseMessagingService.dart
Future<void> sendTokenToBackend() async {
  final success = await apiService.registerFCMToken(userId, _token);
}
```

**درخواست HTTP:**
```json
POST /api/notifications/register-device
{
  "UserID": "c1bf9df0-8263-41f1-844f-2e587f9b4050",
  "WalletID": "wallet-id-123",
  "DeviceToken": "fcm-token-here",
  "DeviceName": "Samsung Galaxy S21",
  "DeviceType": "android"
}
```

### **3️⃣ ارسال از سرور (Server Push)**

**Backend ارسال می‌کند:**
```json
{
  "to": "USER_FCM_TOKEN",
  "notification": {
    "title": "💰 Received: 0.001 BTC",
    "body": "From 1A1zP1...eP2sh"
  },
  "data": {
    "type": "receive",
    "transaction_id": "tx_123456789",
    "amount": "0.001",
    "currency": "BTC",
    "direction": "inbound",
    "from_address": "1A1zP1eP2sh...",
    "to_address": "bc1qxy2k...",
    "wallet_id": "wallet-id-123"
  },
  "android": {
    "notification": {
      "channel_id": "receive_channel",
      "sound": "receive_sound"
    }
  }
}
```

### **4️⃣ دریافت در دستگاه (Device Reception)**

#### **🤖 Android (Background/Terminated):**
```kotlin
// MyFirebaseMessagingService.kt
override fun onMessageReceived(remoteMessage: RemoteMessage) {
    val type = remoteMessage.data["type"] ?: "general"
    val channelId = when (type) {
        "receive" -> RECEIVE_CHANNEL_ID
        "send" -> SEND_CHANNEL_ID
        else -> DEFAULT_CHANNEL_ID
    }
    sendNotification(title, body, channelId)
}
```

#### **📱 Flutter (Foreground):**
```dart
// FirebaseMessagingService.dart
Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await _showLocalNotification(message);
}
```

### **5️⃣ نمایش نوتیفیکیشن (Display)**

**با کانال مناسب:**
- 🎵 **صدای مخصوص** (receive_sound.ogg)
- 🔴 **اولویت بالا** (High Priority)
- 🌟 **آیکون مخصوص** (ic_launcher)
- 🎨 **رنگ مناسب** (تبعی از نوع)

### **6️⃣ تعامل کاربر (User Interaction)**

```dart
// Navigation based on notification type
switch (type?.toLowerCase()) {
  case 'receive':
  case 'send':
    // Navigate to transaction details
    break;
  case 'price_alert':
    // Navigate to market screen
    break;
  case 'security':
    // Navigate to security settings
    break;
}
```

---

## 📁 فایل‌های کلیدی

### **🔥 Firebase & Core Services**

#### `lib/services/firebase_messaging_service.dart`
```dart
class FirebaseMessagingService {
  // FCM token management
  // Message handlers (foreground, background, terminated)
  // Local notification display
  // Native Android sync via MethodChannel
}
```

#### `android/app/src/main/kotlin/.../MyFirebaseMessagingService.kt`
```kotlin
class MyFirebaseMessagingService : FirebaseMessagingService() {
  // Background message processing
  // Notification channel management  
  // Custom sound handling
  // Intent creation for navigation
}
```

### **🔔 Notification Management**

#### `lib/services/notification_helper.dart`
```dart
class NotificationHelper {
  // Channel creation and management
  // Show different notification types
  // Permission handling
  // Sound and priority settings
}
```

#### `lib/screens/notification_management_screen.dart`
```dart
class NotificationManagementScreen {
  // User notification preferences
  // Toggle push notifications
  // Toggle specific notification types
}
```

### **🗂️ Data Models**

#### `lib/services/transaction_notification_receiver.dart`
```dart
class TransactionNotificationReceiver {
  // Stream-based transaction notifications
  // Remove pending transactions
  // Handle confirmed/failed transactions
}
```

#### `lib/providers/history_provider.dart`
```dart
class HistoryProvider {
  // Manage pending transactions
  // Sync with server transactions
  // Remove confirmed transactions
}
```

### **⚙️ Configuration Files**

#### `android/app/google-services.json`
```json
{
  "project_info": {
    "project_number": "1048276147027",
    "project_id": "coinceeper-f2eaf"
  }
}
```

#### `ios/Runner/GoogleService-Info.plist`
```xml
<key>GOOGLE_APP_ID</key>
<string>1:1048276147027:ios:8a9b0c1d2e3f4567</string>
```

#### `lib/firebase_options.dart`
```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSyBnmgQ6SVmxoAXUq4x5HvfA0bppDD_HO3Y',
  appId: '1:1048276147027:android:9c8b7a6d5e4f3241',
  messagingSenderId: '1048276147027',
  projectId: 'coinceeper-f2eaf',
);
```

---

## 🎯 انواع نوتیفیکیشن

### **1️⃣ تراکنش‌های مالی**

#### **💰 دریافت وجه (receive)**
```json
{
  "type": "receive",
  "title": "💰 دریافت وجه",
  "body": "شما 0.001 BTC دریافت کردید",
  "channel": "receive_channel",
  "sound": "receive_sound",
  "priority": "high"
}
```

#### **📤 ارسال وجه (send)**
```json
{
  "type": "send", 
  "title": "📤 ارسال وجه",
  "body": "شما 0.001 BTC ارسال کردید",
  "channel": "send_channel",
  "sound": "send_sound",
  "priority": "high"
}
```

### **2️⃣ هشدارها و اعلان‌ها**

#### **📈 هشدار قیمت (price_alert)**
```json
{
  "type": "price_alert",
  "title": "📈 هشدار قیمت",
  "body": "قیمت بیت‌کوین به $65,000 رسید",
  "channel": "price_alert_channel",
  "sound": "price_alert_sound",
  "priority": "high"
}
```

#### **🎉 خوش‌آمدگویی (welcome)**
```json
{
  "type": "welcome",
  "title": "🎉 خوش آمدید",
  "body": "به کیف پول لکس خوش آمدید",
  "channel": "welcome_channel", 
  "sound": "welcome_sound",
  "priority": "default"
}
```

#### **🛡️ امنیتی (security)**
```json
{
  "type": "security",
  "title": "🛡️ هشدار امنیتی", 
  "body": "ورود از دستگاه جدید تشخیص داده شد",
  "channel": "high_importance_channel",
  "sound": "default",
  "priority": "high"
}
```

---

## 📦 ساختار پیام

### **🎯 ساختار کلی FCM**
```json
{
  "to": "USER_FCM_TOKEN",
  "notification": {
    "title": "عنوان نوتیفیکیشن",
    "body": "محتوای نوتیفیکیشن" 
  },
  "data": {
    "type": "نوع نوتیفیکیشن",
    "custom_field1": "مقدار سفارشی 1",
    "custom_field2": "مقدار سفارشی 2"
  },
  "android": {
    "notification": {
      "channel_id": "شناسه کانال",
      "sound": "نام صدا"
    }
  },
  "apns": {
    "payload": {
      "aps": {
        "sound": "نام صدا.caf"
      }
    }
  }
}
```

### **💳 تراکنش مالی (جدید)**
```json
{
  "data": {
    "type": "receive",           // یا "send"
    "transaction_id": "tx_123456789",
    "amount": "0.001", 
    "currency": "BTC",
    "from_address": "1A1zP1eP2sh...",
    "to_address": "bc1qxy2k...",
    "wallet_id": "wallet-123",
    "block_height": "780123",
    "confirmations": "3"
  }
}
```

### **💳 تراکنش مالی (قدیمی - پشتیبانی شده)**
```json
{
  "data": {
    "type": "transaction",
    "direction": "inbound",      // یا "outbound"
    "transaction_id": "tx_123456789",
    "amount": "0.001",
    "symbol": "BTC",            // استفاده از symbol به جای currency
    "from_address": "1A1zP1eP2sh...",
    "to_address": "bc1qxy2k..."
  }
}
```

### **📊 سایر انواع**
```json
{
  "data": {
    // Welcome
    "type": "welcome",
    "user_id": "user-123",
    "wallet_count": "1",
    
    // Price Alert  
    "type": "price_alert",
    "symbol": "BTC",
    "current_price": "65000",
    "target_price": "60000",
    "direction": "above",
    
    // Security
    "type": "security", 
    "action": "login",
    "device_info": "Samsung Galaxy S21",
    "location": "Tehran, Iran",
    "ip_address": "192.168.1.1"
  }
}
```

---

## 🔊 کانال‌ها و صداها

### **📱 کانال‌های Android**

| نوع | کانال ID | نام کانال | اهمیت | صدا |
|-----|----------|-----------|--------|-----|
| دریافت وجه | `receive_channel` | Receive Notifications | HIGH | receive_sound |
| ارسال وجه | `send_channel` | Send Notifications | HIGH | send_sound |
| خوش‌آمدگویی | `welcome_channel` | Welcome Notifications | DEFAULT | welcome_sound |
| هشدار قیمت | `price_alert_channel` | Price Alert Notifications | HIGH | price_alert_sound |
| عمومی | `high_importance_channel` | General Notifications | HIGH | default |

### **🎵 فایل‌های صوتی**

#### **📂 مسیر Android:**
```
android/app/src/main/res/raw/
├── receive_sound.ogg
├── send_sound.ogg  
├── welcome_sound.ogg
└── price_alert_sound.ogg
```

#### **📂 مسیر iOS:**
```
ios/Runner/Sounds/
├── receive_sound.caf
├── send_sound.caf
├── welcome_sound.caf  
└── price_alert_sound.caf
```

### **⚙️ ساخت کانال‌ها**

#### **🤖 Android (Native):**
```kotlin
private fun createNotificationChannels() {
    val channels = listOf(
        NotificationChannel(
            RECEIVE_CHANNEL_ID,
            "Receive Notifications", 
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            setSound(
                Uri.parse("android.resource://$packageName/raw/receive_sound"),
                null
            )
        }
        // ... سایر کانال‌ها
    )
    
    channels.forEach { notificationManager.createNotificationChannel(it) }
}
```

#### **📱 Flutter:**
```dart
static Future<void> _createNotificationChannels() async {
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      'receive_channel',
      'Receive Notifications',
      description: 'Channel for receive notifications',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('receive_sound'),
    )
  );
}
```

---

## 🧪 تست و عیب‌یابی

### **1️⃣ تست محلی (Local Testing)**

#### **📝 Python Script (`test_notifications.py`):**
```python
import requests

def send_fcm_notification(token, notification_type="receive"):
    payload = {
        "to": token,
        "notification": {
            "title": "تست نوتیفیکیشن",
            "body": "این یک تست است"
        },
        "data": {
            "type": notification_type,
            "amount": "0.001",
            "currency": "BTC"
        }
    }
    
    response = requests.post(
        "https://fcm.googleapis.com/fcm/send",
        json=payload,
        headers={
            "Authorization": "key=YOUR_SERVER_KEY",
            "Content-Type": "application/json"
        }
    )
    
    print(f"Response: {response.status_code}")
    print(f"Body: {response.text}")

# استفاده
send_fcm_notification("YOUR_FCM_TOKEN", "receive")
```

#### **🔧 cURL Command:**
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "YOUR_FCM_TOKEN",
    "notification": {
      "title": "تست نوتیفیکیشن", 
      "body": "شما 0.001 BTC دریافت کردید"
    },
    "data": {
      "type": "receive",
      "amount": "0.001", 
      "currency": "BTC",
      "transaction_id": "test_tx_123"
    }
  }'
```

### **2️⃣ مشاهده Logs**

#### **📱 Flutter Console:**
```bash
flutter run --debug -d device_id

# Logs شامل:
# 🔥 Firebase initialized successfully
# 🪙 FCM Token: [TOKEN] 
# 📱 Message received: [DETAILS]
# ✅ Local notification shown on channel: receive_channel
```

#### **🤖 Android Logcat:**
```bash
adb logcat | grep "MyFirebaseMessaging"

# Logs شامل:
# D/MyFirebaseMessaging: 📱 Message received from: [SENDER]
# D/MyFirebaseMessaging: 📱 Message data: {type=receive, amount=0.001}
# D/MyFirebaseMessaging: 🔔 Showing notification on channel: receive_channel
```

### **3️⃣ عیب‌یابی مسائل رایج**

#### **❌ FCM Token نمی‌آید:**
```dart
// بررسی Firebase initialization
if (Firebase.apps.isEmpty) {
  await Firebase.initializeApp();
}

// بررسی مجوزها
final permission = await Permission.notification.status;
if (!permission.isGranted) {
  await Permission.notification.request();
}
```

#### **❌ نوتیفیکیشن نمایش داده نمی‌شود:**
```kotlin
// بررسی کانال‌ها
private fun checkNotificationChannels() {
    val channels = notificationManager.notificationChannels
    Log.d(TAG, "Available channels: ${channels.map { it.id }}")
}

// بررسی مجوزها
private fun checkNotificationPermission(): Boolean {
    return NotificationManagerCompat.from(this).areNotificationsEnabled()
}
```

#### **❌ صدا پخش نمی‌شود:**
```kotlin
// بررسی فایل صوتی
private fun checkSoundFiles() {
    val soundUri = Uri.parse("android.resource://$packageName/raw/receive_sound")
    Log.d(TAG, "Sound URI: $soundUri")
}
```

### **4️⃣ تست حالت‌های مختلف اپ**

#### **✅ Foreground (اپ باز است):**
- Flutter `FirebaseMessaging.onMessage` فعال است
- Local notification نمایش داده می‌شود
- Navigation مستقیم امکان‌پذیر است

#### **✅ Background (اپ در پس‌زمینه):**
- Native service پیام را پردازش می‌کند
- System notification نمایش داده می‌شود  
- با tap کردن به اپ برمی‌گردد

#### **✅ Terminated (اپ بسته):**
- Native service پیام را پردازش می‌کند
- System notification نمایش داده می‌شود
- با tap کردن اپ باز می‌شود

---

## 🎊 خلاصه و نتیجه‌گیری

سیستم نوتیفیکیشن این اپلیکیشن یک **پیاده‌سازی کامل و حرفه‌ای** است که شامل:

### ✅ **ویژگی‌های کلیدی:**
- 🔥 **Firebase Cloud Messaging** برای reliability
- 🎵 **صداهای مخصوص** برای تجربه بهتر کاربر
- 🌐 **پشتیبانی چندزبانه** برای بازار جهانی
- 🔊 **کانال‌های مجزا** برای مدیریت بهتر
- 📱 **Native + Flutter** برای پوشش کامل حالات اپ
- 🛡️ **مدیریت مجوزها** برای امنیت و قوانین

### 🎯 **کاربردهای اصلی:**
- 💰 **اعلان تراکنش‌ها** (ارسال/دریافت)
- 📈 **هشدارهای قیمت** برای trading
- 🛡️ **اعلان‌های امنیتی** برای محافظت
- 🎉 **پیام‌های خوش‌آمدگویی** برای onboarding

### 🚀 **آماده برای:**
- ⚡ **اجرای فوری** بدون تغییر
- 🧪 **تست با ابزارهای موجود** 
- 🔧 **سفارشی‌سازی** ساده
- 📊 **مانیتورینگ** و آنالیز

---

**✨ این سیستم آماده استفاده در production است و تمام حالت‌های ممکن را پوشش می‌دهد!** 