import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'platform_storage_manager.dart';

/// Manages passcode security and encryption with platform-specific optimizations
class PasscodeManager {
  static const String _passcodeHashKey = 'passcode_hash';
  static const String _attemptsKey = 'failed_attempts';
  static const String _lockoutUntilKey = 'lockout_until';
  static const String _encryptedKeysKey = 'encrypted_private_keys';
  
  static const int _maxAttempts = 5;
  static const int _lockoutDuration = 300; // 5 minutes
  static const int _passcodeLength = 6;
  
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final PlatformStorageManager _platformStorage = PlatformStorageManager.instance;
  
  /// Check if passcode is set using platform-specific strategy
  static Future<bool> isPasscodeSet() async {
    try {
      // استفاده از platform-specific storage
      final hash = await _platformStorage.getData(_passcodeHashKey, isCritical: true);
      final salt = await _platformStorage.getData('passcode_salt', isCritical: true);
      
      final isSet = hash != null && salt != null;
      print('🔑 Passcode check result: $isSet');
      
      return isSet;
    } catch (e) {
      print('❌ Error checking passcode: $e');
      return false;
    }
  }
  
  /// Set a new passcode using platform-specific storage
  static Future<bool> setPasscode(String passcode) async {
    if (passcode.length != _passcodeLength) {
      throw Exception('Passcode must be $_passcodeLength digits');
    }
    
    if (!_isNumeric(passcode)) {
      throw Exception('Passcode must contain only numbers');
    }
    
    try {
      final salt = _generateSalt();
      final hash = _hashPasscode(passcode, salt);
      
      // ذخیره با استراتژی platform-specific
      await _platformStorage.saveData(_passcodeHashKey, hash, isCritical: true);
      await _platformStorage.saveData('passcode_salt', salt, isCritical: true);
      
      // Reset attempts
      await _platformStorage.deleteData(_attemptsKey);
      await _platformStorage.deleteData(_lockoutUntilKey);
      
      // CRITICAL: Mark app as used when passcode is set
      await _markAppAsUsedForPasscode();
      
      // CRITICAL: Enable passcode by default when it's set
      await _enablePasscodeByDefault();
      
      print('🔑 Passcode saved using platform-specific strategy');
      return true;
    } catch (e) {
      print('❌ Error setting passcode: $e');
      return false;
    }
  }
  
  /// Verify passcode using platform-specific storage
  static Future<bool> verifyPasscode(String passcode) async {
    if (passcode.length != _passcodeLength) {
      return false;
    }
    
    if (!_isNumeric(passcode)) {
      return false;
    }
    
    try {
      // Check if wallet is locked
      if (await isLocked()) {
        throw Exception('Wallet is locked. Please try again later.');
      }
      
      // استفاده از platform storage برای دریافت داده‌ها
      String? savedHash = await _platformStorage.getData(_passcodeHashKey, isCritical: true);
      String? salt = await _platformStorage.getData('passcode_salt', isCritical: true);
      
      if (savedHash == null || salt == null) {
        print('❌ No passcode data found in platform storage');
        return false;
      }
      
      final hash = _hashPasscode(passcode, salt);
      final isValid = hash == savedHash;
      
      if (isValid) {
        // Reset attempts on successful verification
        await _platformStorage.deleteData(_attemptsKey);
        await _platformStorage.deleteData(_lockoutUntilKey);
      } else {
        // Record failed attempt
        await _recordFailedAttempt();
      }
      
      return isValid;
    } catch (e) {
      print('❌ Error verifying passcode: $e');
      return false;
    }
  }
  
  /// Get remaining attempts
  static Future<int> getRemainingAttempts() async {
    try {
      final attemptsStr = await _platformStorage.getData(_attemptsKey);
      final attempts = attemptsStr != null ? int.tryParse(attemptsStr) ?? 0 : 0;
      return _maxAttempts - attempts;
    } catch (e) {
      return _maxAttempts;
    }
  }
  
  /// Check if wallet is locked
  static Future<bool> isLocked() async {
    try {
      final lockoutUntilStr = await _platformStorage.getData(_lockoutUntilKey);
      
      if (lockoutUntilStr != null) {
        final lockoutUntil = int.tryParse(lockoutUntilStr);
        if (lockoutUntil != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (now < lockoutUntil) {
            return true;
          } else {
            // Lockout expired, reset
            await _platformStorage.deleteData(_lockoutUntilKey);
            await _platformStorage.deleteData(_attemptsKey);
          }
        }
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// Record failed attempt
  static Future<void> _recordFailedAttempt() async {
    try {
      final attemptsStr = await _platformStorage.getData(_attemptsKey);
      final attempts = (attemptsStr != null ? int.tryParse(attemptsStr) ?? 0 : 0) + 1;
      
      await _platformStorage.saveData(_attemptsKey, attempts.toString());
      
      if (attempts >= _maxAttempts) {
        // Lock wallet
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final lockoutUntil = now + _lockoutDuration;
        await _platformStorage.saveData(_lockoutUntilKey, lockoutUntil.toString());
      }
    } catch (e) {
      print('❌ Error recording failed attempt: $e');
    }
  }
  
  /// Get lockout remaining time in seconds
  static Future<int> getLockoutRemainingTime() async {
    try {
      final lockoutUntilStr = await _platformStorage.getData(_lockoutUntilKey);
      
      if (lockoutUntilStr != null) {
        final lockoutUntil = int.tryParse(lockoutUntilStr);
        if (lockoutUntil != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final remaining = lockoutUntil - now;
          return remaining > 0 ? remaining : 0;
        }
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Encrypt private keys with passcode
  static Future<String> encryptPrivateKeys(String privateKeys, String passcode) async {
    try {
      final salt = _generateSalt();
      final key = _deriveKey(passcode, salt);
      final encrypted = _encrypt(privateKeys, key);
      
      // Store salt with encrypted data
      final data = {
        'salt': salt,
        'encrypted': encrypted,
      };
      
      return base64Encode(utf8.encode(jsonEncode(data)));
    } catch (e) {
      throw Exception('Failed to encrypt private keys: $e');
    }
  }
  
  /// Decrypt private keys with passcode
  static Future<String> decryptPrivateKeys(String encryptedData, String passcode) async {
    try {
      final data = jsonDecode(utf8.decode(base64Decode(encryptedData)));
      final salt = data['salt'];
      final encrypted = data['encrypted'];
      
      final key = _deriveKey(passcode, salt);
      return _decrypt(encrypted, key);
    } catch (e) {
      throw Exception('Failed to decrypt private keys: $e');
    }
  }
  
  /// Store encrypted private keys
  static Future<void> storeEncryptedKeys(String encryptedKeys) async {
    await _secureStorage.write(key: _encryptedKeysKey, value: encryptedKeys);
  }
  
  /// Get encrypted private keys
  static Future<String?> getEncryptedKeys() async {
    return await _secureStorage.read(key: _encryptedKeysKey);
  }
  
  /// Clear all passcode data using platform-specific cleanup
  static Future<void> clearPasscode() async {
    try {
      // استفاده از platform storage برای پاکسازی کامل
      await _platformStorage.deleteData(_passcodeHashKey);
      await _platformStorage.deleteData('passcode_salt');
      await _platformStorage.deleteData(_attemptsKey);
      await _platformStorage.deleteData(_lockoutUntilKey);
      
      // پاک کردن از SecureStorage (legacy cleanup)
      await _secureStorage.delete(key: _encryptedKeysKey);
      
      print('🔑 Passcode data cleared using platform-specific strategy');
    } catch (e) {
      print('❌ Error clearing passcode: $e');
    }
  }
  
  /// Generate random salt
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Encode(bytes);
  }
  
  /// Hash passcode with salt
  static String _hashPasscode(String passcode, String salt) {
    final data = utf8.encode(passcode + salt);
    final hash = sha256.convert(data);
    return hash.toString();
  }
  
  /// Derive encryption key from passcode
  static String _deriveKey(String passcode, String salt) {
    final data = utf8.encode(passcode + salt + 'key_derivation');
    final hash = sha256.convert(data);
    return hash.toString();
  }
  
  /// Simple encryption (in production, use proper encryption)
  static String _encrypt(String data, String key) {
    final bytes = utf8.encode(data);
    final keyBytes = utf8.encode(key);
    
    final encrypted = List<int>.generate(bytes.length, (i) {
      return bytes[i] ^ keyBytes[i % keyBytes.length];
    });
    
    return base64Encode(encrypted);
  }
  
  /// Simple decryption (in production, use proper decryption)
  static String _decrypt(String encrypted, String key) {
    final encryptedBytes = base64Decode(encrypted);
    final keyBytes = utf8.encode(key);
    
    final decrypted = List<int>.generate(encryptedBytes.length, (i) {
      return encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    
    return utf8.decode(decrypted);
  }
  
  /// Check if string is numeric
  static bool _isNumeric(String str) {
    return RegExp(r'^[0-9]+$').hasMatch(str);
  }

  /// Mark app as used when passcode is set (prevent false fresh install detection)
  static Future<void> _markAppAsUsedForPasscode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('passcode_set', true);
      await prefs.setString('last_passcode_action', DateTime.now().millisecondsSinceEpoch.toString());
      
      print('✅ App marked as used (passcode set) - fresh install detection will be more accurate');
    } catch (e) {
      print('❌ Error marking app as used for passcode: $e');
    }
  }

  /// Enable passcode by default when it's first set
  static Future<void> _enablePasscodeByDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Only set to enabled if not explicitly set before
      if (!prefs.containsKey('passcode_enabled')) {
        await prefs.setBool('passcode_enabled', true);
        print('✅ Passcode enabled by default on first setup');
      } else {
        print('🔑 Passcode enabled state already exists - keeping current setting');
      }
    } catch (e) {
      print('❌ Error enabling passcode by default: $e');
    }
  }
} 