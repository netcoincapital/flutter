import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async'; // Add missing import for Completer
import 'passcode_screen.dart';
import '../services/api_service.dart';
import '../services/service_provider.dart';
import '../services/wallet_state_manager.dart';
import '../services/secure_storage.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/device_registration_manager.dart';
import '../services/update_balance_helper.dart'; // اضافه کردن helper مطابق Kotlin

class CreateNewWalletScreen extends StatefulWidget {
  const CreateNewWalletScreen({Key? key}) : super(key: key);

  @override
  State<CreateNewWalletScreen> createState() => _CreateNewWalletScreenState();
}

class _CreateNewWalletScreenState extends State<CreateNewWalletScreen> {
  String? errorMessage;
  String walletName = 'Wallet 1';
  bool showErrorModal = false;
  bool isLoading = false;
  late ApiService _apiService;

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
    _apiService = ServiceProvider.instance.apiService;
    _suggestNextWalletName();
  }

  Future<void> _suggestNextWalletName() async {
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+)');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    setState(() {
      walletName = 'New wallet ${maxNum + 1}';
    });
  }

  Future<void> _generateWallet() async {
    if (isLoading) return;
    
    setState(() {
      isLoading = true;
      errorMessage = null;
      showErrorModal = false;
    });

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+)');
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
      newWalletName = 'New wallet ${++maxNum}';
    } while (wallets.any((w) => (w['walletName'] ?? w['name'] ?? '') == newWalletName));

    // Prevent empty wallet name
    if (newWalletName.trim().isEmpty) {
      setState(() {
        errorMessage = _safeTranslate('wallet_name_cannot_be_empty', 'Wallet name cannot be empty');
        showErrorModal = true;
        isLoading = false;
      });
      return;
    }

    try {
      // Check network connection
      final isConnected = ServiceProvider.instance.networkManager.isConnected;
      if (!isConnected) {
        setState(() {
          errorMessage = _safeTranslate('no_internet_connection', 'No internet connection available. Please check your connection.');
          showErrorModal = true;
          isLoading = false;
        });
        return;
      }

      // Call API to generate wallet
      print('🔄 Calling generateWallet API with walletName: $newWalletName');
      final response = await _apiService.generateWallet(newWalletName);
      print('📥 API Response: ${response.toJson()}');
      
      if (response.success && response.userID != null) {
        print('✅ Wallet created successfully!');
        
        // Save wallet information securely
        final existingWallets = await SecureStorage.instance.getWalletsList();
        
        // Add new wallet to the list
        existingWallets.add({
          'walletName': newWalletName,
          'userID': response.userID!,
          'mnemonic': response.mnemonic ?? '',
        });
        
        // Save updated wallets list
        await SecureStorage.instance.saveWalletsList(existingWallets);
        await SecureStorage.instance.saveSelectedWallet(newWalletName, response.userID!);
        await SecureStorage.instance.saveUserId(newWalletName, response.userID!);
        
        // Save mnemonic in SecureStorage
        if (response.mnemonic != null) {
          await SecureStorage.instance.saveMnemonic(newWalletName, response.userID!, response.mnemonic!);
          print('✅ Mnemonic saved in SecureStorage with key: Mnemonic_${response.userID!}_$newWalletName');
        }
        
        // Save in SharedPreferences for legacy compatibility
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('UserID', response.userID!);
        if (response.mnemonic != null) {
          await prefs.setString('mnemonic', response.mnemonic!);
        }
        await prefs.setString('walletName', newWalletName);

        // ✅ Fixed: Use AppProvider instead of directly accessing TokenProvider
        if (mounted) {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          final tokenProvider = appProvider.tokenProvider;
          
          // Update TokenProvider if it exists
          if (tokenProvider != null) {
            tokenProvider.updateUserId(response.userID!);
          }
          
          // Refresh AppProvider wallets list
          await appProvider.refreshWallets();
        }

        print('🔄 Wallet generation successful, now proceeding with additional API calls (matching Kotlin)');
        
        // متغیرهای هماهنگی بین APIها مطابق با Kotlin CountDownLatch
        bool updateBalanceSuccess = false;
        bool deviceRegistrationSuccess = false;
        
        // فراخوانی همزمان APIها مطابق با Kotlin (با Future.wait به جای CountDownLatch)
        final apiResults = await Future.wait([
          // 1. Call update-balance API مطابق با Kotlin
          Future<bool>(() async {
            final completer = Completer<bool>();
            print('🔄 Starting balance update for UserID: ${response.userID!}');
            
            UpdateBalanceHelper.updateBalanceWithCheck(response.userID!, (success) {
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
                userId: response.userID!,
                walletId: '',
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

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _safeTranslate('wallet_created_success_message', 'Wallet created successfully! UserID: ${response.userID!}, Mnemonic: ${response.mnemonic != null ? "RECEIVED" : "NOT RECEIVED"}'),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        // Navigate to passcode screen مطابق با Kotlin
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PasscodeScreen(
                title: _safeTranslate('choose_passcode', 'Choose Passcode'),
                walletName: newWalletName,
                onSuccess: () {
                  Navigator.pushReplacementNamed(
                    context,
                    '/backup',
                    arguments: {
                      'walletName': newWalletName,
                      'userID': response.userID!,
                      'mnemonic': response.mnemonic ?? '',
                    },
                  );
                },
              ),
            ),
          );
        }
      } else {
        // Show error if unsuccessful
        setState(() {
          errorMessage = response.message ?? _safeTranslate('error_creating_wallet', 'Error creating wallet. Please try again.');
          showErrorModal = true;
          isLoading = false;
        });
      }
    } catch (e) {
      // Handle API errors
      setState(() {
        if (e.toString().contains('server security restrictions') || 
            e.toString().contains('Cloudflare')) {
          errorMessage = _safeTranslate('server_security_restriction', 'Device registration failed due to server security restrictions. This may be caused by Cloudflare protection blocking mobile app requests. Please contact support or try again later.');
        } else if (e.toString().contains('timeout') || 
                   e.toString().contains('connection')) {
          errorMessage = _safeTranslate('connection_error', 'Error connecting to server. Please check your internet connection.');
        } else {
          errorMessage = _safeTranslate('error_creating_wallet', 'Error creating wallet. Please try again.') + ': ${e.toString()}';
        }
        showErrorModal = true;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0BAB9B),
        elevation: 0,
        title: Text(
          _safeTranslate('generate_new_wallet', 'Generate New Wallet'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(  // ✅ Fixed: Add ScrollView to prevent overflow
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletOptionItemNew(
                title: _safeTranslate('secret_phrase', 'Secret phrase'),
                points: 100,
                buttonText: _safeTranslate('generate', 'Generate'),
                isLoading: isLoading,
                onClickCreate: _generateWallet,
                expandedContent: (context) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailRow(
                      label: _safeTranslate('security', 'Security'),
                      content: _safeTranslate('create_recover_description', 'Create and recover wallet with a 12, 18, or 24-word secret phrase. You must manually store this, or back up with Google Drive storage.'),
                    ),
                    const SizedBox(height: 12),
                    DetailRow(
                      label: _safeTranslate('transactions', 'Transactions'),
                      content: _safeTranslate('transaction_networks_description', 'Transactions are available on more networks (chains), but require more steps to complete.'),
                      showIcons: true,
                    ),
                    const SizedBox(height: 12),
                    DetailRow(
                      label: _safeTranslate('fee', 'Fee'),
                      content: _safeTranslate('fees_description', 'Pay network fee (gas) with native tokens only. For example, if your transaction is on the Ethereum network, you can only pay for this fee with ETH.'),
                    ),
                  ],
                ),
              ),
              
              if (showErrorModal)
                CreateWalletErrorModal(
                  show: showErrorModal,
                  onDismiss: () => setState(() => showErrorModal = false),
                  message: errorMessage ?? _safeTranslate('error', 'Error'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletOptionItemNew extends StatefulWidget {
  final String title;
  final int? points;
  final String buttonText;
  final bool isLoading;
  final Future<void> Function() onClickCreate;
  final WidgetBuilder? expandedContent;

  const WalletOptionItemNew({
    Key? key,
    required this.title,
    this.points,
    required this.buttonText,
    required this.isLoading,
    required this.onClickCreate,
    this.expandedContent,
  }) : super(key: key);

  @override
  State<WalletOptionItemNew> createState() => _WalletOptionItemNewState();
}

class _WalletOptionItemNewState extends State<WalletOptionItemNew> {
  bool isExpanded = false;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  void _onClick() async {
    if (widget.isLoading) return;
    await widget.onClickCreate();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          if (widget.points != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${widget.points} ${_safeTranslate('points', 'points')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isExpanded = !isExpanded;
                          });
                        },
                        child: Row(
                          children: [
                            Text(
                              isExpanded ? _safeTranslate('hide_details', 'Hide details') : _safeTranslate('show_details', 'Show details'),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.blue,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 100,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: widget.isLoading ? null : _onClick,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0BAB9B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: widget.isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            widget.buttonText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (isExpanded && widget.expandedContent != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: widget.expandedContent!(context),
            ),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String content;
  final bool showIcons;

  const DetailRow({
    Key? key,
    required this.label,
    required this.content,
    this.showIcons = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            height: 1.4,
          ),
        ),
        if (showIcons) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _buildNetworkIcon('assets/images/ethereum_logo.png'),
              const SizedBox(width: 8),
              _buildNetworkIcon('assets/images/binance_logo.png'),
              const SizedBox(width: 8),
              _buildNetworkIcon('assets/images/btc.png'),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '+',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkIcon(String assetPath) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 24,
              height: 24,
              color: Colors.grey,
            );
          },
        ),
      ),
    );
  }
}

class CreateWalletErrorModal extends StatelessWidget {
  final bool show;
  final VoidCallback onDismiss;
  final String message;
  final String title;
  
  const CreateWalletErrorModal({
    Key? key,
    required this.show,
    required this.onDismiss,
    required this.message,
    this.title = 'Error',
  }) : super(key: key);

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
    if (!show) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _safeTranslate(context, 'error', title),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.red,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
} 