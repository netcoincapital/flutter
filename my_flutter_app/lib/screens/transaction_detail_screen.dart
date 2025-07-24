import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transaction.dart';
import '../layout/main_layout.dart';
import '../services/api_models.dart' as api;
import '../services/service_provider.dart';
import '../services/secure_storage.dart';
import '../utils/number_formatter.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Transaction? transaction;
  final String? amount;
  final String? symbol;
  final String? fiat;
  final String? date;
  final String? status;
  final String? sender;
  final String? networkFee;
  final String? hash;
  final String? transactionId; // اضافه شده برای دریافت تراکنش بر اساس txHash
  
  const TransactionDetailScreen({
    Key? key, 
    this.transaction,
    this.amount,
    this.symbol,
    this.fiat,
    this.date,
    this.status,
    this.sender,
    this.networkFee,
    this.hash,
    this.transactionId, // پارامتر جدید
  }) : super(key: key);

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool isLoading = false;
  String explorerUrl = '';
  
  // State variables for transaction details (will be populated from API if transactionId is provided)
  Transaction? loadedTransaction;
  
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
    
    // اگر transactionId موجود است، تراکنش را از API دریافت کن (مطابق با transaction_detail.kt)
    if (widget.transactionId != null && widget.transactionId!.isNotEmpty) {
      print('🔍 TransactionDetail: Loading from API with txHash: ${widget.transactionId}');
      _loadTransactionDetails();
    } else {
      _fetchExplorerUrl();
    }
  }

  /// دریافت جزئیات تراکنش از API مطابق با transaction_detail.kt
  Future<void> _loadTransactionDetails() async {
    setState(() { isLoading = true; });
    
    try {
      final userId = await SecureStorage.getUserId();
      if (userId == null || userId.isEmpty) {
        print('❌ TransactionDetail: No userId found');
        setState(() { isLoading = false; });
        return;
      }
      
      final transactionId = widget.transactionId;
      if (transactionId == null || transactionId.isEmpty) {
        print('❌ TransactionDetail: No transactionId provided');
        setState(() { isLoading = false; });
        return;
      }
      
      print('🔍 TransactionDetail: Loading transaction details for txHash: $transactionId (matching transaction_detail.kt)');
      
      final apiService = ServiceProvider.instance.apiService;
      
      // استفاده از getTransactions مطابق با کاتلین
      final request = api.TransactionsRequest(userID: userId);
      final response = await apiService.getTransactions(request);
      
      print('🔍 TransactionDetail: API response status: ${response.status}');
      print('🔍 TransactionDetail: Total transactions received: ${response.transactions.length}');
      
      if (response.status == "success") {
        // جستجو برای یافتن تراکنش با txHash مطابق با کاتلین
        final transaction = response.transactions.firstWhere(
          (tx) => (tx.txHash ?? '') == transactionId,
          orElse: () => throw Exception('Transaction not found with txHash: $transactionId'),
        );
        
        print('✅ TransactionDetail: Found transaction: ${transaction.txHash ?? 'unknown'}');
        print('✅ TransactionDetail: Transaction details:');
        print('   amount: ${transaction.amount}');
        print('   status: ${transaction.status}');
        print('   direction: ${transaction.direction}');
        print('   from: ${transaction.from}');
        print('   to: ${transaction.to}');
        print('   timestamp: ${transaction.timestamp}');
        print('   price: ${transaction.price}');
        print('   explorerUrl: ${transaction.explorerUrl}');
        print('   fee: ${transaction.fee}');
        print('   assetType: ${transaction.assetType}');
        
        // تبدیل به Transaction مدل محلی با null safety
        loadedTransaction = Transaction(
          txHash: transaction.txHash ?? '',
          from: transaction.from ?? '',
          to: transaction.to ?? '',
          amount: transaction.amount ?? '0',
          tokenSymbol: transaction.tokenSymbol ?? '',
          direction: transaction.direction ?? 'unknown',
          status: transaction.status ?? 'unknown',
          timestamp: transaction.timestamp ?? DateTime.now().toIso8601String(),
          blockchainName: transaction.blockchainName ?? '',
          price: transaction.price,
          temporaryId: transaction.temporaryId,
          explorerUrl: transaction.explorerUrl,
          fee: transaction.fee,
          assetType: transaction.assetType,
          tokenContract: transaction.tokenContract,
        );
        
        print('✅ TransactionDetail: Successfully created loadedTransaction');
        print('   loadedTransaction.amount: ${loadedTransaction!.amount}');
        print('   loadedTransaction.status: ${loadedTransaction!.status}');
      } else {
        print('❌ TransactionDetail: API returned error status: ${response.status}');
        throw Exception('Failed to fetch transaction details');
      }
    } catch (e) {
      print('❌ TransactionDetail: Error loading transaction details: $e');
      // در صورت خطا، از داده‌های ورودی استفاده کن
    } finally {
      setState(() { isLoading = false; });
      _fetchExplorerUrl();
    }
  }

  void _fetchExplorerUrl() async {
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() {
      // ابتدا سعی می‌کنیم از explorerUrl که از API می‌آید استفاده کنیم
      String? apiExplorerUrl = loadedTransaction?.explorerUrl ?? widget.transaction?.explorerUrl;
      
      print('🔍 Transaction Detail: Checking explorer URLs:');
      print('   loadedTransaction?.explorerUrl: ${loadedTransaction?.explorerUrl}');
      print('   widget.transaction?.explorerUrl: ${widget.transaction?.explorerUrl}');
      print('   Final apiExplorerUrl: $apiExplorerUrl');
      
      if (apiExplorerUrl != null && apiExplorerUrl.isNotEmpty) {
        explorerUrl = apiExplorerUrl;
        print('✅ Transaction Detail: Using API explorer URL: $explorerUrl');
      } else {
        // اگر API explorer URL ندارد، خودمان می‌سازیم
        final txHash = widget.hash ?? loadedTransaction?.txHash ?? widget.transaction?.txHash ?? '';
        final blockchain = loadedTransaction?.blockchainName ?? widget.transaction?.blockchainName ?? '';
        
        print('⚠️ Transaction Detail: No API explorer URL found, building manually');
        print('   TxHash: $txHash');
        print('   Blockchain: $blockchain');
        
        if (txHash.isNotEmpty) {
          explorerUrl = _buildExplorerUrl(blockchain, txHash);
          print('   Generated Explorer URL: $explorerUrl');
        } else {
          print('❌ Transaction Detail: No txHash found, cannot generate explorer URL');
        }
      }
      
      print('🎯 Transaction Detail: Final explorerUrl set to: $explorerUrl');
    });
  }

  String _buildExplorerUrl(String blockchain, String txHash) {
    // ساخت URL explorer بر اساس blockchain
    switch (blockchain.toLowerCase()) {
      case 'ethereum':
        return 'https://etherscan.io/tx/$txHash';
      case 'bitcoin':
        return 'https://blockstream.info/tx/$txHash';
      case 'polygon':
        return 'https://polygonscan.com/tx/$txHash';
      case 'binance':
      case 'bsc':
        return 'https://bscscan.com/tx/$txHash';
      case 'avalanche':
        return 'https://snowtrace.io/tx/$txHash';
      case 'arbitrum':
        return 'https://arbiscan.io/tx/$txHash';
      case 'optimism':
        return 'https://optimistic.etherscan.io/tx/$txHash';
      case 'fantom':
        return 'https://ftmscan.com/tx/$txHash';
      case 'solana':
        return 'https://solscan.io/tx/$txHash';
      case 'tron':
        return 'https://tronscan.org/#/transaction/$txHash';
      case 'cardano':
        return 'https://cardanoscan.io/transaction/$txHash';
      case 'polkadot':
        return 'https://polkadot.subscan.io/extrinsic/$txHash';
      case 'cosmos':
        return 'https://www.mintscan.io/cosmos/txs/$txHash';
      case 'xrp':
        return 'https://xrpscan.com/tx/$txHash';
      default:
        return 'https://etherscan.io/tx/$txHash'; // fallback to Ethereum
    }
  }

  String _getAmount() {
    String amount = '0';
    String symbol = _getSymbol();
    
    if (widget.amount != null) {
      amount = widget.amount!;
    } else if (loadedTransaction != null) {
      final tx = loadedTransaction!;
      final isInbound = tx.direction == 'inbound';
      amount = NumberFormatter.formatTransactionAmount(tx.amount, isInbound);
    } else if (widget.transaction != null) {
      final tx = widget.transaction!;
      final isInbound = tx.direction == 'inbound';
      amount = NumberFormatter.formatTransactionAmount(tx.amount, isInbound);
    }
    
    // اضافه کردن symbol به amount
    if (symbol.isNotEmpty) {
      return '$amount $symbol';
    }
    return amount;
  }

  String _getSymbol() {
    return widget.symbol ?? loadedTransaction?.tokenSymbol ?? widget.transaction?.tokenSymbol ?? '';
  }

  String _getFiat() {
    if (widget.fiat != null) return widget.fiat!;
    if (loadedTransaction != null) {
      final tx = loadedTransaction!;
      try {
        final amount = double.parse(tx.amount);
        final price = tx.price ?? 0.0;
        final value = amount * price;
        return NumberFormatter.formatCurrency(value, '≈ \$');
      } catch (e) {
        return '≈ \$0.00';
      }
    }
    return '≈ \$0.00';
  }

  String _getDate() {
    if (widget.date != null) return widget.date!;
    
    String? timestamp;
    if (loadedTransaction != null) {
      timestamp = loadedTransaction!.timestamp;
    } else if (widget.transaction != null) {
      timestamp = widget.transaction!.timestamp;
    }
    
    if (timestamp != null && timestamp.isNotEmpty) {
      try {
        final dateTime = DateTime.parse(timestamp);
        return DateFormat('MMM d, yyyy, h:mm a').format(dateTime);
      } catch (e) {
        print('❌ TransactionDetail: Error parsing date: $e');
        return timestamp; // Return raw timestamp if parsing fails
      }
    }
    
    return _safeTranslate('unknown_date', 'Unknown Date');
  }

  String _getStatus() {
    String status = 'completed'; // Default to completed for API transactions
    
    if (widget.status != null) {
      status = widget.status!;
    } else if (loadedTransaction != null) {
      final apiStatus = loadedTransaction!.status.toLowerCase();
      // Map API status values to standard values
      switch (apiStatus) {
        case 'success':
        case 'confirmed':
        case 'completed':
        case 'mined':
          status = 'completed';
          break;
        case 'pending':
        case 'unconfirmed':
          status = 'pending';
          break;
        case 'failed':
        case 'error':
        case 'rejected':
          status = 'failed';
          break;
        default:
          status = 'completed'; // Default for unknown API statuses
      }
    } else if (widget.transaction != null) {
      status = widget.transaction!.status;
    }
    
    // Translate status based on value
    switch (status.toLowerCase()) {
      case 'completed':
        return _safeTranslate('completed', 'Completed');
      case 'pending':
        return _safeTranslate('pending', 'Pending');
      case 'failed':
        return _safeTranslate('failed', 'Failed');
      default:
        return _safeTranslate('completed', 'Completed'); // Default to completed
    }
  }

  String _getSenderOrRecipient() {
    if (widget.sender != null) return _formatAddress(widget.sender!);
    
    if (loadedTransaction != null) {
      final tx = loadedTransaction!;
      final isInbound = tx.direction == 'inbound';
      final address = isInbound ? tx.from : tx.to; // inbound: from sender, outbound: to recipient
      return _formatAddress(address ?? '');
    }
    
    if (widget.transaction != null) {
      final tx = widget.transaction!;
      final isInbound = tx.direction == 'inbound';
      final address = isInbound ? tx.from : tx.to;
      return _formatAddress(address ?? '');
    }
    
    return _safeTranslate('unknown', 'Unknown');
  }
  
  String _getSenderOrRecipientLabel() {
    // برای route parameters، بسته به amount prefix تشخیص بده
    if (widget.amount != null) {
      final isInbound = widget.amount!.startsWith('+');
      return isInbound 
          ? _safeTranslate('sender', 'Sender')
          : _safeTranslate('recipient', 'Recipient');
    }
    
    if (loadedTransaction != null) {
      final isInbound = loadedTransaction!.direction == 'inbound';
      return isInbound 
          ? _safeTranslate('sender', 'Sender')
          : _safeTranslate('recipient', 'Recipient');
    }
    
    if (widget.transaction != null) {
      final isInbound = widget.transaction!.direction == 'inbound';
      return isInbound 
          ? _safeTranslate('sender', 'Sender')
          : _safeTranslate('recipient', 'Recipient');
    }
    
    return _safeTranslate('sender', 'Sender'); // default
  }

  String _getNetworkFee() {
    final fee = widget.networkFee ?? '0';
    try {
      final feeDouble = double.parse(fee.replaceAll(RegExp(r'[^\d.]'), ''));
      return NumberFormatter.formatDouble(feeDouble);
    } catch (e) {
      return fee;
    }
  }

  String _getHash() {
    return widget.hash ?? loadedTransaction?.txHash ?? widget.transaction?.txHash ?? '';
  }

  /// باز کردن URL explorer در مرورگر داخلی اپلیکیشن
  Future<void> _openExplorerUrl() async {
    if (explorerUrl.isEmpty) {
      print('❌ Transaction Detail: No explorer URL available');
      return;
    }

    print('🔗 Transaction Detail: Opening explorer URL in app: $explorerUrl');

    try {
      final uri = Uri.parse(explorerUrl);
      if (await canLaunchUrl(uri)) {
        // استفاده از مرورگر داخلی اپلیکیشن
        await launchUrl(
          uri,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
        print('✅ Transaction Detail: Successfully opened in in-app browser');
      } else {
        print('❌ Transaction Detail: Cannot launch URL: $explorerUrl');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_safeTranslate('cannot_open_explorer', 'Cannot open explorer')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (launchError) {
      print('❌ Transaction Detail: Launch URL failed: $launchError');
      
      // Fallback: اگر inAppWebView کار نکرد، به external browser برو
      try {
        print('🔄 Transaction Detail: Fallback to external browser');
        final uri = Uri.parse(explorerUrl);
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('✅ Transaction Detail: Fallback successful - opened in external browser');
      } catch (fallbackError) {
        print('❌ Transaction Detail: Fallback also failed: $fallbackError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_safeTranslate('error_opening_explorer', 'Error opening explorer')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// اشتراک گذاری تراکنش (همراه با URL explorer در صورت وجود)
  Future<void> _shareTransaction() async {
    try {
      print('📤 Transaction Detail: Sharing transaction...');
      
      // ساخت متن مناسب برای اشتراک‌گذاری
      final txHash = _getHash();
      final symbol = _getSymbol();
      final amount = _getAmount();
      final date = _getDate();
      final status = _getStatus();
      
      // ساخت متن کامل تراکنش
      String shareText = '';
      
      if (explorerUrl.isNotEmpty) {
        final shareTextTemplate = _safeTranslate(
          'share_transaction_text', 
          'Transaction Details:\n\nAmount: {amount}\nHash: {hash}\n\nView on Explorer:'
        );
        
        // جایگزینی placeholders با مقادیر واقعی
        shareText = shareTextTemplate
            .replaceAll('{amount}', amount)
            .replaceAll('{hash}', txHash);
        
        shareText = '$shareText\n$explorerUrl';
        print('✅ Transaction Detail: Sharing with explorer URL: $explorerUrl');
      } else {
        // اگر explorer URL نیست، فقط اطلاعات اساسی
        shareText = _safeTranslate('transaction_details', 'Transaction Details') + ':\n\n' +
                   _safeTranslate('amount', 'Amount') + ': $amount\n' +
                   _safeTranslate('date', 'Date') + ': $date\n' +
                   _safeTranslate('status', 'Status') + ': $status\n' +
                   'Hash: $txHash';
        print('⚠️ Transaction Detail: Sharing without explorer URL');
      }
      
      await Share.share(
        shareText,
        subject: _safeTranslate('transaction_details', 'Transaction Details'),
      );
      
      print('✅ Transaction Detail: Successfully shared transaction');
    } catch (shareError) {
      print('❌ Transaction Detail: Share failed: $shareError');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('share_failed', 'Failed to share transaction')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatAddress(String address) {
    if (address.length > 11) {
      return '${address.substring(0, 6)}.....${address.substring(address.length - 5)}';
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    final amountStr = _getAmount();
    final fiatStr = _getFiat();
    final dateStr = _getDate();
    final statusStr = _getStatus();
    final senderRecipientLabel = _getSenderOrRecipientLabel();
    final addressStr = _getSenderOrRecipient();
    final feeStr = _getNetworkFee();

    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.black),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(_safeTranslate('transfer', 'Transfer'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.black),
                          onPressed: _shareTransaction, // همیشه فعال باشد
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Amount
                    Center(
                      child: Column(
                        children: [
                          Text(amountStr, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(fiatStr, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Details Card
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F9FC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _DetailRow(label: _safeTranslate('date', 'Date'), value: dateStr),
                          const Divider(height: 24, color: Color(0xFFEEEEEE)),
                          _DetailRow(label: _safeTranslate('status', 'Status'), value: statusStr),
                          const Divider(height: 24, color: Color(0xFFEEEEEE)),
                          _DetailRow(label: senderRecipientLabel, value: addressStr),
                          const Divider(height: 24, color: Color(0xFFEEEEEE)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(_safeTranslate('network_fee', 'Network fee'), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF11c699).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _safeTranslate('estimated', 'Estimated'),
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF11c699)),
                                    ),
                                  ),
                                ],
                              ),
                              Text(feeStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Explorer Button
                    if (explorerUrl.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _openExplorerUrl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF11c699),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _safeTranslate('view_on_explorer', 'View on Explorer'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
} 