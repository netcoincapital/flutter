import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async'; // اضافه کردن برای Completer
import 'passcode_screen.dart';
import '../services/wallet_state_manager.dart';
import '../services/service_provider.dart';
import '../providers/app_provider.dart';
import '../services/device_registration_manager.dart';
import '../services/secure_storage.dart';
import '../services/security_settings_manager.dart';
import '../services/update_balance_helper.dart'; // اضافه کردن helper مطابق Kotlin

class ImportWalletScreen extends StatefulWidget {
  final Map<String, dynamic>? qrArguments;
  
  const ImportWalletScreen({
    super.key,
    this.qrArguments,
  });

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final TextEditingController _seedController = TextEditingController();
  bool _isLoading = false;
  bool _showErrorModal = false;
  String _errorMessage = '';
  String walletName = 'Imported wallet 1';
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkExistingWallet();
    _processQRArguments();
    // _suggestNextImportedWalletName(); // Removed as per edit hint
  }

  /// Check if wallet exists and redirect to home if it does
  Future<void> _checkExistingWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        print('🔄 Existing wallet found, redirecting to home...');
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Error checking existing wallet: $e');
    }
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  void _processQRArguments() {
    if (widget.qrArguments != null) {
      final seedPhrase = widget.qrArguments!['seedPhrase'];
      if (seedPhrase != null) {
        print('🌱 QR Seed phrase detected: $seedPhrase');
        setState(() {
          _seedController.text = seedPhrase;
        });
      }
    }
  }

  // Removed _suggestNextImportedWalletName as per edit hint

  /// Normalize mnemonic for comparison
  String _normalizeMnemonic(String mnemonic) {
    return mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check if mnemonic already exists in any wallet
  Future<bool> _checkMnemonicExists(String mnemonic) async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      
      for (final wallet in wallets) {
        final walletName = wallet['walletName'] ?? wallet['name'] ?? '';
        final userId = wallet['userID'] ?? wallet['userId'] ?? '';
        
        if (walletName.isNotEmpty) {
          // Try to get mnemonic for this wallet (check both with and without userId)
          String? existingMnemonic;
          
          if (userId.isNotEmpty) {
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
          } else {
            // For wallets without userId, try with empty string
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, '');
          }
          
          if (existingMnemonic != null && _normalizeMnemonic(existingMnemonic) == _normalizeMnemonic(mnemonic)) {
            print('🔍 Mnemonic already exists in wallet: $walletName (userId: $userId)');
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking mnemonic existence: $e');
      return false;
    }
  }

  void _importWallet() async {
    if (_seedController.text.trim().isEmpty) return;

    final phrase = _seedController.text.trim();
    
    // Check if mnemonic already exists before making API call
    print('🔍 Checking if mnemonic already exists...');
    final mnemonicExists = await _checkMnemonicExists(phrase);
    
    if (mnemonicExists) {
      print('⚠️ Mnemonic already exists, showing error modal');
      setState(() {
        _isLoading = false;
        _showErrorModal = true;
        _errorMessage = 'This wallet has already been imported. Please use a different seed phrase.';
      });
      return;
    }
    
    print('✅ Mnemonic check passed, proceeding with import...');

    setState(() => _isLoading = true);

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) ?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    String newWalletName;
    // Ensure uniqueness in case of duplicate names
    do {
      newWalletName = 'Imported wallet ${++maxNum}';
    } while (wallets.any((w) => (w['walletName'] ?? w['name'] ?? '') == newWalletName));

    print('🚀 Starting wallet import process...');
    print('📝 Seed phrase length: ${_seedController.text.trim().length}');
    
    late final response; // تعریف response خارج از try-catch
    
    try {
      final mnemonic = phrase; // Use phrase variable defined earlier
      
      print('📡 Calling API to import wallet...');
      // Call API to import wallet
      final apiService = ServiceProvider.instance.apiService;
      
      response = await apiService.importWallet(mnemonic);
      
      print('📥 API Response received:');
      print('   Status: ${response.status}');
      print('   Message: ${response.message}');
      print('   Has Data: ${response.data != null}');
      print('   Full Response: $response');
      print('   Response Type: ${response.runtimeType}');
      
      // Log detailed server response
      print('🌐 SERVER RESPONSE DETAILS:');
      print('   📊 Status: ${response.status}');
      print('   💬 Message: ${response.message}');
      print('   📦 Has Data: ${response.data != null}');
      
      if (response.data != null) {
        print('   👤 UserID from server: ${response.data!.userID}');
        print('   🆔 WalletID from server: ${response.data!.walletID}');
        print('   📝 Mnemonic from server: ${response.data!.mnemonic != null ? "RECEIVED" : "NOT RECEIVED"}');
        print('   🏠 Addresses count: ${response.data!.addresses.length}');
        
        // Log addresses received from server
        print('   🏠 ADDRESSES FROM SERVER:');
        for (int i = 0; i < response.data!.addresses.length; i++) {
          final address = response.data!.addresses[i];
          print('     ${i + 1}. ${address.blockchainName}: ${address.publicAddress}');
        }
      }
      
      // Save response to a file for debugging
      try {
        final responseJson = response.toJson();
        print('💾 Response JSON: $responseJson');
      } catch (e) {
        print('❌ Error converting response to JSON: $e');
      }
      
      if (response.data != null) {
        print('📊 Wallet Data Details:');
        print('   UserID: ${response.data!.userID}');
        print('   WalletID: ${response.data!.walletID}');
        print('   Has Mnemonic: ${response.data!.mnemonic != null}');
        print('   Mnemonic Length: ${response.data!.mnemonic?.length ?? 0}');
      }
      
      if (response.status == 'success' && response.data != null) {
        final walletData = response.data!;
        
        print('✅ SUCCESS PATH ENTERED - Saving wallet info...');
        print('   UserID to save: ${walletData.userID}');
        print('   WalletID to save: ${walletData.walletID}');
        print('   Wallet name: $newWalletName');
        
        // Save wallet information securely
        await WalletStateManager.instance.saveWalletInfo(
          walletName: newWalletName,
          userId: walletData.userID ?? '',
          walletId: walletData.walletID ?? '',
          mnemonic: walletData.mnemonic ?? mnemonic, // مطمئن می‌شویم که mnemonic ذخیره شود
        );
        
        // **اطمینان از ذخیره mnemonic**: در صورت عدم ذخیره، مستقیماً ذخیره می‌کنیم
        if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
          final mnemonicToSave = walletData.mnemonic ?? mnemonic;
          await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
          print('✅ Mnemonic saved in SecureStorage with key: Mnemonic_${walletData.userID!}_$newWalletName');
        }
        final debugWallets = await SecureStorage.instance.getWalletsList();
        print('Wallets after add: ' + debugWallets.toString());
        
        print('💾 Wallet info saved successfully');

        // Refresh AppProvider wallets list
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        await appProvider.refreshWallets();
        
        // Get user balance for imported wallet
        print('💰 Getting user balance for imported wallet...');
        try {
          // توضیح: در Kotlin این کار انجام نمی‌شود، فقط wallet import می‌شود
          // موجودی‌ها باید توسط TokenProvider در Home screen بارگذاری شوند
          print('ℹ️ Skipping balance fetch - will be handled by TokenProvider in Home screen');
          
        } catch (e) {
          print('⚠️ Error getting balance (continuing anyway): $e');
          // Continue with import process even if balance retrieval fails
        }
        
        print('🔄 Wallet import successful, now proceeding with additional API calls (matching Kotlin)');
        
        // متغیرهای هماهنگی بین APIها مطابق با Kotlin CountDownLatch
        bool updateBalanceSuccess = false;
        bool deviceRegistrationSuccess = false;
        
        // فراخوانی همزمان APIها مطابق با Kotlin (با Future.wait به جای CountDownLatch)
        final apiResults = await Future.wait([
          // 1. Call update-balance API مطابق با Kotlin
          Future<bool>(() async {
            final completer = Completer<bool>();
            print('🔄 Starting balance update for UserID: ${walletData.userID!}');
            
            UpdateBalanceHelper.updateBalanceWithCheck(walletData.userID!, (success) {
              print('🔄 Balance update result: $success');
              updateBalanceSuccess = success;
              completer.complete(success);
            });
            
            return completer.future;
          }),
          
          // 2. Register device مطابق با Kotlin
          Future<bool>(() async {
            try {
              print('🔄 Starting device registration');
              await DeviceRegistrationManager.instance.registerDevice(
                userId: walletData.userID ?? '',
                walletId: walletData.walletID ?? '',
              );
              print('🔄 Device registration result: true');
              deviceRegistrationSuccess = true;
              return true;
            } catch (e) {
              print('🔄 Device registration result: false - $e');
              deviceRegistrationSuccess = false;
              return false;
            }
          }),
        ]);
        
        final allApisSuccessful = apiResults.every((result) => result == true);
        
        print('📊 All API operations completed:');
        print('   Update Balance: $updateBalanceSuccess');
        print('   Device Registration: $deviceRegistrationSuccess');
        print('   Overall Success: $allApisSuccessful');
        print('💫 ABOUT TO START NAVIGATION PROCESS...');
        
        // Show success message with server data
        if (mounted) {
          // Remove success message - wallet imported silently
        }
        
        // Update app provider with new wallet info
        if (mounted) {
          await appProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId جدید through AppProvider
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            final userIdToUpdate = walletData.userID ?? '';
            print('🔄 Updating TokenProvider with userId: $userIdToUpdate');
            tokenProvider.updateUserId(userIdToUpdate);
          } else {
            print('⚠️ TokenProvider is null in AppProvider');
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating to passcode screen...');
          // بررسی فعال بودن passcode
          final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
          print('🔐 Passcode enabled: $isPasscodeEnabled');
          
          if (isPasscodeEnabled) {
            // اگر passcode فعال است، به passcode screen برو
            print('🔐 Navigating to PasscodeScreen...');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PasscodeScreen(
                  title: 'Choose Passcode',
                  walletName: newWalletName,
                  onSuccess: () {
                    print('🔐 Passcode set successfully, navigating to backup...');
                    Navigator.pushReplacementNamed(
                      context,
                      '/backup',
                      arguments: {
                        'walletName': newWalletName,
                        'userID': walletData.userID ?? '',
                        'walletID': walletData.walletID ?? '',
                        'mnemonic': walletData.mnemonic ?? mnemonic,
                      },
                    );
                  },
                ),
              ),
            );
          } else {
            // اگر passcode غیرفعال است، مستقیم به backup screen برو
            print('🔓 Passcode disabled, navigating directly to backup...');
            Navigator.pushReplacementNamed(
              context,
              '/backup',
              arguments: {
                'walletName': newWalletName,
                'userID': walletData.userID ?? '',
                'walletID': walletData.walletID ?? '',
                'mnemonic': walletData.mnemonic ?? mnemonic,
              },
            );
          }
        }
      } else if (response.status != 'success') {
        print('❌ API returned non-success status');
        print('   Status: ${response.status}');
        print('   Message: ${response.message}');
        // فقط اگر واقعا خطا بود
        throw Exception(response.message ?? 'Import failed');
      } else {
        print('⚠️ Response status is success but no data received');
        print('   Status: ${response.status}');
        print('   Has Data: ${response.data != null}');
      }
    } catch (e) {
      final errorMsg = e.toString();
      print('💥 Exception caught: $errorMsg');
      
      if (errorMsg.contains('successfully imported')) {
        print('🔄 Fallback path - Wallet imported but no data received');
        final mnemonic = phrase; // Use phrase variable defined earlier
        
        // بررسی اینکه آیا response تعریف شده و دارای data است یا نه
        try {
          if (response.data != null) {
            print('✅ Response data exists in fallback, using actual UserID');
            final walletData = response.data!;
            
            // Save wallet information securely with actual data
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: walletData.userID ?? '',
              walletId: walletData.walletID ?? '',
              mnemonic: walletData.mnemonic ?? mnemonic,
            );
            
            print('✅ Fallback: Saved wallet with actual UserID: ${walletData.userID}');
            
            // اطمینان از ذخیره mnemonic با UserID واقعی
            if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
              final mnemonicToSave = walletData.mnemonic ?? mnemonic;
              await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic_${walletData.userID!}_$newWalletName');
            }
          } else {
            print('⚠️ No response data in fallback, using empty UserID');
            
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: '',
              walletId: '',
              mnemonic: mnemonic,
            );
            
            // اطمینان از ذخیره mnemonic در fallback path
            if (mnemonic.isNotEmpty) {
              await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
            }
          }
        } catch (responseError) {
          print('⚠️ Error accessing response in fallback: $responseError');
          print('⚠️ Using empty UserID as fallback');
          
          await WalletStateManager.instance.saveWalletInfo(
            walletName: newWalletName,
            userId: '',
            walletId: '',
            mnemonic: mnemonic,
          );
          
          // اطمینان از ذخیره mnemonic در fallback path
          if (mnemonic.isNotEmpty) {
            await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
            print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
          }
        }
        if (mounted) {
          final fallbackAppProvider = Provider.of<AppProvider>(context, listen: false);
          await fallbackAppProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId صحیح through AppProvider
          final tokenProvider = fallbackAppProvider.tokenProvider;
          if (tokenProvider != null) {
            try {
              if (response.data != null) {
                final userIdToUpdate = response.data!.userID ?? '';
                print('🔄 Updating TokenProvider with userId (fallback): $userIdToUpdate');
                tokenProvider.updateUserId(userIdToUpdate);
              }
            } catch (responseError) {
              print('⚠️ Error accessing response for TokenProvider update: $responseError');
            }
          } else {
            print('⚠️ TokenProvider is null in AppProvider (fallback)');
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showErrorModal = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating to passcode screen (fallback path)...');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PasscodeScreen(
                title: 'Choose Passcode',
                walletName: newWalletName,
                onSuccess: () {
                  print('🔐 Passcode set successfully (fallback path)...');
                  String userIdForBackup = '';
                  String walletIdForBackup = '';
                  String mnemonicForBackup = phrase;
                  
                  try {
                    userIdForBackup = response.data?.userID ?? '';
                    walletIdForBackup = response.data?.walletID ?? '';
                    mnemonicForBackup = response.data?.mnemonic ?? phrase;
                  } catch (responseError) {
                    print('⚠️ Error accessing response for backup navigation: $responseError');
                  }
                  
                  Navigator.pushReplacementNamed(
                    context,
                    '/backup',
                    arguments: {
                      'walletName': newWalletName,
                      'userID': userIdForBackup,
                      'walletID': walletIdForBackup,
                      'mnemonic': mnemonicForBackup,
                    },
                  );
                },
              ),
            ),
          );
        }
      } else {
        print('❌ Error path - Showing error modal');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showErrorModal = true;
            _errorMessage = _safeTranslate('error_importing_wallet', 'Error importing wallet') + ': ${e.toString()}';
          });
        }
      }
    }
  }

  void _launchTerms() async {
    const url = 'https://coinceeper.com/terms-of-service';
    // URL launching functionality removed for now
    print('URL launch functionality removed');
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _seedController.text.trim().isNotEmpty;
    return WillPopScope(
      onWillPop: () async {
        // Check if wallets exist, if so, don't allow back navigation
        try {
          final wallets = await SecureStorage.instance.getWalletsList();
          if (wallets.isNotEmpty) {
            print('🚫 Back navigation blocked - wallet exists');
            return false;
          }
        } catch (e) {
          print('❌ Error checking wallets for back navigation: $e');
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('import_wallet', 'Import Wallet')),
          backgroundColor: const Color(0xFF0BAB9B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // تراز چپ
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, // تراز چپ
                      children: [
                        // Title
                        Text(
                          _safeTranslate('import_wallet', 'Import Wallet'),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.left,
                        ),
                        const SizedBox(height: 24),
                        // Seed phrase input with QR button
                        TextField(
                          controller: _seedController,
                          decoration: InputDecoration(
                            labelText: _safeTranslate('seed_phrase_or_private_key', 'Seed phrase or private key'),
                            labelStyle: const TextStyle(fontSize: 16),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code),
                              onPressed: () async {
                                final result = await Navigator.pushNamed(
                                  context, 
                                  '/qr-scanner',
                                  arguments: {'returnScreen': 'import_wallet'},
                                );
                                if (result != null && result is String && result.isNotEmpty) {
                                  setState(() {
                                    _seedController.text = result;
                                  });
                                }
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                              borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                              borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                              borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          ),
                          style: const TextStyle(fontSize: 16),
                          minLines: 1,
                          maxLines: 1,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isValid ? _safeTranslate('valid_phrase_key_detected', 'Valid phrase/key detected') : _safeTranslate('enter_recovery_phrase', 'Enter your recovery phrase'),
                            style: TextStyle(
                              color: isValid ? const Color(0xFF0BAB9B) : Colors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // حذف متن توافق از اینجا
                      ],
                    ),
                  ),
                ),
              ),
              // متن توافق به پایین صفحه منتقل شود
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      _safeTranslate('by_continuing_agree', 'By continuing, you agree to the '),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    GestureDetector(
                      onTap: _launchTerms,
                      child: Text(
                        _safeTranslate('terms_and_conditions', 'Terms and Conditions'),
                        style: const TextStyle(
                          color: Color(0xFF0BAB9B),
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32, top: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isValid && !_isLoading ? _importWallet : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isValid ? const Color(0xFF4C70D0) : const Color(0xFF858585),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _safeTranslate('import', 'Import'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
              if (_showErrorModal)
                _ErrorModal(
                  message: _errorMessage,
                  onDismiss: () => setState(() => _showErrorModal = false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorModal extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorModal({required this.message, required this.onDismiss});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Color(0xFFFF1961), size: 48),
                const SizedBox(height: 16),
                Text(
                  _safeTranslate(context, 'error', 'Error'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1961),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Text(_safeTranslate(context, 'ok', 'OK'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 