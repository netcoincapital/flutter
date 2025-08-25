import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'secure_storage.dart';
import 'passcode_manager.dart';

/// Manages wallet state and navigation logic
class WalletStateManager {
  static WalletStateManager? _instance;
  static WalletStateManager get instance => _instance ??= WalletStateManager._();
  
  WalletStateManager._();

  /// Check if user has any wallet
  Future<bool> hasWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      return wallets.isNotEmpty;
    } catch (e) {
      print('Error checking wallet existence: $e');
      return false;
    }
  }

  /// Check if user has set up passcode
  Future<bool> hasPasscode() async {
    try {
      // Use PasscodeManager to check if passcode is set
      final isSet = await PasscodeManager.isPasscodeSet();
      print('🔑 Passcode set: $isSet');
      return isSet;
    } catch (e) {
      print('Error checking passcode existence: $e');
      return false;
    }
  }

  /// Check if user is authenticated (has wallet and passcode)
  Future<bool> isAuthenticated() async {
    try {
      final hasWalletData = await hasWallet();
      final hasPasscodeData = await hasPasscode();
      return hasWalletData && hasPasscodeData;
    } catch (e) {
      print('Error checking authentication: $e');
      return false;
    }
  }

  /// Check if a valid wallet exists (walletName, userID, mnemonic)
  Future<bool> hasValidWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      print('🔍 Checking ${wallets.length} wallets for validity');
      
      if (wallets.isEmpty) {
        print('❌ No wallets found in list');
        
        // iOS Fallback: Check SharedPreferences if keychain fails
        if (Platform.isIOS) {
          return await _checkValidWalletFallback();
        }
        
        return false;
      }
      
      // Check if at least one wallet has all required fields and a valid mnemonic
      for (int i = 0; i < wallets.length; i++) {
        final wallet = wallets[i];
        final walletName = wallet['walletName'];
        final userId = wallet['userID'];
        
        print('🔍 Checking wallet $i: $walletName (userId: $userId)');
        
        if (walletName?.isNotEmpty == true && userId?.isNotEmpty == true) {
          // Check if mnemonic exists in SecureStorage for this wallet
          try {
            final mnemonic = await SecureStorage.instance.getMnemonic(walletName!, userId!);
            if (mnemonic != null && mnemonic.isNotEmpty) {
              print('✅ Found valid wallet: $walletName with mnemonic');
              return true; // Found at least one valid wallet
            } else {
              print('❌ Wallet $walletName has no mnemonic');
            }
          } catch (e) {
            print('❌ Error checking mnemonic for wallet $walletName: $e');
            // Continue checking other wallets
          }
        } else {
          print('❌ Wallet $i has invalid name or userId');
        }
      }
      
      print('❌ No valid wallets found');
      return false; // No valid wallet found
    } catch (e) {
      print('Error checking valid wallet: $e');
      return false;
    }
  }

  /// Determine initial screen based on wallet and passcode state
  Future<String> getInitialScreen() async {
    try {
      print('🔍 Determining initial screen...');
      
      // Check if this is a fresh install
      final isFresh = await isFreshInstall();
      if (isFresh) {
        print('🆕 Fresh install detected - going to import-create');
        return '/import-create';
      }
      
      // Check for valid wallet
      final hasValidWalletData = await hasValidWallet();
      if (!hasValidWalletData) {
        print('⚠️ No valid wallet found - going to import-create');
        return '/import-create';
      }
      
      // Check for passcode
      final hasPasscodeData = await hasPasscode();
      if (!hasPasscodeData) {
        print('🔑 Valid wallet found but no passcode - going to passcode setup');
        return '/passcode-setup';
      }
      
      // اگر passcode تنظیم شده، همیشه به enter-passcode برود
      print('✅ Valid wallet and passcode found - going to enter-passcode');
      return '/enter-passcode';
      
    } catch (e) {
      print('❌ Error determining initial screen: $e');
      // On error, check if we have any data at all
      try {
        final keys = await SecureStorage.instance.getAllKeys();
        if (keys.isNotEmpty) {
          print('⚠️ Error occurred but found ${keys.length} keys - checking passcode state...');
          
          // در fallback نیز اگر passcode تنظیم شده، به enter-passcode برود
          try {
            final hasPasscodeData = await hasPasscode();
            if (hasPasscodeData) {
              print('⚠️ Fallback: passcode exists - going to enter-passcode');
              return '/enter-passcode';
            } else {
              print('⚠️ Fallback: no passcode - going to home');
              return '/home';
            }
          } catch (e2) {
            print('❌ Error checking passcode state in fallback: $e2');
            return '/enter-passcode'; // fallback امن
          }
        }
      } catch (e2) {
        print('❌ Error checking keys: $e2');
      }
      return '/import-create';
    }
  }

  /// Save wallet information securely
  Future<void> saveWalletInfo({
    required String walletName,
    required String userId,
    required String walletId,
    String? mnemonic,
    List<String>? activeTokens,
  }) async {
    try {
      // Save wallet info to secure storage
      await SecureStorage.instance.saveUserId(walletName, userId);
      await SecureStorage.instance.saveSelectedWallet(walletName, userId);
      
      if (mnemonic != null) {
        await SecureStorage.instance.saveMnemonic(walletName, userId, mnemonic);
      }

      // ✅ Save activeTokens if provided
      if (activeTokens != null) {
        await SecureStorage.instance.saveActiveTokens(walletName, userId, activeTokens);
      }

      // Add to wallets list
      final existingWallets = await SecureStorage.instance.getWalletsList();
      final newWallet = {
        'walletName': walletName,
        'userID': userId,
        'walletId': walletId,
      };
      
      // Check if wallet already exists
      final walletExists = existingWallets.any((wallet) => 
        wallet['walletName'] == walletName && wallet['userID'] == userId);
      
      if (!walletExists) {
        existingWallets.add(newWallet);
        await SecureStorage.instance.saveWalletsList(existingWallets);
      }

      // CRITICAL: Mark that app has been used (prevent false fresh install detection)
      await _markAppAsUsed();
      
      print('✅ Wallet info saved successfully (including ${activeTokens?.length ?? 0} active tokens)');
    } catch (e) {
      print('❌ Error saving wallet info: $e');
      rethrow;
    }
  }

  /// Mark app as used to prevent false fresh install detection
  Future<void> _markAppAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('wallet_imported', true);
      await prefs.setString('last_wallet_action', DateTime.now().millisecondsSinceEpoch.toString());
      
      print('✅ App marked as used - fresh install detection will be more accurate');
    } catch (e) {
      print('❌ Error marking app as used: $e');
    }
  }

  /// Get complete wallet information including activeTokens
  Future<Map<String, dynamic>?> getCompleteWalletInfo(String walletName, String userId) async {
    try {
      final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
      final activeTokens = await SecureStorage.instance.getActiveTokens(walletName, userId);
      final balanceCache = await SecureStorage.instance.getWalletBalanceCache(walletName, userId);
      
      if (mnemonic != null && mnemonic.isNotEmpty) {
        return {
          'walletName': walletName,
          'userId': userId,
          'walletId': walletName, // Using wallet name as ID for now
          'mnemonic': mnemonic,
          'activeTokens': activeTokens,
          'balanceCache': balanceCache,
        };
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting complete wallet info: $e');
      return null;
    }
  }

  /// Save activeTokens for current wallet
  Future<void> saveActiveTokensForWallet(String walletName, String userId, List<String> activeTokens) async {
    try {
      await SecureStorage.instance.saveActiveTokens(walletName, userId, activeTokens);
      print('✅ Active tokens saved for wallet: $walletName');
    } catch (e) {
      print('❌ Error saving active tokens: $e');
      rethrow;
    }
  }

  /// Save balance cache for specific wallet
  Future<void> saveBalanceCacheForWallet(String walletName, String userId, Map<String, double> balances) async {
    try {
      await SecureStorage.instance.saveWalletBalanceCache(walletName, userId, balances);
      print('✅ Balance cache saved for wallet: $walletName');
    } catch (e) {
      print('❌ Error saving balance cache: $e');
      rethrow;
    }
  }

  /// Clear all wallet data (for logout/reset)
  Future<void> clearWalletData() async {
    try {
      await SecureStorage.instance.clearAllSecureData();
      print('✅ Wallet data cleared successfully');
    } catch (e) {
      print('❌ Error clearing wallet data: $e');
      rethrow;
    }
  }

  /// Force clear all data for fresh install
  Future<void> forceClearAllData() async {
    try {
      await SecureStorage.instance.clearAllSecureData();
      print('✅ All data cleared for fresh install');
    } catch (e) {
      print('❌ Error clearing all data: $e');
      rethrow;
    }
  }

  /// Clear all data (alias for forceClearAllData)
  Future<void> clearAllData() async {
    await forceClearAllData();
  }

  /// Check if this is a fresh install (no existing data) with timeout protection
  Future<bool> isFreshInstall() async {
    try {
      print('🔍 Starting fresh install check with timeout protection...');
      
      // CRITICAL FIX: Add timeout protection to prevent hanging
      return await _performFreshInstallCheck()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        print('⚠️ Fresh install check timeout - assuming NOT fresh install (safe default)');
        return false; // Safe default - assume NOT fresh install to prevent data loss
      });
      
    } catch (e) {
      print('❌ Error checking fresh install: $e');
      return false; // Assume NOT fresh install on error to be safe
    }
  }

  /// Perform the actual fresh install check with individual timeouts
  Future<bool> _performFreshInstallCheck() async {
    // CRITICAL FIX: More conservative approach to prevent data loss
    // Check multiple sources to ensure we don't incorrectly detect fresh install
    
    // 1. Check SharedPreferences first (most reliable for app state)
    final hasDataInPrefs = await _checkSharedPreferencesForData()
        .timeout(const Duration(seconds: 2), onTimeout: () {
      print('⚠️ SharedPreferences check timeout - assuming has data');
      return true; // Safe assumption - if timeout, assume has data
    });
    if (hasDataInPrefs) {
      print('📱 Found data in SharedPreferences - NOT fresh install');
      return false;
    }
    
    // 2. Check keychain/secure storage
    final hasSecureData = await _checkSecureStorageForData()
        .timeout(const Duration(seconds: 3), onTimeout: () {
      print('⚠️ SecureStorage check timeout - assuming has data');
      return true; // Safe assumption - if timeout, assume has data
    });
    if (hasSecureData) {
      print('🔐 Found data in SecureStorage - NOT fresh install');
      return false;
    }
    
    // 3. Check passcode specifically (critical indicator)
    final hasPasscodeSet = await PasscodeManager.isPasscodeSet()
        .timeout(const Duration(seconds: 2), onTimeout: () {
      print('⚠️ Passcode check timeout - assuming passcode exists');
      return true; // Safe assumption - if timeout, assume passcode exists
    });
    if (hasPasscodeSet) {
      print('🔑 Found passcode - NOT fresh install');
      return false;
    }
    
    // Check if we have any secure storage keys at all
    final keys = await SecureStorage.instance.getAllKeys()
        .timeout(const Duration(seconds: 2), onTimeout: () {
      print('⚠️ getAllKeys timeout - assuming no keys (fresh install)');
      return <String>[];
    });
    
    if (keys.isEmpty) {
      // iOS: If keychain is empty, double-check SharedPreferences
      if (Platform.isIOS) {
        final hasDataInPrefs = await _checkSharedPreferencesForData()
            .timeout(const Duration(seconds: 2), onTimeout: () {
          print('⚠️ iOS SharedPreferences fallback timeout - assuming no data');
          return false;
        });
        if (hasDataInPrefs) {
          print('🍎 Keychain empty but SharedPreferences has data - NOT fresh install');
          return false;
        }
      }
      
      print('🆕 No secure storage keys found - fresh install');
      return true;
    }
    
    // Check if we have wallet data specifically
    final wallets = await SecureStorage.instance.getWalletsList()
        .timeout(const Duration(seconds: 2), onTimeout: () {
      print('⚠️ getWalletsList timeout - assuming no wallets');
      return <Map<String, String>>[];
    });
    
    if (wallets.isNotEmpty) {
      // Check if any wallet has valid data (with timeout for each check)
      for (final wallet in wallets.take(3)) { // Limit to first 3 wallets to prevent long delays
        final walletName = wallet['walletName'];
        final userId = wallet['userID'];
        
        if (walletName?.isNotEmpty == true && userId?.isNotEmpty == true) {
          try {
            final mnemonic = await SecureStorage.instance.getMnemonic(walletName!, userId!)
                .timeout(const Duration(seconds: 1), onTimeout: () {
              print('⚠️ Mnemonic check timeout for wallet $walletName');
              return null;
            });
            if (mnemonic != null && mnemonic.isNotEmpty) {
              print('💰 Found valid wallet: $walletName - NOT fresh install');
              return false; // Found valid wallet data - not fresh install
            }
          } catch (e) {
            print('❌ Error checking mnemonic for wallet $walletName: $e');
            continue;
          }
        }
      }
    }
    
    // Check for other important keys that indicate existing user (with timeout)
    try {
      final selectedWallet = await SecureStorage.instance.getSecureData('selected_wallet')
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      if (selectedWallet != null && selectedWallet.isNotEmpty) {
        print('🔑 Found selected_wallet - NOT fresh install');
        return false;
      }
    } catch (e) {
      print('⚠️ Error checking selected_wallet: $e');
    }
    
    try {
      final userID = await SecureStorage.instance.getSecureData('UserID')
          .timeout(const Duration(seconds: 1), onTimeout: () => null);
      if (userID != null && userID.isNotEmpty) {
        print('🔑 Found UserID - NOT fresh install');
        return false;
      }
    } catch (e) {
      print('⚠️ Error checking UserID: $e');
    }
    
    // Has some keys but no important data - could be corrupted or old version
    print('⚠️ Has ${keys.length} keys but no valid wallet or important data');
    print('🔑 Keys found: ${keys.take(5).join(', ')}${keys.length > 5 ? '...' : ''}');
    
    // If we have any data at all, it's NOT a fresh install
    // Even if data is corrupted, the app was previously installed
    if (keys.isNotEmpty) {
      print('📊 Found ${keys.length} keys - NOT fresh install (app was previously installed)');
      return false;
    }
    
    // Only if we have absolutely no keys, treat as fresh install
    print('🆕 No keys found - treating as fresh install');
    return true;
  }

  /// Check SecureStorage for any critical app data with timeout protection
  Future<bool> _checkSecureStorageForData() async {
    try {
      print('🔐 Checking SecureStorage for data...');
      
      // Check for critical keys that indicate app usage (with individual timeouts)
      final criticalKeys = [
        'selected_wallet',
        'UserID',
        'WalletID', 
        'app_last_initialized',
        'passcode_hash_secure',
        'passcode_salt_secure',
      ];
      
      for (final key in criticalKeys.take(4)) { // Limit to first 4 keys to prevent delays
        try {
          final value = await SecureStorage.instance.getSecureData(key)
              .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
          if (value != null && value.isNotEmpty) {
            print('🔐 Found SecureStorage key: $key');
            return true;
          }
        } catch (e) {
          // Continue checking other keys if one fails
          print('🔐 Error checking key $key: $e');
        }
      }
      
      // Check wallet list (with timeout)
      try {
        final wallets = await SecureStorage.instance.getWalletsList()
            .timeout(const Duration(seconds: 1), onTimeout: () => <Map<String, String>>[]);
        if (wallets.isNotEmpty) {
          print('🔐 Found ${wallets.length} wallets in SecureStorage');
          return true;
        }
      } catch (e) {
        print('🔐 Error checking wallet list: $e');
      }
      
      // Check all keys as last resort (with timeout)
      try {
        final allKeys = await SecureStorage.instance.getAllKeys()
            .timeout(const Duration(seconds: 1), onTimeout: () => <String>[]);
        if (allKeys.isNotEmpty) {
          print('🔐 Found ${allKeys.length} keys in SecureStorage');
          return true;
        }
      } catch (e) {
        print('🔐 Error getting all keys: $e');
      }
      
      print('🔐 No data found in SecureStorage');
      return false;
      
    } catch (e) {
      print('🔐 Error checking SecureStorage: $e');
      return false;
    }
  }

  /// Check SharedPreferences for any app data (iOS resilience) with timeout protection
  Future<bool> _checkSharedPreferencesForData() async {
    try {
      print('🍎 Checking SharedPreferences for data...');
      
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2), onTimeout: () {
        throw TimeoutException('SharedPreferences getInstance timeout');
      });
      
      // Check for any key that indicates the app was used before (limit to most critical keys)
      final indicatorKeys = [
        'selected_wallet',
        'UserID', 
        'WalletID',
        'passcode_hash',
        'passcode_salt',
        'wallet_list',
        'app_initialized',
        'app_has_been_used',     // Critical flag
        'wallet_imported',       // Wallet import flag
        'passcode_set',          // Passcode set flag
      ];
      
      // Only check first 8 keys to prevent delays
      for (final key in indicatorKeys.take(8)) {
        try {
          if (prefs.containsKey(key)) {
            final value = prefs.get(key);
            if (value != null) {
              print('🍎 Found SharedPreferences key: $key');
              return true;
            }
          }
        } catch (e) {
          print('🍎 Error checking SharedPreferences key $key: $e');
          continue; // Continue with other keys
        }
      }
      
      // Check if we have any keys at all
      final allKeys = prefs.getKeys();
      if (allKeys.isNotEmpty) {
        print('🍎 Found ${allKeys.length} SharedPreferences keys: ${allKeys.take(5).join(", ")}${allKeys.length > 5 ? "..." : ""}');
        return true;
      }
      
      print('🍎 No data found in SharedPreferences');
      return false;
      
    } catch (e) {
      print('🍎 Error checking SharedPreferences: $e');
      return false;
    }
  }

  /// iOS Fallback: Check for valid wallet in SharedPreferences
  Future<bool> _checkValidWalletFallback() async {
    try {
      print('🍎 iOS: Checking SharedPreferences for wallet fallback...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Check for common wallet indicators in SharedPreferences
      final hasWalletData = prefs.containsKey('selected_wallet') ||
                           prefs.containsKey('UserID') ||
                           prefs.containsKey('WalletID') ||
                           prefs.containsKey('passcode_hash');
      
      if (hasWalletData) {
        print('🍎 iOS: Found wallet indicators in SharedPreferences');
        
        // Try to get specific wallet data
        final selectedWallet = prefs.getString('selected_wallet');
        final userId = prefs.getString('UserID');
        final walletId = prefs.getString('WalletID');
        
        print('🍎 iOS: selectedWallet: ${selectedWallet != null ? "EXISTS" : "NULL"}');
        print('🍎 iOS: userId: ${userId != null ? "EXISTS" : "NULL"}');
        print('🍎 iOS: walletId: ${walletId != null ? "EXISTS" : "NULL"}');
        
        // If we have basic wallet info, consider it valid for routing
        // The actual mnemonic might be in keychain but not accessible
        if (selectedWallet != null || userId != null) {
          print('🍎 iOS: Valid wallet found in SharedPreferences fallback');
          return true;
        }
      }
      
      print('🍎 iOS: No valid wallet found in SharedPreferences fallback');
      return false;
      
    } catch (e) {
      print('🍎 iOS: Error in SharedPreferences fallback: $e');
      return false;
    }
  }

  /// Get current wallet information
  Future<Map<String, String>?> getCurrentWallet() async {
    try {
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      final selectedUserId = await SecureStorage.instance.getSelectedUserId();
      
      if (selectedWallet != null && selectedUserId != null) {
        // Verify that the selected wallet actually exists and has valid data
        final mnemonic = await SecureStorage.instance.getMnemonic(selectedWallet, selectedUserId);
        
        if (mnemonic != null && mnemonic.isNotEmpty) {
          return {
            'name': selectedWallet,
            'userId': selectedUserId,
            'walletId': selectedWallet, // Using wallet name as ID for now
          };
        } else {
          print('⚠️ Selected wallet $selectedWallet has no valid mnemonic');
          return null;
        }
      }
      
      // If no selected wallet or invalid, try to find first valid wallet
      final wallets = await SecureStorage.instance.getWalletsList();
      for (final wallet in wallets) {
        final walletName = wallet['walletName'];
        final userId = wallet['userID'];
        
        if (walletName?.isNotEmpty == true && userId?.isNotEmpty == true) {
          try {
            final mnemonic = await SecureStorage.instance.getMnemonic(walletName!, userId!);
            if (mnemonic != null && mnemonic.isNotEmpty) {
              // Set this as selected wallet
              await SecureStorage.instance.saveSelectedWallet(walletName, userId);
              
              return {
                'name': walletName,
                'userId': userId,
                'walletId': walletName,
              };
            }
          } catch (e) {
            print('❌ Error checking wallet $walletName: $e');
            continue;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting current wallet: $e');
      return null;
    }
  }
} 