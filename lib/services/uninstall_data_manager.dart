import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

/// مدیریت پاکسازی خودکار داده‌ها هنگام حذف اپلیکیشن
class UninstallDataManager {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  /// بررسی و پاکسازی داده‌ها در صورت fresh install
  static Future<void> checkAndCleanupOnFreshInstall() async {
    try {
      print('🔍 iOS: Checking for fresh install...');
      
      // بررسی وجود داده‌های باقی‌مانده
      final hasRemainingData = await _hasRemainingData();
      
      // Do NOT perform cleanup automatically on app launch; only log status.
      if (!hasRemainingData) {
        print('✅ iOS: No remaining data found - clean install state');
      } else {
        print('⚠️ iOS: Remaining data detected (will not auto-clear). Use settings reset if needed.');
      }
      
      // بررسی مجدد بعد از پاکسازی
      // (Cleanup disabled by default to avoid wiping user token preferences.)
      
    } catch (e) {
      print('❌ Error during fresh install cleanup: $e');
    }
  }
  
  /// بررسی وجود داده‌های باقی‌مانده
  static Future<bool> _hasRemainingData() async {
    try {
      // بررسی SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      
      // بررسی SecureStorage
      final secureKeys = await _secureStorage.readAll();
      
      // بررسی فایل‌های کش
      final hasCacheFiles = await _hasCacheFiles();
      
      // بررسی داده‌های مهم
      final hasImportantData = await _hasImportantData();
      
      final hasData = prefsKeys.isNotEmpty || secureKeys.isNotEmpty || hasCacheFiles || hasImportantData;
      
      if (hasData) {
        print('🔍 Found remaining data:');
        print('  - SharedPreferences keys: ${prefsKeys.length}');
        print('  - SecureStorage keys: ${secureKeys.length}');
        print('  - Cache files: ${hasCacheFiles ? "Yes" : "No"}');
        print('  - Important data: ${hasImportantData ? "Yes" : "No"}');
      }
      
      return hasData;
    } catch (e) {
      print('❌ Error checking remaining data: $e');
      return false;
    }
  }
  
  /// بررسی وجود داده‌های مهم
  static Future<bool> _hasImportantData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // بررسی داده‌های مهم در SharedPreferences
      final importantPrefsKeys = [
        'passcode_hash',
        'passcode_enabled',
        'biometric_enabled',
        'auto_lock_timeout_millis',
        'last_background_time',
        'selected_currency',
        'selected_language',
        'notification_settings',
        'fcm_token',
        'push_notifications_enabled',
        'current_language',
        'current_currency',
        'auto_lock_timeout'
      ];
      
      for (final key in importantPrefsKeys) {
        if (prefs.containsKey(key)) {
          print('🔍 Found important SharedPreferences key: $key');
          return true;
        }
      }
      
      // بررسی داده‌های مهم در SecureStorage
      final secureKeys = await _secureStorage.readAll();
      final importantSecureKeys = secureKeys.keys.where((key) =>
        key.contains('UserID') ||
        key.contains('WalletID') ||
        key.contains('Mnemonic') ||
        key.contains('Passcode') ||
        key.contains('PrivateKey') ||
        key.contains('WalletSettings') ||
        key.contains('DeviceInfo')
      ).toList();
      
      if (importantSecureKeys.isNotEmpty) {
        print('🔍 Found important SecureStorage keys: ${importantSecureKeys.join(', ')}');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking important data: $e');
      return false;
    }
  }
  
  /// بررسی وجود فایل‌های کش
  static Future<bool> _hasCacheFiles() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync();
        return files.isNotEmpty;
      }
      return false;
    } catch (e) {
      print('❌ Error checking cache files: $e');
      return false;
    }
  }
  
  /// پاکسازی کامل تمام داده‌ها
  static Future<void> _performCompleteCleanup() async {
    try {
      print('🗑️ Starting complete data cleanup...');
      
      // Step 1: Clear SecureStorage
      await _clearSecureStorage();
      
      // Step 2: Clear SharedPreferences
      await _clearSharedPreferences();
      
      // Step 3: Clear Cache
      await _clearCache();
      
      // Step 4: Clear App Documents
      await _clearAppDocuments();
      
      // Step 5: Clear External Storage (Android)
      await _clearExternalStorage();
      
      print('✅ Complete data cleanup finished');
      
    } catch (e) {
      print('❌ Error during complete cleanup: $e');
    }
  }
  
  /// پاکسازی SecureStorage
  static Future<void> _clearSecureStorage() async {
    try {
      await _secureStorage.deleteAll();
      print('✅ SecureStorage cleared');
    } catch (e) {
      print('❌ Error clearing SecureStorage: $e');
    }
  }
  
  /// پاکسازی SharedPreferences
  static Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      print('✅ SharedPreferences cleared');
    } catch (e) {
      print('❌ Error clearing SharedPreferences: $e');
    }
  }
  
  /// پاکسازی کش
  static Future<void> _clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print('✅ Cache cleared');
      }
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }
  
  /// پاکسازی فایل‌های Documents اپلیکیشن
  static Future<void> _clearAppDocuments() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (await appDir.exists()) {
        final files = appDir.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          } else if (file is Directory) {
            await file.delete(recursive: true);
          }
        }
        print('✅ App documents cleared');
      }
    } catch (e) {
      print('❌ Error clearing app documents: $e');
    }
  }
  
  /// پاکسازی External Storage (Android)
  static Future<void> _clearExternalStorage() async {
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null && await externalDir.exists()) {
          final files = externalDir.listSync();
          for (final file in files) {
            if (file is File) {
              await file.delete();
            } else if (file is Directory) {
              await file.delete(recursive: true);
            }
          }
          print('✅ External storage cleared');
        }
      }
    } catch (e) {
      print('❌ Error clearing external storage: $e');
    }
  }
  
  /// پاکسازی داده‌های کیف پول
  static Future<void> clearWalletData() async {
    try {
      // حذف تمام کلیدهای مربوط به کیف پول از SecureStorage
      final allKeys = await _secureStorage.readAll();
      final walletKeys = allKeys.keys.where((key) => 
        key.contains('UserID') || 
        key.contains('WalletID') || 
        key.contains('Mnemonic') || 
        key.contains('PrivateKey') || 
        key.contains('WalletSettings') ||
        key.contains('DeviceInfo')
      ).toList();
      
      for (final key in walletKeys) {
        await _secureStorage.delete(key: key);
      }
      
      // حذف داده‌های کیف پول از SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      final walletPrefsKeys = prefsKeys.where((key) =>
        key.contains('wallet') ||
        key.contains('user_wallets') ||
        key.contains('selected_wallet')
      ).toList();
      
      for (final key in walletPrefsKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Wallet data cleared');
    } catch (e) {
      print('❌ Error clearing wallet data: $e');
    }
  }
  
  /// پاکسازی داده‌های پسکد
  static Future<void> clearPasscodeData() async {
    try {
      // حذف پسکد از SecureStorage
      await _secureStorage.delete(key: 'Passcode');
      
      // حذف پسکد از SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('passcode_hash');
      await prefs.remove('passcode_enabled');
      await prefs.remove('biometric_enabled');
      
      // حذف تمام کلیدهای مربوط به passcode از SecureStorage
      final allKeys = await _secureStorage.readAll();
      final passcodeKeys = allKeys.keys.where((key) => 
        key.toLowerCase().contains('passcode') ||
        key.toLowerCase().contains('biometric') ||
        key.toLowerCase().contains('security')
      ).toList();
      
      for (final key in passcodeKeys) {
        await _secureStorage.delete(key: key);
      }
      
      // حذف تمام کلیدهای مربوط به passcode از SharedPreferences
      final prefsKeys = prefs.getKeys();
      final passcodePrefsKeys = prefsKeys.where((key) =>
        key.toLowerCase().contains('passcode') ||
        key.toLowerCase().contains('biometric') ||
        key.toLowerCase().contains('security') ||
        key.toLowerCase().contains('lock')
      ).toList();
      
      for (final key in passcodePrefsKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Passcode data cleared');
    } catch (e) {
      print('❌ Error clearing passcode data: $e');
    }
  }
  
  /// پاکسازی داده‌های تنظیمات
  static Future<void> clearSettingsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // حذف تنظیمات اپلیکیشن
      final settingsKeys = [
        'selected_currency',
        'selected_language',
        'auto_lock_timeout_millis',
        'last_background_time',
        'notification_settings',
        'fcm_token',
        'push_notifications_enabled',
        'current_language',
        'current_currency',
        'auto_lock_timeout'
      ];
      
      for (final key in settingsKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Settings data cleared');
    } catch (e) {
      print('❌ Error clearing settings data: $e');
    }
  }
  
  /// پاکسازی داده‌های کش قیمت‌ها
  static Future<void> clearPriceCacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف کش قیمت‌ها
      final priceKeys = keys.where((key) =>
        key.startsWith('price_') ||
        key.startsWith('cached_prices') ||
        key.contains('prices_cache')
      ).toList();
      
      for (final key in priceKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Price cache data cleared');
    } catch (e) {
      print('❌ Error clearing price cache data: $e');
    }
  }
  
  /// پاکسازی داده‌های توکن‌ها
  static Future<void> clearTokenData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف تنظیمات توکن‌ها
      final tokenKeys = keys.where((key) =>
        key.startsWith('token_') ||
        key.contains('token_state') ||
        key.contains('token_order')
      ).toList();
      
      for (final key in tokenKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Token data cleared');
    } catch (e) {
      print('❌ Error clearing token data: $e');
    }
  }
  
  /// پاکسازی داده‌های تراکنش‌ها
  static Future<void> clearTransactionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف داده‌های تراکنش‌ها
      final transactionKeys = keys.where((key) =>
        key.contains('transaction') ||
        key.contains('tx_') ||
        key.contains('pending_')
      ).toList();
      
      for (final key in transactionKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Transaction data cleared');
    } catch (e) {
      print('❌ Error clearing transaction data: $e');
    }
  }
  
  /// پاکسازی داده‌های آدرس‌ها
  static Future<void> clearAddressBookData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف داده‌های دفترچه آدرس
      final addressKeys = keys.where((key) =>
        key.startsWith('wallet_name_') ||
        key.startsWith('wallet_address_') ||
        key.contains('address_book')
      ).toList();
      
      for (final key in addressKeys) {
        await prefs.remove(key);
      }
      
      print('✅ Address book data cleared');
    } catch (e) {
      print('❌ Error clearing address book data: $e');
    }
  }
  
  /// پاکسازی کامل تمام داده‌ها (برای استفاده در تنظیمات)
  static Future<void> performCompleteDataCleanup(BuildContext context) async {
    try {
      print('🗑️ Starting complete data cleanup from settings...');
      
      // پاکسازی تمام انواع داده‌ها
      await Future.wait([
        clearWalletData(),
        clearPasscodeData(),
        clearSettingsData(),
        clearPriceCacheData(),
        clearTokenData(),
        clearTransactionData(),
        clearAddressBookData(),
        _clearSecureStorage(),
        _clearSharedPreferences(),
        _clearCache(),
        _clearAppDocuments(),
        _clearExternalStorage(),
      ]);
      
      print('✅ Complete data cleanup finished');
      
      // نمایش پیام موفقیت
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمام داده‌ها با موفقیت پاک شدند'),
            backgroundColor: Color(0xFF16B369),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      print('❌ Error during complete data cleanup: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پاکسازی داده‌ها: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// بررسی وضعیت داده‌های باقی‌مانده
  static Future<Map<String, dynamic>> getDataStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secureKeys = await _secureStorage.readAll();
      final hasCacheFiles = await _hasCacheFiles();
      
      return {
        'sharedPreferencesKeys': prefs.getKeys().length,
        'secureStorageKeys': secureKeys.length,
        'hasCacheFiles': hasCacheFiles,
        'totalDataItems': prefs.getKeys().length + secureKeys.length + (hasCacheFiles ? 1 : 0),
      };
    } catch (e) {
      print('❌ Error getting data status: $e');
      return {};
    }
  }
} 