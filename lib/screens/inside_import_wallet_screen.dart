import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async'; // اضافه کردن برای Completer
import '../layout/bottom_menu_with_siri.dart';
import '../services/secure_storage.dart';
import '../services/service_provider.dart';
import '../services/update_balance_helper.dart'; // اضافه کردن helper مطابق Kotlin

class InsideImportWalletScreen extends StatefulWidget {
  const InsideImportWalletScreen({Key? key}) : super(key: key);

  @override
  State<InsideImportWalletScreen> createState() => _InsideImportWalletScreenState();
}

class _InsideImportWalletScreenState extends State<InsideImportWalletScreen> {
  final TextEditingController _secretPhraseController = TextEditingController();
  String errorMessage = '';
  bool isLoading = false;
  bool showErrorModal = false;

  // فرض: نام کیف پول جدید به صورت خودکار تولید می‌شود
  String walletName = 'Import 1';

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
    _suggestNextImportedWalletName();
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

  Future<void> _suggestNextImportedWalletName() async {
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) 0?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    setState(() {
      walletName = 'Imported wallet ${maxNum + 1}';
    });
  }

  @override
  void dispose() {
    _secretPhraseController.dispose();
    super.dispose();
  }

  bool validateSecretPhrase(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return [12, 18, 24].contains(words.length);
  }

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

  void _restoreWallet() async {
    final phrase = _secretPhraseController.text.trim();
    if (!validateSecretPhrase(phrase)) {
      setState(() {
        errorMessage = _safeTranslate('secret_phrase_must_contain', 'Secret phrase must contain 12, 18, or 24 words.');
        showErrorModal = true;
      });
      return;
    }

    // Check if mnemonic already exists before making API call
    print('🔍 Checking if mnemonic already exists...');
    final mnemonicExists = await _checkMnemonicExists(phrase);
    
    if (mnemonicExists) {
      print('⚠️ Mnemonic already exists, showing error modal');
      setState(() {
        errorMessage = 'This wallet has already been imported. Please use a different seed phrase.';
        showErrorModal = true;
      });
      return;
    }
    
    print('✅ Mnemonic check passed, proceeding with import...');

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) 0?$');
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

    try {
      // Import wallet via API
      print('🚀 Starting wallet import process...');
      final apiService = ServiceProvider.instance.apiService;
      final response = await apiService.importWallet(phrase);
      
      if (response.status == 'success' && response.data != null) {
        print('✅ Wallet import successful');
        
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
        
        // فراخوانی update-balance API مطابق با Kotlin
        final completer = Completer<bool>();
        print('🔄 Starting balance update for UserID: ${response.data!.userID}');
        
        UpdateBalanceHelper.updateBalanceWithCheck(response.data!.userID ?? '', (success) {
          print('🔄 Balance update result: $success');
          updateBalanceSuccess = success;
          completer.complete(success);
        });
        
        await completer.future;
        
        print('📊 Update Balance operation completed: $updateBalanceSuccess');
        
        setState(() {
          isLoading = false;
        });
        
        // فرض: موفقیت
        if (mounted) Navigator.pop(context, {'walletName': newWalletName});
      } else {
        setState(() {
          isLoading = false;
          errorMessage = _safeTranslate('import_failed', 'Import failed: ${response.message}');
          showErrorModal = true;
        });
      }
    } catch (e) {
      print('❌ Error importing wallet: $e');
      setState(() {
        isLoading = false;
        errorMessage = _safeTranslate('import_failed', 'Import failed: ${e.toString()}');
        showErrorModal = true;
      });
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _secretPhraseController.text = data.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isValid = validateSecretPhrase(_secretPhraseController.text);
    final scaffold = WillPopScope(
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
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(_safeTranslate('multi_coin_wallet', 'Multi-coin wallet'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Secret phrase label
              Text(_safeTranslate('secret_phrase', 'Secret phrase'), style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  TextField(
                    controller: _secretPhraseController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: _safeTranslate('enter_secret_phrase', 'Enter your secret phrase'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF16B369)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextButton(
                    onPressed: _pasteFromClipboard,
                    child: Text(_safeTranslate('paste', 'Paste'), style: const TextStyle(color: Color(0xFF16B369), fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isValid && !isLoading ? _restoreWallet : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isValid ? const Color(0xFF16B369) : Colors.grey[300],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_safeTranslate('restore_wallet', 'Restore wallet'), style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Text(_safeTranslate('what_is_secret_phrase', 'What is a secret phrase?'), style: const TextStyle(fontSize: 14, color: Color(0xFF16B369))),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
              ),
        bottomNavigationBar: const BottomMenuWithSiri(),
      ),
    );

    return showErrorModal
        ? Stack(
            children: [
              scaffold,
              _ErrorModal(
                message: errorMessage,
                onDismiss: () => setState(() => showErrorModal = false),
              ),
            ],
          )
        : scaffold;
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