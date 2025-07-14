import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:my_flutter_app/screens/receive_wallet_screen.dart';
import '../models/transaction.dart';
import '../services/api_models.dart' as api;
import '../services/secure_storage.dart';
import '../services/service_provider.dart';
import '../providers/price_provider.dart';

class CryptoDetailsScreen extends StatefulWidget {
  final String tokenName;
  final String tokenSymbol;
  final String iconUrl;
  final bool isToken;
  final String blockchainName;
  final double gasFee;
  // سایر پارامترهای مورد نیاز مانند قیمت، مقدار و ...

  const CryptoDetailsScreen({
    Key? key,
    required this.tokenName,
    required this.tokenSymbol,
    required this.iconUrl,
    required this.isToken,
    required this.blockchainName,
    required this.gasFee,
  }) : super(key: key);

  @override
  State<CryptoDetailsScreen> createState() => _CryptoDetailsScreenState();
}

class _CryptoDetailsScreenState extends State<CryptoDetailsScreen> {
  Color? dominantColor;

  List<Transaction> transactions = [];
  bool isLoading = true;
  String? errorMessage;
  double tokenBalance = 0.0;
  bool isLoadingBalance = true;

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
    _updatePalette(widget.iconUrl);
    _loadTransactions();
    _loadTokenBalance(); // اضافه کردن بارگذاری موجودی توکن
    
    // Load selected currency and fetch price for this token (مطابق با Kotlin crypto_details.kt)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      await priceProvider.loadSelectedCurrency();
      
      // دریافت قیمت این توکن خاص (مطابق با Kotlin crypto_details.kt)
      await priceProvider.fetchPrices([widget.tokenSymbol], currencies: [priceProvider.selectedCurrency]);
    });
  }

  /// دریافت موجودی توکن خاص (مطابق با crypto_details.kt)
  Future<void> _loadTokenBalance() async {
    setState(() {
      isLoadingBalance = true;
    });

    try {
      final userId = await SecureStorage.getUserId();
      if (userId != null) {
        print('🔍 CryptoDetails - Loading balance for token: ${widget.tokenSymbol}');
        print('🔍 CryptoDetails - UserID: $userId');
        
        final apiService = ServiceProvider.instance.apiService;
        
        // استفاده از getBalance API مطابق با crypto_details.kt (توکن خاص)
        final response = await apiService.getBalance(
          userId,
          currencyNames: [widget.tokenSymbol], // فقط توکن خاص مانند کاتلین
          blockchain: {},
        );
        
        print('📥 CryptoDetails - API Response:');
        print('   Success: ${response.success}');
        print('   Balances count: ${response.balances?.length ?? 0}');
        
        if (response.success && response.balances != null && response.balances!.isNotEmpty) {
          // با توجه به اینکه فقط یک توکن درخواست شده، باید فقط یک نتیجه داشته باشیم
          double finalBalance = 0.0;
          
          print('🔍 CryptoDetails - Looking for token: "${widget.tokenSymbol.toUpperCase()}"');
          print('🔍 CryptoDetails - Available balances in response:');
          
          // جستجو برای پیدا کردن موجودی توکن مورد نظر
          for (int i = 0; i < response.balances!.length; i++) {
            final balance = response.balances![i];
            print('   [$i] Symbol: "${balance.symbol}", Balance: "${balance.balance}", Blockchain: "${balance.blockchain}"');
            
            if (balance.symbol?.toUpperCase() == widget.tokenSymbol.toUpperCase()) {
              finalBalance = double.tryParse(balance.balance ?? '0') ?? 0.0;
              print('✅ CryptoDetails - Token balance found: ${widget.tokenSymbol} = $finalBalance');
              break;
            } else {
              print('   ❌ Symbol "${balance.symbol?.toUpperCase()}" != "${widget.tokenSymbol.toUpperCase()}"');
            }
          }
          
          print('✅ CryptoDetails - Final balance for ${widget.tokenSymbol}: $finalBalance');
          
          setState(() {
            tokenBalance = finalBalance;
            isLoadingBalance = false;
          });
        } else {
          print('❌ CryptoDetails - No balance data received');
          setState(() {
            tokenBalance = 0.0;
            isLoadingBalance = false;
          });
        }
      } else {
        print('❌ CryptoDetails - No userId found');
        setState(() {
          tokenBalance = 0.0;
          isLoadingBalance = false;
        });
      }
    } catch (e) {
      print('❌ CryptoDetails - Error loading token balance: $e');
      setState(() {
        tokenBalance = 0.0;
        isLoadingBalance = false;
      });
    }
  }

  Future<void> _updatePalette(String iconUrl) async {
    try {
      final ImageProvider provider = iconUrl.startsWith('http')
          ? NetworkImage(iconUrl)
          : AssetImage(iconUrl) as ImageProvider;
      // Palette generation removed for now
      print('Palette generation removed');
              setState(() {
          dominantColor = const Color(0x80D7FBE7);
        });
    } catch (_) {
      setState(() {
        dominantColor = const Color(0x80D7FBE7);
      });
    }
  }

  Future<void> _loadTransactions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final userId = await SecureStorage.getUserId();
      if (userId != null && userId.isNotEmpty) {
        print('🔍 CryptoDetails: Fetching transactions for user: $userId, token: ${widget.tokenSymbol}');
        
        final apiService = ServiceProvider.instance.apiService;
        
        // سعی کن ابتدا با ارسال TokenSymbol به API
        var response = await apiService.getTransactionsForToken(userId, widget.tokenSymbol);
        
        print('🔍 CryptoDetails: API response status: ${response.status}');
        print('🔍 CryptoDetails: Server-side filtered transactions: ${response.transactions.length}');
        
        // اگر هیچ تراکنشی نیامد، احتمالاً server-side filtering کار نکرده
        // بیایید تمام تراکنش‌ها را بگیریم و خودمان فیلتر کنیم
        if (response.status == "success" && response.transactions.isEmpty) {
          print('🔍 CryptoDetails: No transactions from server-side filter, trying client-side filter...');
          
          // دریافت تمام تراکنش‌ها
          response = await apiService.getTransactionsForUser(userId);
          print('🔍 CryptoDetails: Total transactions received: ${response.transactions.length}');
          
          if (response.status == "success") {
            // فیلتر کردن در سمت کلاینت
            final filteredTransactions = response.transactions.where((tx) {
              final txSymbol = tx.tokenSymbol ?? '';
              final widgetSymbol = widget.tokenSymbol ?? '';
              final matches = txSymbol.toLowerCase() == widgetSymbol.toLowerCase();
              print('🔍 CryptoDetails: Transaction ${tx.txHash ?? 'unknown'} - Symbol: "$txSymbol" vs "$widgetSymbol", Match: $matches');
              return matches;
            }).toList();
            
            print('🔍 CryptoDetails: Client-side filtered transactions: ${filteredTransactions.length}');
            
            setState(() {
              transactions = filteredTransactions
                  .map((apiTx) => Transaction(
                        txHash: apiTx.txHash ?? '',
                        from: apiTx.from ?? '',
                        to: apiTx.to ?? '',
                        amount: apiTx.amount ?? '0',
                        tokenSymbol: apiTx.tokenSymbol ?? '',
                        direction: apiTx.direction ?? 'unknown',
                        status: apiTx.status ?? 'unknown',
                        timestamp: apiTx.timestamp ?? DateTime.now().toIso8601String(),
                        blockchainName: apiTx.blockchainName ?? '',
                        price: apiTx.price,
                        temporaryId: apiTx.temporaryId,
                      ))
                  .toList();
              isLoading = false;
            });
            
            print('✅ CryptoDetails: Successfully loaded ${transactions.length} transactions for ${widget.tokenSymbol} (client-side filter)');
          } else {
            print('❌ CryptoDetails: API returned error status: ${response.status}');
            setState(() {
              errorMessage = 'Failed to fetch transactions';
              isLoading = false;
            });
          }
        } else if (response.status == "success") {
          // Server-side filtering کار کرده
          setState(() {
            transactions = response.transactions
                .map((apiTx) => Transaction(
                      txHash: apiTx.txHash ?? '',
                      from: apiTx.from ?? '',
                      to: apiTx.to ?? '',
                      amount: apiTx.amount ?? '0',
                      tokenSymbol: apiTx.tokenSymbol ?? '',
                      direction: apiTx.direction ?? 'unknown',
                      status: apiTx.status ?? 'unknown',
                      timestamp: apiTx.timestamp ?? DateTime.now().toIso8601String(),
                      blockchainName: apiTx.blockchainName ?? '',
                      price: apiTx.price,
                      temporaryId: apiTx.temporaryId,
                    ))
                .toList();
            isLoading = false;
          });
          
          print('✅ CryptoDetails: Successfully loaded ${transactions.length} transactions for ${widget.tokenSymbol} (server-side filter)');
        } else {
          print('❌ CryptoDetails: API returned error status: ${response.status}');
          setState(() {
            errorMessage = 'Failed to fetch transactions';
            isLoading = false;
          });
        }
      } else {
        print('❌ CryptoDetails: No userId found');
        setState(() {
          errorMessage = 'User ID not found';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ CryptoDetails: Error loading transactions: $e');
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Widget _buildTokenIcon(String iconUrl) {
    if (iconUrl.startsWith('http')) {
      return Image.network(
        iconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.monetization_on, size: 52, color: Colors.grey),
      );
    } else {
      return Image.asset(
        iconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.monetization_on, size: 52, color: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.notifications, color: Colors.grey),
                    Column(
                      children: [
                        Text(widget.tokenName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(
                          "${widget.isToken ? _safeTranslate('token', 'Token') : _safeTranslate('coin', 'Coin')}  ||  ${widget.tokenSymbol}",
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Icon(Icons.info, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 16),
                // Token Icon with dominant color background
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: dominantColor ?? const Color(0x80D7FBE7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: ClipOval(
                      child: _buildTokenIcon(widget.iconUrl),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // قیمت، مقدار و ... (در اینجا به صورت نمونه)
                isLoadingBalance 
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                    )
                  : Text(
                      '${tokenBalance.toStringAsFixed(6)} ${widget.tokenSymbol}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                const SizedBox(height: 4),
                Consumer<PriceProvider>(
                  builder: (context, priceProvider, child) {
                    final currencySymbol = priceProvider.getCurrencySymbol();
                    final price = priceProvider.getPrice(widget.tokenSymbol) ?? 0.0;
                    final dollarValue = tokenBalance * price;
                    return Text(
                      '≈ ${currencySymbol}${dollarValue.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // دکمه‌های Send و Receive
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ActionButton(
                      assetIcon: 'assets/images/send.png',
                      label: _safeTranslate('send', 'Send'),
                      color: const Color(0x80D7FBE7),
                      onTap: () {},
                    ),
                    _ActionButton(
                      assetIcon: 'assets/images/receive.png',
                      label: _safeTranslate('receive', 'Receive'),
                      color: const Color(0xFFE0F7FA),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReceiveWalletScreen(
                              cryptoName: widget.tokenName,
                              blockchainName: widget.blockchainName,
                              address: '', // آدرس را اینجا مقداردهی کن یا از prop بگیر
                              symbol: widget.tokenSymbol,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // لیست تراکنش‌ها (نمونه)
                const SizedBox(height: 16),
                if (isLoading)
                  const Center(child: CircularProgressIndicator()),
                if (errorMessage != null)
                  Center(child: Text(errorMessage!, style: const TextStyle(color: Colors.red))),
                if (!isLoading && errorMessage == null)
                  _TransactionHistorySection(transactions: transactions, tokenSymbol: widget.tokenSymbol),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String assetIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.assetIcon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Image.asset(
                assetIcon,
                width: 28,
                height: 28,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Transaction history section widget
class _TransactionHistorySection extends StatelessWidget {
  final List<Transaction> transactions;
  final String tokenSymbol;
  const _TransactionHistorySection({required this.transactions, required this.tokenSymbol});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  String _getDateGroup(BuildContext context, String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final transactionDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
      if (transactionDate.isAtSameMomentAs(today)) {
        return _safeTranslate(context, 'today', 'Today');
      } else if (transactionDate.isAtSameMomentAs(yesterday)) {
        return _safeTranslate(context, 'yesterday', 'Yesterday');
      } else {
        return "${dateTime.year}/${dateTime.month}/${dateTime.day}";
      }
    } catch (e) {
      return _safeTranslate(context, 'unknown_date', 'Unknown Date');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Image.asset('assets/images/notransaction.png', width: 80, height: 80),
            const SizedBox(height: 12),
            Text(_safeTranslate(context, 'no_transactions_found', 'No transactions found'), style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    // Group transactions by date
    final grouped = <String, List<Transaction>>{};
    for (final tx in transactions) {
      final group = _getDateGroup(context, tx.timestamp);
      grouped.putIfAbsent(group, () => []).add(tx);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final date in grouped.keys)
            ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(date, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              ...grouped[date]!.map((tx) => _TransactionItem(tx: tx)).toList(),
            ],
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction tx;
  const _TransactionItem({required this.tx});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  String _formatAmount(String amount) {
    try {
      final number = double.parse(amount);
      String formatted = number.toStringAsFixed(6);
      if (formatted.contains('.')) {
        formatted = formatted.replaceFirst(RegExp(r'\.0+ '), '');
        formatted = formatted.replaceFirst(RegExp(r'(\.\d*?[1-9])0+ '), r'\1');
        formatted = formatted.replaceFirst(RegExp(r'\.$'), '');
      }
      return formatted;
    } catch (e) {
      return amount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = tx.direction == "inbound";
    final icon = isReceived ? Icons.arrow_downward : Icons.arrow_upward;
    final iconColor = isReceived ? const Color(0xFF20CDA4) : const Color(0xFFF43672);
    final bgColor = isReceived ? const Color(0xFF20CDA4).withOpacity(0.1) : const Color(0xFFF43672).withOpacity(0.1);
    final address = isReceived ? tx.from : tx.to;
    final shortAddress = address.length > 15 ? "${address.substring(0, 10)}...${address.substring(address.length - 5)}" : address;
    final amountPrefix = isReceived ? "+" : "-";
    final amountValue = "$amountPrefix${_formatAmount(tx.amount)}";
    final isPending = !isReceived && (tx.status ?? '').toLowerCase() == "pending";
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Center(
              child: isPending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xFFF43672),
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isReceived ? _safeTranslate(context, 'receive', 'Receive') : _safeTranslate(context, 'send', 'Send'), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                    if (isPending) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9A825),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_safeTranslate(context, 'pending', 'pending'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                Text(shortAddress, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(amountValue, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: amountValue.startsWith("-") ? const Color(0xFFF43672) : const Color(0xFF11c699))),
                  const SizedBox(width: 2),
                  Text(tx.tokenSymbol, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.black)),
                ],
              ),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  try {
                    final price = tx.price ?? 0.0;
                    if (price > 0.0) {
                      final value = price * double.parse(tx.amount);
                      return Text(
                        "≈ $currencySymbol${value.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    } else {
                      return Text(
                        "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    }
                  } catch (e) {
                    return Text(
                      "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
} 