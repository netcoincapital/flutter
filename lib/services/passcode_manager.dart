import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages passcode security and encryption
class PasscodeManager {
  static const String _passcodeHashKey = 'passcode_hash';
  static const String _attemptsKey = 'failed_attempts';
  static const String _lockoutUntilKey = 'lockout_until';
  static const String _encryptedKeysKey = 'encrypted_private_keys';
  
  static const int _maxAttempts = 5;
  static const int _lockoutDuration = 300; // 5 minutes
  static const int _passcodeLength = 6;
  
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  /// Check if passcode is set
  static Future<bool> isPasscodeSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passcodeHashKey) != null;
  }
  
  /// Set a new passcode
  static Future<bool> setPasscode(String passcode) async {
    if (passcode.length != _passcodeLength) {
      throw Exception('Passcode must be $_passcodeLength digits');
    }
    
    if (!_isNumeric(passcode)) {
      throw Exception('Passcode must contain only numbers');
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = _generateSalt();
      final hash = _hashPasscode(passcode, salt);
      
      await prefs.setString(_passcodeHashKey, hash);
      await prefs.setString('passcode_salt', salt);
      
      // Reset attempts
      await prefs.remove(_attemptsKey);
      await prefs.remove(_lockoutUntilKey);
      
      return true;
    } catch (e) {
      print('Error setting passcode: $e');
      return false;
    }
  }
  
  /// Verify passcode
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
      
      final prefs = await SharedPreferences.getInstance();
      final savedHash = prefs.getString(_passcodeHashKey);
      final salt = prefs.getString('passcode_salt');
      
      if (savedHash == null || salt == null) {
        return false;
      }
      
      final hash = _hashPasscode(passcode, salt);
      final isValid = hash == savedHash;
      
      if (isValid) {
        // Reset attempts on successful verification
        await prefs.remove(_attemptsKey);
        await prefs.remove(_lockoutUntilKey);
      } else {
        // Record failed attempt
        await _recordFailedAttempt();
      }
      
      return isValid;
    } catch (e) {
      print('Error verifying passcode: $e');
      return false;
    }
  }
  
  /// Get remaining attempts
  static Future<int> getRemainingAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_attemptsKey) ?? 0;
      return _maxAttempts - attempts;
    } catch (e) {
      return _maxAttempts;
    }
  }
  
  /// Check if wallet is locked
  static Future<bool> isLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutUntil = prefs.getInt(_lockoutUntilKey);
      
      if (lockoutUntil != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (now < lockoutUntil) {
          return true;
        } else {
          // Lockout expired, reset
          await prefs.remove(_lockoutUntilKey);
          await prefs.remove(_attemptsKey);
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
      final prefs = await SharedPreferences.getInstance();
      final attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
      
      await prefs.setInt(_attemptsKey, attempts);
      
      if (attempts >= _maxAttempts) {
        // Lock wallet
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final lockoutUntil = now + _lockoutDuration;
        await prefs.setInt(_lockoutUntilKey, lockoutUntil);
      }
    } catch (e) {
      print('Error recording failed attempt: $e');
    }
  }
  
  /// Get lockout remaining time in seconds
  static Future<int> getLockoutRemainingTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutUntil = prefs.getInt(_lockoutUntilKey);
      
      if (lockoutUntil != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final remaining = lockoutUntil - now;
        return remaining > 0 ? remaining : 0;
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
  
  /// Clear all passcode data
  static Future<void> clearPasscode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_passcodeHashKey);
      await prefs.remove('passcode_salt');
      await prefs.remove(_attemptsKey);
      await prefs.remove(_lockoutUntilKey);
      await _secureStorage.delete(key: _encryptedKeysKey);
    } catch (e) {
      print('Error clearing passcode: $e');
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
} 