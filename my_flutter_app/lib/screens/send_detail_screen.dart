import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import '../models/crypto_token.dart';
import '../models/transaction.dart';
import '../layout/main_layout.dart';
import '../services/transaction_notification_receiver.dart';
import '../providers/history_provider.dart';

class SendDetailScreen extends StatefulWidget {
  final String tokenJson;
  const SendDetailScreen({super.key, required this.tokenJson});

  @override
  State<SendDetailScreen> createState() => _SendDetailScreenState();
}

class _SendDetailScreenState extends State<SendDetailScreen> {
  CryptoToken? token;
  bool isLoading = false;
  String address = '';
  String amount = '';
  bool addressError = false;
  bool showAddressBook = false;
  bool showErrorModal = false;
  String errorMessage = '';
  bool showConfirmModal = false;
  bool isPriceLoading = false;
  double pricePerToken = 0.0;
  String walletName = 'My Wallet'; // TODO: Replace with real wallet name from storage/provider
  List<Map<String, String>> addressBook = [
    {'name': 'Ali', 'address': '0x1234567890abcdef1234567890abcdef12345678'},
    {'name': 'Reza', 'address': 'TQ2Qw1k2k3k4k5k6k7k8k9k0k1k2k3k4k5'},
    {'name': 'BTC Friend', 'address': 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh'},
  ];
  String? scannedQr;

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
    _parseToken();
    _fetchPrice();
  }

  void _parseToken() {
    try {
      final decodedJson = Uri.decodeComponent(widget.tokenJson);
      final tokenData = jsonDecode(decodedJson) as Map<String, dynamic>;
      setState(() {
        token = CryptoToken.fromJson(tokenData);
      });
    } catch (e) {
      setState(() {
        token = null;
      });
    }
  }

  void _fetchPrice() async {
    setState(() { isPriceLoading = true; });
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      pricePerToken = 0.0; // Price is fetched from API
      isPriceLoading = false;
    });
  }

  bool get isFormValid => address.isNotEmpty && amount.isNotEmpty && !addressError;

  void _onPaste() async {
    final data = await Clipboard.getData('text/plain');
    final val = data?.text ?? '';
    setState(() {
      address = val;
      addressError = val.isNotEmpty && !_isValidAddress(val, token!.blockchainName);
    });
  }

  void _onQrScan() async {
    final result = await Navigator.pushNamed(context, '/qr-scanner');
    if (result != null && result is String && result.isNotEmpty) {
      // Parse QR: address[?amount=...]
      final parts = result.split('?');
      final addr = parts[0];
      String? amt;
      if (parts.length > 1) {
        final params = Uri.splitQueryString(parts[1]);
        amt = params['amount'];
      }
      setState(() {
        address = addr;
        addressError = addr.isNotEmpty && !_isValidAddress(addr, token!.blockchainName);
        if (amt != null) amount = amt;
      });
    }
  }

  void _onMax() {
    setState(() {
      amount = (token!.amount ?? 0.0).toStringAsFixed(8);
    });
  }

  void _onSelectAddress(String addr) {
    setState(() {
      address = addr;
      addressError = addr.isNotEmpty && !_isValidAddress(addr, token!.blockchainName);
      showAddressBook = false;
    });
  }

  void _onNext() async {
    if (!isFormValid) return;
    setState(() { isLoading = true; });
    await Future.delayed(const Duration(milliseconds: 800));
    // Fake: check if sending to self
    if (address == '0x1234567890abcdef1234567890abcdef12345678') {
      setState(() {
        isLoading = false;
        showErrorModal = true;
        errorMessage = _safeTranslate('cannot_send_to_own_address', 'You cannot send assets to your own address.');
      });
      return;
    }
    setState(() {
      isLoading = false;
      showConfirmModal = true;
    });
  }

  void _onSend() async {
    setState(() { isLoading = true; });
    
    // Simulate sending transaction
    final transactionId = 'tx_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create pending transaction
    final pendingTransaction = Transaction(
      txHash: transactionId,
      from: '0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6', // User wallet address
      to: address,
      amount: amount,
      tokenSymbol: token!.symbol ?? '',
      direction: 'outbound',
      status: 'pending',
      timestamp: DateTime.now().toIso8601String(),
      blockchainName: token!.blockchainName ?? '',
      price: null,
      temporaryId: null,
    );
    
    // Add pending transaction to HistoryProvider
    final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
    historyProvider.addPendingTransaction(pendingTransaction);
    
    // Show pending transaction notification
    TransactionNotificationReceiver.instance.notifyTransactionPending(transactionId);
    
    await Future.delayed(const Duration(seconds: 2));
    
    // Simulate transaction confirmation (in real case, get from server)
    final isSuccess = true; // In real case, get from API
    
    setState(() {
      isLoading = false;
      showConfirmModal = false;
    });
    
    if (isSuccess) {
      // Update transaction status to completed
      historyProvider.updatePendingTransactionStatus(transactionId, 'completed');
      
      // Show transaction confirmation notification
      TransactionNotificationReceiver.instance.notifyTransactionConfirmed(transactionId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_safeTranslate('transaction_sent', 'Transaction sent!'))));
    } else {
      // Update transaction status to failed
      historyProvider.updatePendingTransactionStatus(transactionId, 'failed');
      
      // Show transaction failure notification
      TransactionNotificationReceiver.instance.notifyTransactionFailed(transactionId, 'خطای شبکه');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_safeTranslate('transaction_failed', 'Transaction failed!'))));
    }
    
    Navigator.pop(context);
  }

  bool _isValidAddress(String address, String? blockchainName) {
    final chain = (blockchainName ?? '').toLowerCase();
    if (chain.contains('tron')) {
      return address.startsWith('T') && address.length == 34;
    }
    if (chain.contains('bitcoin')) {
      return (address.startsWith('bc1') && address.length >= 42 && address.length <= 62) ||
             ((address.startsWith('1') || address.startsWith('3')) && address.length >= 26 && address.length <= 35);
    }
    // Default: EVM
    return address.startsWith('0x') && address.length == 42;
  }

  String _getDollarValue() {
    final price = pricePerToken;
    final amt = double.tryParse(amount) ?? 0.0;
    return (price * amt).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    if (token == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('send_token', 'Send Token')),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: Center(child: Text(_safeTranslate('token_not_found', 'Token not found'))),
      );
    }
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _safeTranslate('send_symbol', 'Send {symbol}').replaceAll('{symbol}', token!.symbol ?? ''),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(_safeTranslate('address_or_domain_name', 'Address or Domain Name'), style: const TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) {
                          setState(() {
                            address = val;
                            addressError = val.isNotEmpty && !_isValidAddress(val, token!.blockchainName);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: _safeTranslate('search_or_enter', 'Search or Enter'),
                          errorText: addressError ? _safeTranslate('wallet_address_not_valid', 'The wallet address entered is not valid.') : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.paste, color: Color(0xFF08C495)),
                                onPressed: _onPaste,
                              ),
                              IconButton(
                                icon: const Icon(Icons.menu_book, color: Color(0xFF08C495)),
                                onPressed: () { setState(() { showAddressBook = true; }); },
                              ),
                              IconButton(
                                icon: const Icon(Icons.qr_code, color: Color(0xFF08C495)),
                                onPressed: _onQrScan,
                              ),
                              if (address.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () { setState(() { address = ''; addressError = false; }); },
                                ),
                            ],
                          ),
                        ),
                        controller: TextEditingController(text: address),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(_safeTranslate('amount', 'Amount'), style: const TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) { setState(() { amount = val; }); },
                        decoration: InputDecoration(
                          hintText: _safeTranslate('symbol_amount', '{symbol} Amount').replaceAll('{symbol}', token!.symbol ?? ''),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _onMax,
                                child: Text(_safeTranslate('max', 'Max'), style: const TextStyle(color: Color(0xFF08C495), fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        controller: TextEditingController(text: amount),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                isPriceLoading
                  ? Row(
                      children: [
                        const SizedBox(width: 4),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Text(_safeTranslate('fetching_latest_price', 'Fetching latest price...'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    )
                  : Text(
                      '≈ \$${_getDollarValue()}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: isFormValid && !isLoading ? _onNext : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF08C495),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_safeTranslate('next', 'Next'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
        // Address Book BottomSheet
        bottomSheet: showAddressBook ? _AddressBookSheet(
          addressBook: addressBook,
          onSelect: _onSelectAddress,
          onClose: () => setState(() => showAddressBook = false),
        ) : null,
      ),
    );
  }
}

class _AddressBookSheet extends StatelessWidget {
  final List<Map<String, String>> addressBook;
  final void Function(String) onSelect;
  final VoidCallback onClose;
  const _AddressBookSheet({required this.addressBook, required this.onSelect, required this.onClose});

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
    return Container(
      height: 420,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                Text(_safeTranslate(context, 'address_book', 'Address Book'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: onClose),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: addressBook.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final wallet = addressBook[index];
                return GestureDetector(
                  onTap: () => onSelect(wallet['address'] ?? ''),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(wallet['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text(wallet['address'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white)),
                            ],
                          ),
                        ),
                        Image.asset('assets/images/rightarrow.png', width: 18, height: 18, color: Colors.white),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
} 