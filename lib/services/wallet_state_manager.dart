import 'secure_storage.dart';
import 'passcode_manager.dart';
import 'security_settings_manager.dart';

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

      print('✅ Wallet info saved successfully (including ${activeTokens?.length ?? 0} active tokens)');
    } catch (e) {
      print('❌ Error saving wallet info: $e');
      rethrow;
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

  /// Check if this is a fresh install (no existing data)
  Future<bool> isFreshInstall() async {
    try {
      // First check if we have any secure storage keys at all
      final keys = await SecureStorage.instance.getAllKeys();
      if (keys.isEmpty) {
        print('🆕 No secure storage keys found - fresh install');
        return true;
      }
      
      // Check if we have wallet data specifically
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        // Check if any wallet has valid data
        for (final wallet in wallets) {
          final walletName = wallet['walletName'];
          final userId = wallet['userID'];
          
          if (walletName?.isNotEmpty == true && userId?.isNotEmpty == true) {
            try {
              final mnemonic = await SecureStorage.instance.getMnemonic(walletName!, userId!);
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
      
      // Check for other important keys that indicate existing user
      final selectedWallet = await SecureStorage.instance.getSecureData('selected_wallet');
      final userID = await SecureStorage.instance.getSecureData('UserID');
      
      if (selectedWallet != null && selectedWallet.isNotEmpty) {
        print('🔑 Found selected_wallet - NOT fresh install');
        return false;
      }
      
      if (userID != null && userID.isNotEmpty) {
        print('🔑 Found UserID - NOT fresh install');
        return false;
      }
      
      // Check if passcode is set using PasscodeManager
      final hasPasscodeSet = await PasscodeManager.isPasscodeSet();
      if (hasPasscodeSet) {
        print('🔑 Found passcode - NOT fresh install');
        return false;
      }
      
      // Has some keys but no important data - could be corrupted or old version
      print('⚠️ Has ${keys.length} keys but no valid wallet or important data');
      print('🔑 Keys found: ${keys.take(5).join(', ')}${keys.length > 5 ? '...' : ''}');
      
      // If we have any data but no valid wallet or important data, treat as fresh install
      // This ensures that corrupted or incomplete data doesn't prevent fresh install
      print('🆕 Treating as fresh install due to no valid wallet or important data');
      return true;
      
    } catch (e) {
      print('❌ Error checking fresh install: $e');
      return false; // Assume NOT fresh install on error to be safe
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