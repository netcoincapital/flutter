import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static const String receiveChannelId = 'receive_channel';
  static const String sendChannelId = 'send_channel';
  static const String welcomeChannelId = 'welcome_channel';
  static const String priceAlertChannelId = 'price_alert_channel';
  static const String loginChannelId = 'login_channel_id';
  static const int notificationId = 1;

  /// مقداردهی اولیه کانال‌ها
  static Future<void> initialize() async {
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('notifsmall');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _notifications.initialize(initSettings);
    await _createNotificationChannels();
  }

  /// ساخت کانال‌های نوتیفیکیشن
  static Future<void> _createNotificationChannels() async {
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(const AndroidNotificationChannel(
          receiveChannelId,
          'Receive Notifications',
          description: 'Channel for receive notifications',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('receive_sound'),
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          sendChannelId,
          'Send Notifications',
          description: 'Channel for send notifications',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('send_sound'),
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          welcomeChannelId,
          'Welcome Notifications',
          description: 'Channel for welcome notifications',
          importance: Importance.defaultImportance,
          sound: RawResourceAndroidNotificationSound('welcome_sound'),
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          priceAlertChannelId,
          'Price Alert Notifications',
          description: 'Channel for price alert notifications',
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('price_alert_sound'),
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          loginChannelId,
          'Login Notifications',
          description: 'Channel for login notifications',
          importance: Importance.defaultImportance,
        ));
      }
    }
  }

  /// درخواست مجوز نوتیفیکیشن (Android 13+ و iOS)
  static Future<void> requestNotificationPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } else if (Platform.isIOS) {
      // iOS: مجوز هنگام initialize درخواست می‌شود
    }
  }

  /// ارسال نوتیفیکیشن ساده
  static Future<void> showNotification({
    required String channelId,
    required String title,
    required String body,
    String? payload,
    String? largeIconAsset,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId,
      channelDescription: 'Channel for $channelId',
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: largeIconAsset != null ? DrawableResourceAndroidBitmap(largeIconAsset) : null,
    );
    final iosDetails = const DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// ارسال نوتیفیکیشن خوش‌آمد
  static Future<void> showWelcomeNotification() async {
    await showNotification(
      channelId: welcomeChannelId,
      title: 'Welcome',
      body: 'Welcome to ADL Wallet',
      largeIconAsset: 'logo',
    );
  }

  /// ارسال نوتیفیکیشن دریافت وجه
  static Future<void> showReceiveNotification(double amount, String currency) async {
    await showNotification(
      channelId: receiveChannelId,
      title: 'دریافت وجه',
      body: 'شما $amount $currency دریافت کردید!',
      largeIconAsset: 'logo',
    );
  }

  /// ارسال نوتیفیکیشن ارسال وجه
  static Future<void> showSendNotification(double amount, String currency) async {
    await showNotification(
      channelId: sendChannelId,
      title: 'ارسال وجه',
      body: 'شما $amount $currency ارسال کردید!',
      largeIconAsset: 'logo',
    );
  }

  /// ارسال نوتیفیکیشن هشدار قیمت
  static Future<void> showPriceAlertNotification(double currentPrice) async {
    await showNotification(
      channelId: priceAlertChannelId,
      title: 'هشدار قیمت!',
      body: 'قیمت بیت‌کوین به $currentPrice دلار رسید!',
      largeIconAsset: 'logo',
    );
  }

  /// حذف همه نوتیفیکیشن‌ها
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// حذف کانال‌های نوتیفیکیشن (فقط اندروید)
  static Future<void> deleteNotificationChannels() async {
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.deleteNotificationChannel(receiveChannelId);
        await android.deleteNotificationChannel(sendChannelId);
        await android.deleteNotificationChannel(welcomeChannelId);
        await android.deleteNotificationChannel(priceAlertChannelId);
        await android.deleteNotificationChannel(loginChannelId);
      }
    }
  }
} 