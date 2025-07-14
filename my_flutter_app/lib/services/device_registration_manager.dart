import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'dart:async';
import 'api_service.dart';
import 'secure_storage.dart';
import '../services/api_models.dart';

/// مدیریت ثبت دستگاه در سرور - مشابه DeviceRegistrationManager.kt
class DeviceRegistrationManager {
  static DeviceRegistrationManager? _instance;
  static DeviceRegistrationManager get instance => _instance ??= DeviceRegistrationManager._();
  
  DeviceRegistrationManager._();
  
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final ApiService _apiService = ApiService();
  
  // تنظیمات مشابه Kotlin
  static const int API_TIMEOUT = 15000; // میلی‌ثانیه
  static const int MAX_RETRY_ATTEMPTS = 3;
  static const int RETRY_DELAY = 3000; // میلی‌ثانیه
  
  /// بررسی کامل بودن اطلاعات ثبت
  bool _isProvisioningComplete(String? userId, String? walletId, String? deviceToken) {
    return userId != null && userId.isNotEmpty && 
           walletId != null && walletId.isNotEmpty && 
           deviceToken != null && deviceToken.isNotEmpty;
  }
  
  /// دریافت توکن FCM (مشابه initializeFirebaseAndGetToken در Kotlin)
  Future<String?> _initializeFirebaseAndGetToken() async {
    try {
      print('📱 Attempting to get FCM token...');
      
      // بررسی آیا Firebase نصب شده
      // TODO: اضافه کردن بررسی Firebase initialization
      
      // دریافت توکن از SecureStorage (یا تولید جدید)
      final token = await _getDeviceToken();
      
      if (token.isNotEmpty) {
        print('✅ FCM token retrieved successfully');
        return token;
      } else {
        print('❌ Failed to get FCM token');
        return null;
      }
    } catch (e) {
      print('❌ Error getting FCM token: $e');
      return null;
    }
  }
  
  /// ثبت دستگاه با callback (مشابه registerDeviceWithCallback در Kotlin)
  Future<void> registerDeviceWithCallback({
    required String userId,
    required String walletId,
    required Function(bool success) onResult,
  }) async {
    const TAG = 'DeviceRegistration';
    
    try {
      final deviceName = await _getDeviceName();
      print('📱 Starting device registration process for UserID: $userId, WalletID: $walletId');
      
      // دریافت توکن
      print('📱 Attempting to get FCM token...');
      final deviceToken = await _initializeFirebaseAndGetToken();
      print('📱 FCM token retrieval result: ${deviceToken != null ? "Success" : "Failed"}');
      
      if (!_isProvisioningComplete(userId, walletId, deviceToken)) {
        print('❌ Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken');
        onResult(false);
        return;
      }
      
      // بررسی آیا دستگاه قبلاً ثبت شده
      final lastRegisteredToken = await SecureStorage.instance.getDeviceToken();
      final lastRegisteredUserId = await SecureStorage.instance.getSecureData('last_registered_userid');
      
      if (deviceToken == lastRegisteredToken && userId == lastRegisteredUserId) {
        print('✅ Device already registered with same token and userId');
        onResult(true);
        return;
      }
      
      // ایجاد درخواست ثبت
      final request = RegisterDeviceRequest(
        userId: userId,
        walletId: walletId,
        deviceToken: deviceToken!,
        deviceName: deviceName,
        deviceType: 'flutter',
      );
      
      Exception? lastException;
      bool registrationSuccess = false;
      
      // حلقه تلاش مجدد
      for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {
        try {
          print('📱 Attempt $attempt of $MAX_RETRY_ATTEMPTS to register device. Request: $request');
          
          // ارسال درخواست با timeout
          final response = await _apiService.registerDevice(
            userId: userId,
            walletId: walletId,
            deviceToken: deviceToken,
            deviceName: deviceName,
            deviceType: 'flutter',
          ).timeout(Duration(milliseconds: API_TIMEOUT));
          
          // بررسی موفقیت بر اساس response
          final message = response.message ?? '';
          final isSuccessfulByMessage = message.toLowerCase().contains('به‌روزرسانی شد') ||
                                       message.toLowerCase().contains('ثبت شد') ||
                                       message.toLowerCase().contains('توکن دستگاه جدید') ||
                                       message.toLowerCase().contains('توکن دستگاه موجود') ||
                                       message.toLowerCase().contains('شناسه') ||
                                       message.toLowerCase().contains('updated') ||
                                       message.toLowerCase().contains('successful') ||
                                       message.toLowerCase().contains('registered') ||
                                       message.toLowerCase().contains('device token');
          
          final isActuallySuccessful = response.success || isSuccessfulByMessage;
          
          print('📱 Final success determination: response.success=${response.success}, successByMessage=$isSuccessfulByMessage, finalResult=$isActuallySuccessful');
          
          if (isActuallySuccessful) {
            print('✅ Device registration successful on attempt $attempt');
            
            // ذخیره اطلاعات ثبت
            await SecureStorage.instance.saveDeviceToken(deviceToken);
            await SecureStorage.instance.saveSecureData('last_registered_userid', userId);
            
            registrationSuccess = true;
            break;
          } else {
            final errorMessage = response.message ?? 'Unknown registration error';
            print('❌ Registration failed on attempt $attempt: $errorMessage');
            print('❌ Expected success=true but got success=${response.success}');
            
            lastException = Exception(errorMessage);
            
            if (attempt < MAX_RETRY_ATTEMPTS) {
              final delayTime = RETRY_DELAY * attempt;
              print('📱 Retrying in ${delayTime}ms...');
              await Future.delayed(Duration(milliseconds: delayTime));
            }
          }
        } catch (e) {
          print('❌ Exception on attempt $attempt: $e');
          lastException = e as Exception;
          
          if (attempt < MAX_RETRY_ATTEMPTS) {
            final delayTime = RETRY_DELAY * attempt;
            print('📱 Retrying in ${delayTime}ms...');
            await Future.delayed(Duration(milliseconds: delayTime));
          }
        }
      }
      
      if (registrationSuccess) {
        print('✅ Device registration completed successfully');
        onResult(true);
      } else {
        print('❌ Device registration failed after all attempts. Last error: ${lastException?.toString()}');
        onResult(false);
      }
    } catch (e) {
      print('❌ Unexpected error in device registration: $e');
      onResult(false);
    }
  }
  
  /// ثبت دستگاه (مشابه registerDevice در Kotlin)
  Future<bool> registerDevice({
    required String userId,
    required String walletId,
  }) async {
    try {
      final deviceName = await _getDeviceName();
      await Future.delayed(Duration(milliseconds: 3000)); // تأخیر مشابه Kotlin
      
      final deviceToken = await _initializeFirebaseAndGetToken();
      
      if (!_isProvisioningComplete(userId, walletId, deviceToken)) {
        print('❌ Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken');
        return false;
      }
      
      // بررسی ثبت قبلی
      final lastRegisteredToken = await SecureStorage.instance.getDeviceToken();
      final lastRegisteredUserId = await SecureStorage.instance.getSecureData('last_registered_userid');
      
      if (deviceToken == lastRegisteredToken && userId == lastRegisteredUserId) {
        print('✅ Device already registered with same token and userId');
        return true;
      }
      
      final request = RegisterDeviceRequest(
        userId: userId,
        walletId: walletId,
        deviceToken: deviceToken!,
        deviceName: deviceName,
        deviceType: 'flutter',
      );
      
      Exception? lastException;
      
      // حلقه تلاش مجدد
      for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {
        try {
          print('📱 Attempt $attempt of $MAX_RETRY_ATTEMPTS to register device. Request: $request');
          
          final response = await _apiService.registerDevice(
            userId: userId,
            walletId: walletId,
            deviceToken: deviceToken,
            deviceName: deviceName,
            deviceType: 'flutter',
          ).timeout(Duration(milliseconds: API_TIMEOUT));
          
          // بررسی موفقیت
          final message = response.message ?? '';
          final isSuccessfulByMessage = message.toLowerCase().contains('به‌روزرسانی شد') ||
                                       message.toLowerCase().contains('ثبت شد') ||
                                       message.toLowerCase().contains('توکن دستگاه جدید') ||
                                       message.toLowerCase().contains('توکن دستگاه موجود') ||
                                       message.toLowerCase().contains('شناسه') ||
                                       message.toLowerCase().contains('updated') ||
                                       message.toLowerCase().contains('successful') ||
                                       message.toLowerCase().contains('registered') ||
                                       message.toLowerCase().contains('device token');
          
          final isActuallySuccessful = response.success || isSuccessfulByMessage;
          
          if (isActuallySuccessful) {
            print('✅ Device registration successful on attempt $attempt');
            
            // ذخیره اطلاعات
            await SecureStorage.instance.saveDeviceToken(deviceToken);
            await SecureStorage.instance.saveSecureData('last_registered_userid', userId);
            
            return true;
          } else {
            final errorMessage = response.message ?? 'Unknown registration error';
            print('❌ Registration failed on attempt $attempt: $errorMessage');
            
            lastException = Exception(errorMessage);
            
            if (attempt < MAX_RETRY_ATTEMPTS) {
              final delayTime = RETRY_DELAY * attempt;
              print('📱 Retrying in ${delayTime}ms...');
              await Future.delayed(Duration(milliseconds: delayTime));
            }
          }
        } catch (e) {
          print('❌ Exception on attempt $attempt: $e');
          lastException = e as Exception;
          
          if (attempt < MAX_RETRY_ATTEMPTS) {
            final delayTime = RETRY_DELAY * attempt;
            print('📱 Retrying in ${delayTime}ms...');
            await Future.delayed(Duration(milliseconds: delayTime));
          }
        }
      }
      
      print('❌ Device registration failed after all attempts. Last error: ${lastException?.toString()}');
      return false;
    } catch (e) {
      print('❌ Unexpected error in device registration: $e');
      return false;
    }
  }
  
  /// بررسی و ثبت مجدد دستگاه (مشابه checkAndRegisterDevice در Kotlin)
  Future<bool> checkAndRegisterDevice({
    required String userId,
    required String walletId,
  }) async {
    try {
      final deviceToken = await _initializeFirebaseAndGetToken();
      
      if (!_isProvisioningComplete(userId, walletId, deviceToken)) {
        print('❌ Provisioning incomplete: userId=$userId, walletId=$walletId, deviceToken=$deviceToken');
        return false;
      }
      
      final lastRegisteredToken = await SecureStorage.instance.getDeviceToken();
      final lastRegisteredUserId = await SecureStorage.instance.getSecureData('last_registered_userid');
      
      if (deviceToken != lastRegisteredToken || userId != lastRegisteredUserId) {
        print('📱 Token or userId changed, re-registering device');
        return await registerDevice(userId: userId, walletId: walletId);
      } else {
        print('✅ Device already registered with current token and userId');
        return true;
      }
    } catch (e) {
      print('❌ Error in checkAndRegisterDevice: $e');
      return false;
    }
  }
  
  /// دریافت نام دستگاه
  Future<String> _getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.name;
      } else if (kIsWeb) {
        return 'Web Browser';
      }
      return 'Unknown Device';
    } catch (e) {
      print('Error getting device name: $e');
      return 'Unknown Device';
    }
  }
  
  /// دریافت توکن دستگاه
  Future<String> _getDeviceToken() async {
    try {
      // تلاش برای دریافت توکن از ذخیره‌سازی
      final savedToken = await SecureStorage.instance.getDeviceToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        return savedToken;
      }
      
      // تولید توکن جدید
      final deviceInfo = await _getDeviceInfo();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final token = '${deviceInfo['platform']}_${deviceInfo['deviceName']}_$timestamp';
      
      // ذخیره توکن جدید
      await SecureStorage.instance.saveDeviceToken(token);
      
      return token;
    } catch (e) {
      print('Error getting device token: $e');
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  /// دریافت اطلاعات دستگاه
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'platform': 'Android',
          'deviceName': '${androidInfo.brand} ${androidInfo.model}',
          'version': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'brand': androidInfo.brand,
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'deviceId': androidInfo.id,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'platform': 'iOS',
          'deviceName': iosInfo.name,
          'version': iosInfo.systemVersion,
          'model': iosInfo.model,
          'localizedModel': iosInfo.localizedModel,
          'identifierForVendor': iosInfo.identifierForVendor,
        };
      } else if (kIsWeb) {
        return {
          'platform': 'Web',
          'deviceName': 'Web Browser',
          'version': 'Unknown',
        };
      }
      
      return {
        'platform': 'Unknown',
        'deviceName': 'Unknown Device',
        'version': 'Unknown',
      };
    } catch (e) {
      print('Error getting device info: $e');
      return {
        'platform': 'Unknown',
        'deviceName': 'Unknown Device',
        'version': 'Unknown',
      };
    }
  }
  
  /// حذف ثبت دستگاه
  Future<bool> unregisterDevice({
    required String userId,
    required String walletId,
  }) async {
    try {
      print('🗑️ Unregistering device for UserID: $userId, WalletID: $walletId');
      
      // حذف اطلاعات دستگاه از ذخیره‌سازی محلی
      await _removeDeviceInfo(userId, walletId);
      
      // TODO: ارسال درخواست حذف به سرور (اگر API موجود باشد)
      
      print('✅ Device unregistered successfully');
      return true;
      
    } catch (e) {
      print('❌ Error unregistering device: $e');
      return false;
    }
  }
  
  /// ذخیره اطلاعات دستگاه
  Future<void> _saveDeviceInfo(
    String userId,
    String walletId,
    String deviceToken,
    String deviceName,
  ) async {
    try {
      final deviceInfo = {
        'userId': userId,
        'walletId': walletId,
        'deviceToken': deviceToken,
        'deviceName': deviceName,
        'registeredAt': DateTime.now().toIso8601String(),
      };
      
      final key = 'DeviceInfo_${userId}_$walletId';
      await SecureStorage.instance.saveSecureJson(key, deviceInfo);
      
      print('💾 Device info saved');
    } catch (e) {
      print('Error saving device info: $e');
    }
  }
  
  /// بررسی آیا دستگاه ثبت شده
  Future<bool> _isDeviceRegistered(String userId, String walletId) async {
    try {
      final key = 'DeviceInfo_${userId}_$walletId';
      final deviceInfo = await SecureStorage.instance.getSecureJson(key);
      
      if (deviceInfo != null) {
        final registeredAt = DateTime.tryParse(deviceInfo['registeredAt'] ?? '');
        if (registeredAt != null) {
          // بررسی آیا ثبت کمتر از 24 ساعت پیش بوده
          final hoursSinceRegistration = DateTime.now().difference(registeredAt).inHours;
          return hoursSinceRegistration < 24;
        }
      }
      
      return false;
    } catch (e) {
      print('Error checking device registration: $e');
      return false;
    }
  }
  
  /// حذف اطلاعات دستگاه
  Future<void> _removeDeviceInfo(String userId, String walletId) async {
    try {
      final key = 'DeviceInfo_${userId}_$walletId';
      await SecureStorage.instance.deleteSecureData(key);
      
      print('🗑️ Device info removed');
    } catch (e) {
      print('Error removing device info: $e');
    }
  }
  
  /// دریافت اطلاعات ثبت دستگاه
  Future<Map<String, dynamic>?> getDeviceRegistrationInfo(String userId, String walletId) async {
    try {
      final key = 'DeviceInfo_${userId}_$walletId';
      return await SecureStorage.instance.getSecureJson(key);
    } catch (e) {
      print('Error getting device registration info: $e');
      return null;
    }
  }
  
  /// دریافت تمام دستگاه‌های ثبت شده
  Future<List<Map<String, dynamic>>> getAllRegisteredDevices() async {
    try {
      final allKeys = await SecureStorage.instance.getAllKeys();
      final deviceKeys = allKeys.where((key) => key.startsWith('DeviceInfo_')).toList();
      
      final devices = <Map<String, dynamic>>[];
      
      for (final key in deviceKeys) {
        final deviceInfo = await SecureStorage.instance.getSecureJson(key);
        if (deviceInfo != null) {
          devices.add(deviceInfo);
        }
      }
      
      return devices;
    } catch (e) {
      print('Error getting all registered devices: $e');
      return [];
    }
  }
  
  /// پاک کردن تمام اطلاعات دستگاه‌ها
  Future<void> clearAllDeviceInfo() async {
    try {
      final allKeys = await SecureStorage.instance.getAllKeys();
      final deviceKeys = allKeys.where((key) => key.startsWith('DeviceInfo_')).toList();
      
      for (final key in deviceKeys) {
        await SecureStorage.instance.deleteSecureData(key);
      }
      
      print('🗑️ All device info cleared');
    } catch (e) {
      print('Error clearing device info: $e');
    }
  }
} 