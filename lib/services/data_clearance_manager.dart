import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../services/device_registration_manager.dart';
import '../services/language_manager.dart';
import '../services/wallet_state_manager.dart';

class DataClearanceManager {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  /// Clear all app data and reset to factory settings
  static Future<void> clearAllData(BuildContext context) async {
    try {
      print('🗑️ Starting complete data clearance...');
      
      // Step 1: Clear Secure Storage
      await _clearSecureStorage();
      
      // Step 2: Clear SharedPreferences
      await _clearSharedPreferences();
      
      // Step 3: Clear Cache
      await _clearCache();
      
      // Step 4: Unregister device from server
      await _unregisterDevice();
      
      // Step 5: Reset language to default
      await _resetLanguage(context);
      
      // Step 6: Clear QR scan data
      await _clearQRData();
      
      // Step 7: Reset wallet state
      await _resetWalletState();
      
      print('✅ Complete data clearance finished');
      
      // Show success message
      _showSuccessMessage(context);
      
    } catch (e) {
      print('❌ Error during data clearance: $e');
      _showErrorMessage(context, e.toString());
    }
  }

  /// Clear all secure storage data
  static Future<void> _clearSecureStorage() async {
    try {
      await _secureStorage.deleteAll();
      print('✅ Secure storage cleared');
    } catch (e) {
      print('❌ Error clearing secure storage: $e');
    }
  }

  /// Clear all SharedPreferences data
  static Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      print('✅ SharedPreferences cleared');
    } catch (e) {
      print('❌ Error clearing SharedPreferences: $e');
    }
  }

  /// Clear app cache
  static Future<void> _clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
        print('✅ Cache cleared');
      }
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }

  /// Unregister device from server
  static Future<void> _unregisterDevice() async {
    try {
      // Get current user and wallet info before clearing
      final userId = await _getUserIdBeforeClear();
      final walletId = await _getWalletIdBeforeClear();
      
      if (userId != null && walletId != null) {
        await DeviceRegistrationManager.instance.unregisterDevice(
          userId: userId,
          walletId: walletId,
        );
        print('✅ Device unregistered from server');
      } else {
        print('⚠️ No device registration info found');
      }
    } catch (e) {
      print('❌ Error unregistering device: $e');
    }
  }

  /// Reset language to default (English)
  static Future<void> _resetLanguage(BuildContext context) async {
    try {
      await LanguageManager.resetToDefault(context);
      print('✅ Language reset to default');
    } catch (e) {
      print('❌ Error resetting language: $e');
    }
  }

  /// Clear QR scan data
  static Future<void> _clearQRData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_scan_result');
      await prefs.remove('return_screen');
      print('✅ QR scan data cleared');
    } catch (e) {
      print('❌ Error clearing QR data: $e');
    }
  }

  /// Reset wallet state
  static Future<void> _resetWalletState() async {
    try {
      await WalletStateManager.instance.clearAllData();
      print('✅ Wallet state reset');
    } catch (e) {
      print('❌ Error resetting wallet state: $e');
    }
  }

  /// Get User ID before clearing (for device unregistration)
  static Future<String?> _getUserIdBeforeClear() async {
    try {
      return await _secureStorage.read(key: 'UserID');
    } catch (e) {
      print('❌ Error getting User ID: $e');
      return null;
    }
  }

  /// Get Wallet ID before clearing (for device unregistration)
  static Future<String?> _getWalletIdBeforeClear() async {
    try {
      return await _secureStorage.read(key: 'WalletID');
    } catch (e) {
      print('❌ Error getting Wallet ID: $e');
      return null;
    }
  }

  /// Clear specific data types
  static Future<void> clearWalletData() async {
    try {
      await _secureStorage.delete(key: 'UserID');
      await _secureStorage.delete(key: 'WalletID');
      await _secureStorage.delete(key: 'selected_wallet');
      await _secureStorage.delete(key: 'user_wallets');
      print('✅ Wallet data cleared');
    } catch (e) {
      print('❌ Error clearing wallet data: $e');
    }
  }

  static Future<void> clearSettingsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auto_lock_timeout_millis');
      await prefs.remove('last_background_time');
      await prefs.remove('selected_language');
      print('✅ Settings data cleared');
    } catch (e) {
      print('❌ Error clearing settings data: $e');
    }
  }

  static Future<void> clearNotificationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notification_settings');
      await prefs.remove('fcm_token');
      print('✅ Notification data cleared');
    } catch (e) {
      print('❌ Error clearing notification data: $e');
    }
  }

  /// Check if app is in fresh install state
  static Future<bool> isFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys.isEmpty;
    } catch (e) {
      print('❌ Error checking fresh install: $e');
      return true; // Assume fresh install on error
    }
  }

  /// Get data usage statistics
  static Future<Map<String, dynamic>> getDataUsageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secureKeys = await _secureStorage.readAll();
      
      return {
        'sharedPreferencesKeys': prefs.getKeys().length,
        'secureStorageKeys': secureKeys.length,
        'isFreshInstall': await isFreshInstall(),
      };
    } catch (e) {
      print('❌ Error getting data usage stats: $e');
      return {};
    }
  }

  /// Show success message
  static void _showSuccessMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All data cleared successfully. App will restart.'),
        backgroundColor: Color(0xFF16B369),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Show error message
  static void _showErrorMessage(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error clearing data: $error'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Factory reset with confirmation
  static Future<void> factoryReset(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(context);
    if (confirmed) {
      await clearAllData(context);
      // Restart app or navigate to initial screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/import-create',
        (route) => false,
      );
    }
  }

  /// Show confirmation dialog
  static Future<bool> _showConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Factory Reset'),
        content: const Text(
          'This will delete all your data including:\n'
          '• Wallets and private keys\n'
          '• Settings and preferences\n'
          '• Transaction history\n'
          '• Device registration\n\n'
          'This action cannot be undone. Are you sure?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    ) ?? false;
  }
} 