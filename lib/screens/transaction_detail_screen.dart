import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/transaction.dart';
import '../layout/main_layout.dart';
import '../services/api_models.dart' as api;
import '../services/service_provider.dart';
import '../services/secure_storage.dart';
import 'web_view_screen.dart';

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
        );
        
        print('✅ TransactionDetail: Successfully loaded transaction details');
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
      final txHash = widget.hash ?? loadedTransaction?.txHash ?? widget.transaction?.txHash ?? '';
      explorerUrl = 'https://explorer.example.com/tx/$txHash';
    });
  }

  String _getAmount() {
    if (widget.amount != null) return widget.amount!;
    if (loadedTransaction != null) {
      final tx = loadedTransaction!;
      final prefix = tx.direction == 'inbound' ? '+' : '-';
      return '$prefix${tx.amount}';
    }
    if (widget.transaction != null) {
      final tx = widget.transaction!;
      final prefix = tx.direction == 'inbound' ? '+' : '-';
      return '$prefix${tx.amount}';
    }
    return '0.00';
  }

  String _getSymbol() {
    return widget.symbol ?? loadedTransaction?.tokenSymbol ?? widget.transaction?.tokenSymbol ?? '';
  }

  String _getFiat() {
    return widget.fiat ?? '≈ \$0.00';
  }

  String _getDate() {
    return widget.date ?? loadedTransaction?.timestamp ?? widget.transaction?.timestamp ?? _safeTranslate('unknown_date', 'Unknown Date');
  }

  String _getStatus() {
    final status = widget.status ?? loadedTransaction?.status ?? widget.transaction?.status ?? 'Completed';
    // Translate status based on value
    switch (status.toLowerCase()) {
      case 'completed':
        return _safeTranslate('completed', 'Completed');
      case 'pending':
        return _safeTranslate('pending', 'Pending');
      case 'failed':
        return _safeTranslate('failed', 'Failed');
      default:
        return _safeTranslate('unknown', 'Unknown');
    }
  }

  String _getSender() {
    return widget.sender ?? loadedTransaction?.from ?? widget.transaction?.from ?? _safeTranslate('unknown', 'Unknown');
  }

  String _getNetworkFee() {
    return widget.networkFee ?? '0.00';
  }

  String _getHash() {
    return widget.hash ?? loadedTransaction?.txHash ?? widget.transaction?.txHash ?? '';
  }

  String _formatAddress(String address) {
    if (address.length > 12) {
      return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    final amountStr = _getAmount();
    final fiatStr = _getFiat();
    final dateStr = _getDate();
    final statusStr = _getStatus();
    final addressStr = _formatAddress(_getSender());
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
                          onPressed: explorerUrl.isNotEmpty ? () {
                            // Remove success message - share silently
                          } : null,
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
                          _DetailRow(label: _safeTranslate('sender', 'Sender'), value: addressStr),
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
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WebViewScreen(
                                  url: explorerUrl,
                                ),
                              ),
                            );
                          },
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