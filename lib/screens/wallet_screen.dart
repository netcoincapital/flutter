import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/main_layout.dart';
import '../services/secure_storage.dart';
import '../providers/app_provider.dart';
import 'package:provider/provider.dart';
import 'phrasekey_confirmation_screen.dart';

class WalletScreen extends StatefulWidget {
  final String walletName;
  
  const WalletScreen({Key? key, required this.walletName}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late String walletName;
  late String initialWalletName;
  bool showDeleteDialog = false;
  List<Map<String, String>> wallets = [];
  late TextEditingController _walletNameController;

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
    walletName = widget.walletName;
    initialWalletName = widget.walletName;
    _walletNameController = TextEditingController(text: walletName);
    
    // اضافه کردن listener برای به‌روزرسانی فوری UI
    _walletNameController.addListener(() {
      setState(() {
        walletName = _walletNameController.text;
      });
    });
    
    _loadWallets();
  }
  
  @override
  void dispose() {
    _walletNameController.dispose();
    super.dispose();
  }

  /// بارگذاری لیست کیف پول‌ها
  Future<void> _loadWallets() async {
    try {
      wallets = await SecureStorage.instance.getWalletsList();
      setState(() {});
    } catch (e) {
      print('❌ Error loading wallet data: $e');
      // Remove error message - silent failure
    }
  }

  /// ذخیره نام کیف پول (مطابق با Kotlin)
  Future<void> _saveWalletName() async {
    try {
      final trimmedWalletName = _walletNameController.text.trim();
      final trimmedInitialWalletName = initialWalletName.trim();
      
      if (trimmedWalletName.isEmpty) {
        // Remove error message - silent failure
        return;
      }
      
      if (trimmedWalletName != trimmedInitialWalletName) {
        final userId = await SecureStorage.instance.getUserIdForWallet(trimmedInitialWalletName);
        
        if (userId != null) {
          // چک کنیم که نام جدید تکراری نباشد
          final existingWallets = await SecureStorage.instance.getWalletsList();
          final isDuplicate = existingWallets.any((wallet) => 
            wallet['walletName'] == trimmedWalletName && wallet['userID'] != userId
          );
          
          if (isDuplicate) {
            // Remove error message - silent failure
            return;
          }
          
          // به‌روزرسانی mnemonic با نام جدید کیف پول
          await _updateMnemonicForWalletName(userId, trimmedInitialWalletName, trimmedWalletName);
          
          // ذخیره نام جدید کیف پول
          await _saveWalletNameToKeystore(userId, trimmedInitialWalletName, trimmedWalletName);
          
          // به‌روزرسانی state محلی
          setState(() {
            walletName = trimmedWalletName;
            initialWalletName = trimmedWalletName;
          });
          
          print('💰 Wallet name updated: $trimmedInitialWalletName -> $trimmedWalletName');
          
          // نمایش پیام موفقیت
          // Remove error message - silent failure
        } else {
          // Remove error message - silent failure
          return;
        }
      }
      
      // بازگشت به صفحه wallets
      Navigator.pushReplacementNamed(context, '/wallets');
    } catch (e) {
      print('Error saving wallet name: $e');
      // Remove error message - silent failure
    }
  }

  /// ذخیره نام کیف پول در Keystore (مطابق با Kotlin)
  Future<void> _saveWalletNameToKeystore(
    String userId,
    String oldWalletName,
    String newWalletName,
  ) async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      
      // به‌روزرسانی نام کیف پول در لیست
      final updatedWallets = wallets.map((wallet) {
        if (wallet['userID'] == userId && wallet['walletName'] == oldWalletName) {
          return {
            'walletName': newWalletName,
            'userID': userId,
          };
        }
        return wallet;
      }).toList();
      
      // ذخیره تغییرات
      await SecureStorage.instance.saveWalletsList(updatedWallets);
      
      // به‌روزرسانی نام کیف پول انتخاب‌شده اگر همان کیف پول باشد
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      if (selectedWallet == oldWalletName) {
        await SecureStorage.instance.saveSelectedWallet(newWalletName, userId);
        
        // به‌روزرسانی AppProvider با نام جدید
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        await appProvider.selectWallet(newWalletName);
      }
      
      // به‌روزرسانی AppProvider
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      await appProvider.refreshWallets();
      
      print('✅ Wallet name saved successfully: $oldWalletName -> $newWalletName');
    } catch (e) {
      print('Error saving wallet name to keystore: $e');
      rethrow;
    }
  }

  /// به‌روزرسانی mnemonic و UserID با نام جدید کیف پول (مطابق با Kotlin)
  Future<void> _updateMnemonicForWalletName(
    String userId,
    String oldWalletName,
    String newWalletName,
  ) async {
    try {
      // 1. به‌روزرسانی mnemonic
      final oldMnemonicKey = 'Mnemonic_${userId}_$oldWalletName';
      final newMnemonicKey = 'Mnemonic_${userId}_$newWalletName';
      
      // خواندن mnemonic با کلید قدیمی
      final mnemonic = await SecureStorage.instance.getSecureData(oldMnemonicKey);
      
      if (mnemonic != null) {
        // ذخیره mnemonic با کلید جدید
        await SecureStorage.instance.saveSecureData(newMnemonicKey, mnemonic);
        
        // حذف کلید قدیمی
        await SecureStorage.instance.deleteSecureData(oldMnemonicKey);
        
        print('✅ Mnemonic updated for wallet: $oldWalletName -> $newWalletName');
      } else {
        print('⚠️ No mnemonic found for old wallet name: $oldWalletName');
      }

      // 2. به‌روزرسانی UserID کلید
      final oldUserIdKey = 'UserID_$oldWalletName';
      final newUserIdKey = 'UserID_$newWalletName';
      
      // خواندن userId با کلید قدیمی
      final userIdData = await SecureStorage.instance.getSecureData(oldUserIdKey);
      
      if (userIdData != null) {
        // ذخیره userId با کلید جدید
        await SecureStorage.instance.saveSecureData(newUserIdKey, userIdData);
        
        // حذف کلید قدیمی
        await SecureStorage.instance.deleteSecureData(oldUserIdKey);
        
        print('✅ UserID key updated for wallet: $oldWalletName -> $newWalletName');
      } else {
        // اگر کلید قدیمی موجود نبود، کلید جدید را ایجاد کن
        await SecureStorage.instance.saveSecureData(newUserIdKey, userId);
        print('✅ UserID key created for new wallet name: $newWalletName');
      }

      // 3. به‌روزرسانی سایر کلیدهای مرتبط با کیف پول
      await _updateOtherWalletKeys(oldWalletName, newWalletName);
      
    } catch (e) {
      print('Error updating mnemonic and keys: $e');
      rethrow;
    }
  }

  /// به‌روزرسانی سایر کلیدهای مرتبط با کیف پول
  Future<void> _updateOtherWalletKeys(String oldWalletName, String newWalletName) async {
    try {
      // به‌روزرسانی PrivateKey اگر موجود باشد
      final oldPrivateKeyKey = 'PrivateKey_$oldWalletName';
      final newPrivateKeyKey = 'PrivateKey_$newWalletName';
      
      final privateKey = await SecureStorage.instance.getSecureData(oldPrivateKeyKey);
      if (privateKey != null) {
        await SecureStorage.instance.saveSecureData(newPrivateKeyKey, privateKey);
        await SecureStorage.instance.deleteSecureData(oldPrivateKeyKey);
        print('✅ PrivateKey updated for wallet: $oldWalletName -> $newWalletName');
      }

      // به‌روزرسانی WalletSettings اگر موجود باشد
      final oldSettingsKey = 'WalletSettings_$oldWalletName';
      final newSettingsKey = 'WalletSettings_$newWalletName';
      
      final settings = await SecureStorage.instance.getSecureJson(oldSettingsKey);
      if (settings != null) {
        await SecureStorage.instance.saveSecureJson(newSettingsKey, settings);
        await SecureStorage.instance.deleteSecureData(oldSettingsKey);
        print('✅ WalletSettings updated for wallet: $oldWalletName -> $newWalletName');
      }
      
    } catch (e) {
      print('Error updating other wallet keys: $e');
      // این خطا critical نیست، فقط لاگ می‌کنیم
    }
  }

  /// حذف کیف پول (مطابق با Kotlin)
  Future<void> _deleteWallet() async {
    try {
      setState(() {
        showDeleteDialog = false;
      });
      
      await _deleteWalletFromKeystore(walletName);
      
      print('🗑️ Wallet deleted: $walletName');
      Navigator.pushReplacementNamed(context, '/wallets');
    } catch (e) {
      print('Error deleting wallet: $e');
      // Remove error message - silent failure
    }
  }

  /// حذف کیف پول از Keystore (مطابق با Kotlin)
  Future<void> _deleteWalletFromKeystore(String walletName) async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      
      // حذف کیف پول از لیست
      final updatedWallets = wallets.where((wallet) => wallet['walletName'] != walletName).toList();
      
      // ذخیره لیست به‌روز شده
      await SecureStorage.instance.saveWalletsList(updatedWallets);
      
      // حذف کیف پول انتخاب‌شده اگر همان کیف پول باشد
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      if (selectedWallet == walletName) {
        await SecureStorage.instance.deleteSecureData('selected_wallet');
        await SecureStorage.instance.deleteSecureData('selected_user_id');
      }
      
      // حذف تمام کلیدهای مرتبط با کیف پول
      await _deleteAllWalletKeys(walletName);
      
      // انتخاب کیف پول جدید اگر کیف پول حذف شده انتخاب شده بود
      if (updatedWallets.isNotEmpty) {
        final newWallet = updatedWallets.first;
        final newWalletName = newWallet['walletName'] ?? '';
        final newUserId = newWallet['userID'] ?? '';
        
        if (newWalletName.isNotEmpty && newUserId.isNotEmpty) {
          await SecureStorage.instance.saveSelectedWallet(newWalletName, newUserId);
          
          // به‌روزرسانی AppProvider
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          await appProvider.selectWallet(newWalletName);
          
          print('✅ New wallet selected: $newWalletName');
        }
      } else {
        // هیچ کیف پولی باقی نمانده است
        print('⚠️ No wallets remaining');
        Navigator.pushReplacementNamed(context, '/import-create');
        return;
      }
      
      // به‌روزرسانی AppProvider
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      await appProvider.refreshWallets();
      
    } catch (e) {
      print('Error deleting wallet from keystore: $e');
      rethrow;
    }
  }

  /// حذف تمام کلیدهای مرتبط با کیف پول
  Future<void> _deleteAllWalletKeys(String walletName) async {
    try {
      // دریافت userId برای کیف پول
      final userId = await SecureStorage.instance.getUserIdForWallet(walletName);
      
      if (userId != null) {
        // حذف mnemonic کیف پول
        final mnemonicKey = 'Mnemonic_${userId}_$walletName';
        await SecureStorage.instance.deleteSecureData(mnemonicKey);
        print('✅ Deleted mnemonic key: $mnemonicKey');
      }
      
      // حذف UserID کلید
      final userIdKey = 'UserID_$walletName';
      await SecureStorage.instance.deleteSecureData(userIdKey);
      print('✅ Deleted UserID key: $userIdKey');
      
      // حذف PrivateKey اگر موجود باشد
      final privateKeyKey = 'PrivateKey_$walletName';
      if (await SecureStorage.instance.containsKey(privateKeyKey)) {
        await SecureStorage.instance.deleteSecureData(privateKeyKey);
        print('✅ Deleted PrivateKey key: $privateKeyKey');
      }
      
      // حذف WalletSettings اگر موجود باشد
      final settingsKey = 'WalletSettings_$walletName';
      if (await SecureStorage.instance.containsKey(settingsKey)) {
        await SecureStorage.instance.deleteSecureData(settingsKey);
        print('✅ Deleted WalletSettings key: $settingsKey');
      }
      
      print('✅ All keys deleted for wallet: $walletName');
    } catch (e) {
      print('Error deleting wallet keys: $e');
      // این خطا critical نیست، ادامه می‌دهیم
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Save and Delete buttons
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.black),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            walletName.isEmpty ? _safeTranslate('wallet_title', 'Wallet') : walletName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              showDeleteDialog = true;
                            });
                          },
                          icon: Image.asset(
                            'assets/images/recycle_bin.png',
                            width: 18,
                            height: 18,
                            color: Colors.black,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final trimmedWalletName = _walletNameController.text.trim();
                            final trimmedInitialWalletName = initialWalletName.trim();
                            
                            if (trimmedWalletName != trimmedInitialWalletName) {
                              await _saveWalletName();
                            } else {
                              // اگر تغییری نبود، فقط برگشت
                              Navigator.pushReplacementNamed(context, '/wallets');
                            }
                          },
                          child: Text(
                            _safeTranslate('save', 'Save'),
                            style: TextStyle(
                              fontSize: 14,
                              color: _walletNameController.text.trim() != initialWalletName.trim() 
                                  ? const Color(0xFF2AC079) 
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Name Input
                    Text(
                      _safeTranslate('name', 'Name'),
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _walletNameController,
                      decoration: InputDecoration(
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
                    ),
                    const SizedBox(height: 28),
                    // Secret phrase backups section
                    Text(
                      _safeTranslate('secret_phrase_backups', 'Secret phrase backups'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Manual backup option
                    GestureDetector(
                      onTap: () async {
                        // Navigate to phrasekey_confirmation first (مطابق با درخواست کاربر)
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PhraseKeyConfirmationScreen(
                              walletName: walletName,
                              isFromWalletCreation: false, // این از مسیر manual backup است
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/images/hold.png',
                                  width: 28,
                                  height: 28,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  _safeTranslate('manual', 'Manual'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _safeTranslate('active', 'Active'),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Warning box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _safeTranslate('backup_recommendation', 'We highly recommend completing both backup options to help prevent the loss of your crypto.'),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFE68A00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Delete confirmation dialog
              if (showDeleteDialog)
                _DeleteDialog(
                  onDelete: _deleteWallet,
                  onCancel: () {
                    setState(() {
                      showDeleteDialog = false;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// دریافت نام کیف پول از Keystore (مطابق با Kotlin)
Future<String> _getWalletNameFromKeystore(String walletName) async {
  try {
    final selectedWallet = await SecureStorage.instance.getSelectedWallet();
    return selectedWallet ?? walletName;
  } catch (e) {
    print('Error getting wallet name from keystore: $e');
    return walletName;
  }
}

class _DeleteDialog extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _DeleteDialog({
    required this.onDelete,
    required this.onCancel,
  });

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
      onTap: onCancel,
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _safeTranslate(context, 'delete_wallet', 'Delete Wallet'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _safeTranslate(context, 'delete_wallet_confirmation', 'Are you sure you want to delete this wallet? This action cannot be undone.'),
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onCancel,
                        child: Text(
                          _safeTranslate(context, 'cancel', 'Cancel'),
                          style: const TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextButton(
                        onPressed: onDelete,
                        child: Text(
                          _safeTranslate(context, 'delete', 'Delete'),
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 