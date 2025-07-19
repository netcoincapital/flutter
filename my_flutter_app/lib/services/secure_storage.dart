import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
      accessibility: KeychainAccessibility.first_unlock_this_device,
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
    } catch (e) {
      print('Error clearing secure data: $e');
      rethrow;
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