import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مدیر ذخیره‌سازی یکپارچه برای iOS و Android
/// این کلاس تفاوت‌های بین پلتفرم‌ها را مدیریت می‌کند
class PlatformStorageManager {
  static PlatformStorageManager? _instance;
  static PlatformStorageManager get instance => _instance ??= PlatformStorageManager._();
  
  PlatformStorageManager._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: false, // جلوگیری از sync با iCloud
      accountName: 'com.coinceeper.app', // مشخص کردن App-specific storage
      groupId: null, // عدم استفاده از shared keychain group
    ),
  );

  /// ذخیره داده با استراتژی مناسب هر پلتفرم
  Future<void> saveData(String key, String value, {bool isCritical = false}) async {
    try {
      if (Platform.isIOS) {
        // iOS: استراتژی Triple Storage برای اطمینان بیشتر
        await _saveDataIOS(key, value, isCritical).timeout(const Duration(seconds: 3));
      } else if (Platform.isAndroid) {
        // Android: استراتژی Dual Storage
        await _saveDataAndroid(key, value, isCritical).timeout(const Duration(seconds: 3));
      } else {
        // Web/Desktop: فقط SharedPreferences
        await _saveDataGeneric(key, value).timeout(const Duration(seconds: 3));
      }
      
      print('💾 Platform storage saved: $key (critical: $isCritical, platform: ${Platform.operatingSystem})');
    } catch (e) {
      print('❌ Error saving platform data: $e');
      rethrow;
    }
  }

  /// خواندن داده با بازیابی هوشمند
  Future<String?> getData(String key, {bool isCritical = false}) async {
    try {
      if (Platform.isIOS) {
        return await _getDataIOS(key, isCritical).timeout(const Duration(seconds: 3));
      } else if (Platform.isAndroid) {
        return await _getDataAndroid(key, isCritical).timeout(const Duration(seconds: 3));
      } else {
        return await _getDataGeneric(key).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      print('❌ Error getting platform data: $e');
      return null;
    }
  }

  /// حذف داده از همه مکان‌ها
  Future<void> deleteData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      
      // حذف از SharedPreferences
      await prefs.remove(key).timeout(const Duration(seconds: 2));
      
      // حذف از SecureStorage
      await _secureStorage.delete(key: key).timeout(const Duration(seconds: 3));
      
      // iOS: حذف از backup keys
      if (Platform.isIOS) {
        await _secureStorage.delete(key: '${key}_ios_backup').timeout(const Duration(seconds: 3));
        await prefs.remove('${key}_timestamp').timeout(const Duration(seconds: 2));
      }
      
      print('🗑️ Platform data deleted: $key');
    } catch (e) {
      print('❌ Error deleting platform data: $e');
    }
  }

  // ==================== iOS SPECIFIC METHODS ====================

  /// ذخیره‌سازی iOS با Triple Storage
  Future<void> _saveDataIOS(String key, String value, bool isCritical) async {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // 1. SharedPreferences (اولویت اول)
    await prefs.setString(key, value).timeout(const Duration(seconds: 2));
    await prefs.setInt('${key}_timestamp', timestamp).timeout(const Duration(seconds: 2));
    
    // 2. SecureStorage (backup اصلی)
    await _secureStorage.write(key: key, value: value).timeout(const Duration(seconds: 3));
    
    // 3. SecureStorage backup (برای critical data)
    if (isCritical) {
      await _secureStorage.write(key: '${key}_ios_backup', value: value).timeout(const Duration(seconds: 3));
    }
  }

  /// بازیابی iOS با استراتژی Cascade
  Future<String?> _getDataIOS(String key, bool isCritical) async {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    
    // 1. اول از SharedPreferences تلاش کن
    String? value = prefs.getString(key);
    if (value != null) {
      print('📱 iOS: Data found in SharedPreferences: $key');
      return value;
    }
    
    // 2. از SecureStorage اصلی
    value = await _secureStorage.read(key: key).timeout(const Duration(seconds: 3));
    if (value != null) {
      print('📱 iOS: Data recovered from SecureStorage: $key');
      
      // بازگردانی به SharedPreferences
      await prefs.setString(key, value).timeout(const Duration(seconds: 2));
      await prefs.setInt('${key}_timestamp', DateTime.now().millisecondsSinceEpoch).timeout(const Duration(seconds: 2));
      
      return value;
    }
    
    // 3. از iOS backup (فقط برای critical data)
    if (isCritical) {
      value = await _secureStorage.read(key: '${key}_ios_backup').timeout(const Duration(seconds: 3));
      if (value != null) {
        print('📱 iOS: Data recovered from backup: $key');
        
        // بازگردانی کامل
        await prefs.setString(key, value).timeout(const Duration(seconds: 2));
        await _secureStorage.write(key: key, value: value).timeout(const Duration(seconds: 3));
        
        return value;
      }
    }
    
    print('📱 iOS: No data found for key: $key');
    return null;
  }

  // ==================== ANDROID SPECIFIC METHODS ====================

  /// ذخیره‌سازی Android با Dual Storage
  Future<void> _saveDataAndroid(String key, String value, bool isCritical) async {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
    
    // 1. SharedPreferences (اصلی) - با تلاش مجدد در صورت خطا
    try {
      await prefs.setString(key, value).timeout(const Duration(seconds: 3));
      print('🤖 Android: SharedPreferences write successful for $key');
    } catch (e) {
      print('❌ Android: SharedPreferences write failed for $key: $e');
      // تلاش مجدد
      await Future.delayed(const Duration(milliseconds: 100));
      await prefs.setString(key, value).timeout(const Duration(seconds: 3));
      print('🤖 Android: SharedPreferences retry successful for $key');
    }
    
    // 2. SecureStorage (برای critical data و backup)
    if (isCritical) {
      try {
        await _secureStorage.write(key: key, value: value).timeout(const Duration(seconds: 5));
        print('🤖 Android: SecureStorage write successful for $key');
      } catch (e) {
        print('❌ Android: SecureStorage write failed for $key: $e');
        // در اندروید، اگر SecureStorage کار نکرد، حداقل SharedPreferences داریم
      }
    }
  }

  /// بازیابی Android
  Future<String?> _getDataAndroid(String key, bool isCritical) async {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    
    // 1. اول از SharedPreferences
    String? value = prefs.getString(key);
    if (value != null) {
      print('🤖 Android: Data found in SharedPreferences: $key');
      return value;
    }
    
    // 2. از SecureStorage (فقط برای critical data)
    if (isCritical) {
      value = await _secureStorage.read(key: key).timeout(const Duration(seconds: 3));
      if (value != null) {
        print('🤖 Android: Data recovered from SecureStorage: $key');
        
        // بازگردانی به SharedPreferences
        await prefs.setString(key, value).timeout(const Duration(seconds: 2));
        
        return value;
      }
    }
    
    print('🤖 Android: No data found for key: $key');
    return null;
  }

  // ==================== GENERIC METHODS ====================

  /// ذخیره‌سازی عمومی (Web/Desktop)
  Future<void> _saveDataGeneric(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// بازیابی عمومی (Web/Desktop)
  Future<String?> _getDataGeneric(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  // ==================== UTILITY METHODS ====================

  /// بررسی integrity داده‌ها بین storage ها
  Future<Map<String, dynamic>> checkDataIntegrity(String key) async {
    final prefs = await SharedPreferences.getInstance();
    
    final sharedPrefsValue = prefs.getString(key);
    final secureStorageValue = await _secureStorage.read(key: key);
    
    String? backupValue;
    if (Platform.isIOS) {
      backupValue = await _secureStorage.read(key: '${key}_ios_backup');
    }
    
    return {
      'key': key,
      'platform': Platform.operatingSystem,
      'shared_prefs': sharedPrefsValue != null ? 'EXISTS' : 'NULL',
      'secure_storage': secureStorageValue != null ? 'EXISTS' : 'NULL',
      'ios_backup': backupValue != null ? 'EXISTS' : 'NULL',
      'consistent': sharedPrefsValue == secureStorageValue,
    };
  }

  /// هماهنگ‌سازی داده‌ها بین storage ها
  Future<void> synchronizeStorages() async {
    try {
      print('🔄 Starting platform storage synchronization...');
      
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      int synced = 0;
      int errors = 0;
      
      for (final key in allKeys) {
        if (key.endsWith('_timestamp')) continue; // Skip timestamp keys
        
        try {
          final sharedValue = prefs.getString(key);
          if (sharedValue != null) {
            final secureValue = await _secureStorage.read(key: key);
            
            if (secureValue == null) {
              // Copy from SharedPreferences to SecureStorage
              await _secureStorage.write(key: key, value: sharedValue);
              synced++;
            } else if (secureValue != sharedValue) {
              // Conflict resolution: prefer SharedPreferences
              await _secureStorage.write(key: key, value: sharedValue);
              synced++;
            }
          }
        } catch (e) {
          print('❌ Error syncing key $key: $e');
          errors++;
        }
      }
      
      print('✅ Storage synchronization complete: $synced synced, $errors errors');
    } catch (e) {
      print('❌ Storage synchronization failed: $e');
    }
  }

  /// تمیز کردن storage های قدیمی
  Future<void> cleanupOldData({int maxAgeInDays = 30}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final maxAge = maxAgeInDays * 24 * 60 * 60 * 1000; // Convert to milliseconds
      
      final allKeys = prefs.getKeys();
      int cleaned = 0;
      
      for (final key in allKeys) {
        if (key.endsWith('_timestamp')) {
          final timestamp = prefs.getInt(key);
          if (timestamp != null && (currentTime - timestamp) > maxAge) {
            final dataKey = key.replaceAll('_timestamp', '');
            
            // Clean old data
            await deleteData(dataKey);
            cleaned++;
          }
        }
      }
      
      print('🧹 Cleaned up $cleaned old data entries');
    } catch (e) {
      print('❌ Cleanup failed: $e');
    }
  }
} 