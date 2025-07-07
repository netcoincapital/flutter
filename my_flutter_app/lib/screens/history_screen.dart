import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../layout/main_layout.dart';
import '../models/transaction.dart';
import '../utils/transaction_cache.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Transaction> transactions = [];
  bool isLoading = true;
  String? errorMessage;
  String selectedNetwork = "All Networks";
  bool isRefreshing = false;

  // Mock data for demonstration
  final List<Transaction> mockTransactions = [
    Transaction(
      txHash: "0x1234567890abcdef",
      from: "0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6",
      to: "0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6",
      amount: "0.1234",
      tokenSymbol: "ETH",
      direction: "inbound",
      status: "completed",
      timestamp: "2024-01-15T10:30:00Z",
      blockchainName: "Ethereum",
      price: 3200.0,
    ),
    Transaction(
      txHash: "0xabcdef1234567890",
      from: "0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6",
      to: "0x1234567890abcdef1234567890abcdef12345678",
      amount: "0.05",
      tokenSymbol: "ETH",
      direction: "outbound",
      status: "pending",
      timestamp: "2024-01-15T09:15:00Z",
      blockchainName: "Ethereum",
      price: 3200.0,
    ),
    Transaction(
      txHash: "0x9876543210fedcba",
      from: "0xabcdef1234567890abcdef1234567890abcdef12",
      to: "0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6",
      amount: "1000",
      tokenSymbol: "USDT",
      direction: "inbound",
      status: "completed",
      timestamp: "2024-01-14T16:45:00Z",
      blockchainName: "Ethereum",
      price: 1.0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Simulate API call delay
      await Future.delayed(const Duration(seconds: 1));
      
      setState(() {
        transactions = mockTransactions;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _refreshTransactions() async {
    setState(() {
      isRefreshing = true;
    });

    await _loadTransactions();

    setState(() {
      isRefreshing = false;
    });
  }

  String _formatAmount(String amount) {
    try {
      final number = double.parse(amount);
      final formatted = number.toStringAsFixed(6).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
      return formatted;
    } catch (e) {
      return amount;
    }
  }

  String _getDateGroup(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final transactionDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      if (transactionDate.isAtSameMomentAs(today)) {
        return "Today";
      } else if (transactionDate.isAtSameMomentAs(yesterday)) {
        return "Yesterday";
      } else {
        return DateFormat('MMM d, yyyy').format(dateTime);
      }
    } catch (e) {
      return "Unknown Date";
    }
  }

  Map<String, List<Transaction>> _groupTransactionsByDate() {
    final allTransactions = [...LocalTransactionCache.pendingTransactions, ...transactions]
        .where((tx) => selectedNetwork == "All Networks" || tx.blockchainName == selectedNetwork)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final grouped = <String, List<Transaction>>{};
    for (final transaction in allTransactions) {
      final dateGroup = _getDateGroup(transaction.timestamp);
      grouped.putIfAbsent(dateGroup, () => []).add(transaction);
    }
    return grouped;
  }

  void _showNetworkFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Color(0xFFF6F6F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Blockchain",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  _NetworkOption(
                    name: "All Networks",
                    icon: "assets/images/all.png",
                    isSelected: selectedNetwork == "All Networks",
                    onTap: () {
                      setState(() => selectedNetwork = "All Networks");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Bitcoin",
                    icon: "assets/images/btc.png",
                    isSelected: selectedNetwork == "Bitcoin",
                    onTap: () {
                      setState(() => selectedNetwork = "Bitcoin");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Ethereum",
                    icon: "assets/images/ethereum_logo.png",
                    isSelected: selectedNetwork == "Ethereum",
                    onTap: () {
                      setState(() => selectedNetwork = "Ethereum");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "BNB Smart Chain",
                    icon: "assets/images/binance_logo.png",
                    isSelected: selectedNetwork == "BNB Smart Chain",
                    onTap: () {
                      setState(() => selectedNetwork = "BNB Smart Chain");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Polygon",
                    icon: "assets/images/pol.png",
                    isSelected: selectedNetwork == "Polygon",
                    onTap: () {
                      setState(() => selectedNetwork = "Polygon");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Solana",
                    icon: "assets/images/sol.png",
                    isSelected: selectedNetwork == "Solana",
                    onTap: () {
                      setState(() => selectedNetwork = "Solana");
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea( // این خط اضافه شود
          child: RefreshIndicator(
            onRefresh: _refreshTransactions,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Text(
                          "History",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Filter
                  GestureDetector(
                    onTap: _showNetworkFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            selectedNetwork,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.black,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Content
                  Expanded(
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF11c699),
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Text(
          "Error: $errorMessage",
          style: const TextStyle(color: Colors.red, fontSize: 16),
        ),
      );
    }

    final groupedTransactions = _groupTransactionsByDate();

    if (groupedTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/notransaction.png',
              width: 180,
              height: 180,
              color: Colors.grey.withOpacity(0.9),
            ),
            const SizedBox(height: 16),
            const Text(
              "No transactions found",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: groupedTransactions.length + 1, // +1 for the explorer footer
      itemBuilder: (context, index) {
        if (index == groupedTransactions.length) {
          // Explorer footer
          return Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0F1BCAA0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Cannot find your transaction? ",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                GestureDetector(
                  onTap: () {
                    // TODO: Implement explorer functionality
                  },
                  child: const Text(
                    "Check explorer",
                    style: TextStyle(
                      color: Color(0xFF11c699),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final date = groupedTransactions.keys.elementAt(index);
        final transactionsForDate = groupedTransactions[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                date,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            ...transactionsForDate.map((transaction) => _TransactionItem(
              transaction: transaction,
              onTap: () {
                // TODO: Navigate to transaction details
                final isReceived = transaction.direction == "inbound";
                final direction = isReceived ? "From: " : "To: ";
                final address = isReceived ? transaction.from : transaction.to;
                final shortAddress = address.length > 15
                    ? "${address.substring(0, 10)}...${address.substring(address.length - 5)}"
                    : address;
                
                final amountPrefix = isReceived ? "+" : "-";
                final formattedAmount = _formatAmount(transaction.amount);
                final amountValue = "$amountPrefix$formattedAmount";
                
                final fiatValue = transaction.price != null
                    ? "≈ \$${transaction.price!.toStringAsFixed(2)}"
                    : "≈ \$0.00";

                // Navigate to transaction detail screen
                Navigator.pushNamed(
                  context,
                  '/transaction-detail',
                  arguments: {
                    'amount': amountValue,
                    'symbol': transaction.tokenSymbol,
                    'fiat': fiatValue,
                    'address': "$direction$shortAddress",
                    'status': transaction.status,
                    'hash': transaction.txHash,
                  },
                );
              },
            )).toList(),
          ],
        );
      },
    );
  }
}

class _NetworkOption extends StatelessWidget {
  final String name;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NetworkOption({
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 24,
              height: 24,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.account_balance_wallet,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              name,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _TransactionItem({
    required this.transaction,
    required this.onTap,
  });

  String _formatAmount(String amount) {
    try {
      final number = double.parse(amount);
      final formatted = number.toStringAsFixed(6).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
      return formatted;
    } catch (e) {
      return amount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = transaction.direction == "inbound";
    final direction = isReceived ? "From: " : "To: ";
    final address = isReceived ? transaction.from : transaction.to;
    final shortAddress = address.length > 15
        ? "${address.substring(0, 10)}...${address.substring(address.length - 5)}"
        : address;
    
    final amountPrefix = isReceived ? "+" : "-";
    final formattedAmount = _formatAmount(transaction.amount);
    final amountValue = "$amountPrefix$formattedAmount";
    
    final fiatValue = transaction.price != null
        ? "≈ \$${transaction.price!.toStringAsFixed(2)}"
        : "≈ \$0.00";

    final isPending = !isReceived && transaction.status.toLowerCase() == "pending";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isReceived
                    ? const Color(0xFF20CDA4).withOpacity(0.1)
                    : const Color(0xFFF43672).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
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
                    : Icon(
                        isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isReceived ? const Color(0xFF20CDA4) : const Color(0xFFF43672),
                        size: 16,
                      ),
              ),
            ),

            const SizedBox(width: 10),

            // Transaction details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isReceived ? "Receive" : "Send",
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9A825),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "pending",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    "$direction$shortAddress",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text(
                      amountValue,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: amountValue.startsWith("-")
                            ? const Color(0xFFF43672)
                            : const Color(0xFF11c699),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      transaction.tokenSymbol,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                Text(
                  fiatValue,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 