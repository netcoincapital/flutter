import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// سرویس ذخیره‌سازی امن برای تمام پلتفرم‌ها
class SecureStorage {
  static SecureStorage? _instance;
  static SecureStorage get instance => _instance ??= SecureStorage._();
  
  SecureStorage._();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: false, // جلوگیری از sync با iCloud
      accountName: 'com.coinceeper.app', // مشخص کردن App-specific storage
      groupId: null, // عدم استفاده از shared keychain group
    ),
  );

  /// ذخیره داده به صورت امن
  Future<void> saveSecureData(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      print('Error saving secure data: $e');
      rethrow;
    }
  }

  /// خواندن داده از ذخیره‌سازی امن
  Future<String?> getSecureData(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      print('Error reading secure data: $e');
      return null;
    }
  }

  /// ذخیره داده‌های JSON به صورت امن
  Future<void> saveSecureJson(String key, Map<String, dynamic> data) async {
    try {
      final jsonString = jsonEncode(data);
      await _storage.write(key: key, value: jsonString);
    } catch (e) {
      print('Error saving secure JSON: $e');
      rethrow;
    }
  }

  /// خواندن داده‌های JSON از ذخیره‌سازی امن
  Future<Map<String, dynamic>?> getSecureJson(String key) async {
    try {
      final jsonString = await _storage.read(key: key);
      if (jsonString != null) {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error reading secure JSON: $e');
      return null;
    }
  }

  /// حذف داده از ذخیره‌سازی امن
  Future<void> deleteSecureData(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      print('Error deleting secure data: $e');
      rethrow;
    }
  }

  /// پاک کردن تمام داده‌های امن
  Future<void> clearAllSecureData() async {
    try {
      await _storage.deleteAll();
      print('✅ All secure data cleared');
    } catch (e) {
      print('Error clearing secure data: $e');
      rethrow;
    }
  }

  /// بررسی و پاکسازی داده‌های orphaned در صورت نصب جدید
  Future<void> checkAndClearOrphanedData() async {
    try {
      // بررسی کن که آیا این اولین اجرای اپ پس از نصب است
      final isFirstRun = await _isFirstRunAfterInstall();
      
      if (isFirstRun) {
        print('🔍 iOS: First run after install detected, clearing orphaned keychain data');
        
        // پاک کردن تمام داده‌های keychain
        await clearAllSecureData();
        
        // ثبت که اولین اجرا انجام شده
        await _markFirstRunCompleted();
        
        print('✅ iOS: Orphaned keychain data cleared');
      } else {
        print('📱 iOS: Normal app launch, keychain data preserved');
      }
    } catch (e) {
      print('❌ Error in checkAndClearOrphanedData: $e');
    }
  }

  /// بررسی اینکه آیا این اولین اجرای اپ پس از نصب است
  Future<bool> _isFirstRunAfterInstall() async {
    try {
      // استفاده از SharedPreferences برای تشخیص نصب جدید
      // زیرا SharedPreferences همراه با اپ حذف می‌شود ولی Keychain باقی می‌ماند
      final prefs = await SharedPreferences.getInstance();
      final hasSharedPrefsData = prefs.getBool('app_initialized') ?? false;
      
      if (!hasSharedPrefsData) {
        // اگر SharedPreferences خالی است ولی Keychain دارای داده است،
        // یعنی اپ حذف و دوباره نصب شده
        final hasKeychainData = await _hasAnyKeychainData();
        
        if (hasKeychainData) {
          print('🔍 iOS: App reinstalled detected - SharedPreferences empty but Keychain has data');
          return true;
        } else {
          print('🔍 iOS: Fresh install detected - both SharedPreferences and Keychain are empty');
          return false; // نصب کاملاً جدید
        }
      }
      
      return false; // اجرای عادی
    } catch (e) {
      print('❌ Error checking first run: $e');
      return false;
    }
  }

  /// بررسی اینکه آیا Keychain دارای داده است
  Future<bool> _hasAnyKeychainData() async {
    try {
      final allData = await _storage.readAll();
      return allData.isNotEmpty;
    } catch (e) {
      print('❌ Error checking keychain data: $e');
      return false;
    }
  }

  /// علامت‌گذاری اینکه اپ initialize شده
  Future<void> _markFirstRunCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_initialized', true);
      await prefs.setString('app_install_timestamp', DateTime.now().millisecondsSinceEpoch.toString());
      
      // همچنین در keychain هم ذخیره کن
      await _storage.write(key: 'app_last_initialized', value: DateTime.now().millisecondsSinceEpoch.toString());
      
      print('✅ iOS: App marked as initialized');
    } catch (e) {
      print('❌ Error marking first run completed: $e');
    }
  }

  /// بررسی وجود کلید
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      print('Error checking key existence: $e');
      return false;
    }
  }

  /// دریافت تمام کلیدها
  Future<List<String>> getAllKeys() async {
    try {
      final keys = await _storage.readAll();
      return keys.keys.toList();
    } catch (e) {
      print('Error getting all keys: $e');
      return [];
    }
  }

  // ==================== WALLET SPECIFIC METHODS ====================

  /// ذخیره UserID برای کیف پول
  Future<void> saveUserId(String walletName, String userId) async {
    final key = 'UserID_$walletName';
    await saveSecureData(key, userId);
  }

  /// خواندن UserID کیف پول
  Future<String?> getUserIdForWallet(String walletName) async {
    final key = 'UserID_$walletName';
    return await getSecureData(key);
  }

  /// ذخیره Mnemonic کیف پول
  Future<void> saveMnemonic(String walletName, String userId, String mnemonic) async {
    final key = 'Mnemonic_${userId}_$walletName';
    await saveSecureData(key, mnemonic);
  }

  /// خواندن Mnemonic کیف پول
  Future<String?> getMnemonic(String walletName, String userId) async {
    final key = 'Mnemonic_${userId}_$walletName';
    return await getSecureData(key);
  }

  /// ذخیره Passcode
  Future<void> savePasscode(String passcode) async {
    await saveSecureData('Passcode', passcode);
  }

  /// خواندن Passcode
  Future<String?> getPasscode() async {
    return await getSecureData('Passcode');
  }

  // ==================== DEBUG METHODS ====================

  /// Debug: نمایش تمام کلیدهای موجود در keychain
  Future<void> debugPrintAllKeychainKeys() async {
    try {
      final allData = await _storage.readAll();
      print('=== KEYCHAIN DEBUG ===');
      print('Total keys in keychain: ${allData.length}');
      
      if (allData.isEmpty) {
        print('📱 Keychain is empty');
      } else {
        print('📱 Keychain keys:');
        for (final key in allData.keys) {
          print('   - $key');
        }
      }
      print('=== END KEYCHAIN DEBUG ===');
    } catch (e) {
      print('❌ Error debugging keychain: $e');
    }
  }

  /// Debug: پاک کردن اجباری تمام داده‌های keychain
  Future<void> debugForceClearAllData() async {
    try {
      print('🗑️ DEBUG: Force clearing all keychain data...');
      await clearAllSecureData();
      
      // همچنین SharedPreferences را هم پاک کن
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      print('✅ DEBUG: All data cleared (Keychain + SharedPreferences)');
    } catch (e) {
      print('❌ Error in debug force clear: $e');
    }
  }

  /// ذخیره تنظیمات کیف پول
  Future<void> saveWalletSettings(String walletName, Map<String, dynamic> settings) async {
    final key = 'WalletSettings_$walletName';
    await saveSecureJson(key, settings);
  }

  /// خواندن تنظیمات کیف پول
  Future<Map<String, dynamic>?> getWalletSettings(String walletName) async {
    final key = 'WalletSettings_$walletName';
    return await getSecureJson(key);
  }

  /// ذخیره لیست کیف پول‌ها
  Future<void> saveWalletsList(List<Map<String, String>> wallets) async {
    // Ensure all maps are Map<String, String>
    final walletsAsString = wallets.map((w) => w.map((k, v) => MapEntry(k, v.toString()))).toList();
    await saveSecureJson('user_wallets', {'wallets': walletsAsString});
  }

  /// خواندن لیست کیف پول‌ها
  Future<List<Map<String, String>>> getWalletsList() async {
    final data = await getSecureJson('user_wallets');
    if (data != null && data['wallets'] != null) {
      // Convert each map to Map<String, String>
      return List<Map<String, String>>.from(
        (data['wallets'] as List).map(
          (item) => Map<String, String>.from(item as Map),
        ),
      );
    }
    return [];
  }

  /// ذخیره activeTokens برای کیف پول (جدید)
  Future<void> saveActiveTokens(String walletName, String userId, List<String> activeTokens) async {
    final key = 'ActiveTokens_${userId}_$walletName';
    await saveSecureJson(key, {'tokens': activeTokens});
    print('📝 Saved ${activeTokens.length} active tokens for wallet: $walletName');
  }

  /// خواندن activeTokens کیف پول (جدید)
  Future<List<String>> getActiveTokens(String walletName, String userId) async {
    final key = 'ActiveTokens_${userId}_$walletName';
    final data = await getSecureJson(key);
    if (data != null && data['tokens'] != null) {
      return List<String>.from(data['tokens'] as List);
    }
    return []; // بازگرداندن لیست خالی اگر هیچ توکنی فعال نباشد
  }

  /// ذخیره کش موجودی‌ها برای کیف پول خاص (جدید)
  Future<void> saveWalletBalanceCache(String walletName, String userId, Map<String, double> balances) async {
    final key = 'BalanceCache_${userId}_$walletName';
    await saveSecureJson(key, balances.map((k, v) => MapEntry(k, v.toString())));
    print('💾 Saved balance cache for wallet: $walletName (${balances.length} tokens)');
  }

  /// خواندن کش موجودی‌ها برای کیف پول خاص (جدید)
  Future<Map<String, double>> getWalletBalanceCache(String walletName, String userId) async {
    final key = 'BalanceCache_${userId}_$walletName';
    final data = await getSecureJson(key);
    if (data != null) {
      return data.map((k, v) => MapEntry(k, double.tryParse(v.toString()) ?? 0.0));
    }
    return {};
  }

  /// حذف کش موجودی‌ها برای کیف پول خاص (جدید)
  Future<void> clearWalletBalanceCache(String walletName, String userId) async {
    final key = 'BalanceCache_${userId}_$walletName';
    await deleteSecureData(key);
    print('🗑️ Cleared balance cache for wallet: $walletName');
  }

  /// ذخیره کیف پول انتخاب شده (مطابق با Kotlin)
  Future<void> saveSelectedWallet(String walletName, String userId) async {
    await saveSecureData('selected_wallet', walletName);
    await saveSecureData('selected_user_id', userId);
  }

  /// خواندن کیف پول انتخاب شده (مطابق با Kotlin)
  Future<String?> getSelectedWallet() async {
    return await getSecureData('selected_wallet');
  }

  /// ذخیره userId انتخاب‌شده
  Future<void> saveSelectedUserId(String userId) async {
    await saveSecureData('selected_user_id', userId);
  }

  /// دریافت userId انتخاب‌شده
  Future<String?> getSelectedUserId() async {
    return await getSecureData('selected_user_id');
  }

  /// دریافت UserID برای کیف پول انتخاب شده (مطابق با Kotlin)
  Future<String?> getUserIdForSelectedWallet() async {
    final selectedWallet = await getSelectedWallet();
    if (selectedWallet != null) {
      return await getUserIdForWallet(selectedWallet);
    }
    return null;
  }

  // ==================== SECURITY METHODS ====================

  /// ذخیره کلید خصوصی
  Future<void> savePrivateKey(String walletName, String privateKey) async {
    final key = 'PrivateKey_$walletName';
    await saveSecureData(key, privateKey);
  }

  /// خواندن کلید خصوصی
  Future<String?> getPrivateKey(String walletName) async {
    final key = 'PrivateKey_$walletName';
    return await getSecureData(key);
  }

  /// دریافت کلید خصوصی برای کیف پول انتخاب شده
  Future<String?> getPrivateKeyForSelectedWallet() async {
    final selectedWallet = await getSelectedWallet();
    if (selectedWallet != null) {
      return await getPrivateKey(selectedWallet);
    }
    return null;
  }

  // ==================== COMPATIBILITY METHODS ====================

  /// دریافت UserID (متد سازگاری)
  static Future<String?> getUserId() async {
    try {
      return await instance.getUserIdForSelectedWallet();
    } catch (e) {
      print('Error getting User ID: $e');
      return null;
    }
  }

  /// دریافت کیف پول انتخاب شده و UserID (مطابق با Kotlin)
  static Future<Map<String, String?>> getSelectedWalletInfo() async {
    try {
      final selectedWallet = await instance.getSelectedWallet();
      final selectedUserId = await instance.getUserIdForSelectedWallet();
      
      return {
        'walletName': selectedWallet,
        'userId': selectedUserId,
      };
    } catch (e) {
      print('Error getting selected wallet info: $e');
      return {'walletName': null, 'userId': null};
    }
  }

  /// دریافت WalletID (متد سازگاری)
  static Future<String?> getWalletId() async {
    try {
      final selectedWallet = await instance.getSelectedWallet();
      return selectedWallet;
    } catch (e) {
      print('Error getting Wallet ID: $e');
      return null;
    }
  }

  /// ذخیره توکن دستگاه
  Future<void> saveDeviceToken(String deviceToken) async {
    await saveSecureData('DeviceToken', deviceToken);
  }

  /// خواندن توکن دستگاه
  Future<String?> getDeviceToken() async {
    return await getSecureData('DeviceToken');
  }

  /// ذخیره تنظیمات امنیتی
  Future<void> saveSecuritySettings(Map<String, dynamic> settings) async {
    await saveSecureJson('SecuritySettings', settings);
  }

  /// خواندن تنظیمات امنیتی
  Future<Map<String, dynamic>?> getSecuritySettings() async {
    return await getSecureJson('SecuritySettings');
  }
} 