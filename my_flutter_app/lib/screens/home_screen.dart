import 'package:flutter/material.dart';
import '../layout/main_layout.dart';
import 'crypto_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String walletName = 'My Wallet';
  bool isHidden = false;
  int selectedTab = 0;
  List<String> walletsList = ['My Wallet', 'Test Wallet', 'Demo Wallet'];
  List<Map<String, dynamic>> tokens = [
    {
      'name': 'Bitcoin',
      'symbol': 'BTC',
      'icon': 'assets/images/btc.png',
      'amount': 0.1234,
      'price': 65000.0,
      'change': '+2.5%',
    },
    {
      'name': 'Ethereum',
      'symbol': 'ETH',
      'icon': 'assets/images/ethereum_logo.png',
      'amount': 1.5,
      'price': 3200.0,
      'change': '-1.2%',
    },
    {
      'name': 'Tether',
      'symbol': 'USDT',
      'icon': 'assets/images/binance_logo.png',
      'amount': 1000.0,
      'price': 1.0,
      'change': '+0.0%',
    },
  ];

  @override
  void initState() {
    super.initState();
  }

  void _showWalletModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 16),
            ...walletsList.map((w) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(w, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: Image.asset('assets/images/rightarrow.png', width: 18, height: 18),
                    onTap: () {
                      setState(() { walletName = w; });
                      Navigator.pop(context);
                    },
                  ),
                )),
            const SizedBox(height: 20),
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
        body: SafeArea(
          child: Column(
            children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left icons
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(context, '/add-token');
                              },
                              child: Image.asset('assets/images/music.png', width: 18, height: 18),
                            ),
                            const SizedBox(width: 12),
                            // اگر آیکون دیگری نیاز بود اضافه کن
                          ],
                        ),
                        // Center wallet name and visibility
                        GestureDetector(
                          onTap: _showWalletModal,
                          child: Row(
                            children: [
                              Text(
                                walletName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => setState(() => isHidden = !isHidden),
                                child: Icon(
                                  isHidden ? Icons.visibility_off : Icons.visibility,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right icon
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/add-token');
                          },
                          child: Image.asset('assets/images/search.png', width: 18, height: 18),
                        ),
                      ],
                    ),
                  ),
                  // User profile section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          isHidden ? '****' : '21,000.00',
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_upward,
                              size: 12,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isHidden ? '**** +2.5%' : '+2.5%',
                              style: const TextStyle(fontSize: 16, color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionButton(
                          icon: 'assets/images/send.png',
                          label: 'Send',
                          onTap: () {},
                          bgColor: const Color(0x80D7FBE7),
                        ),
                        _ActionButton(
                          icon: 'assets/images/receive.png',
                          label: 'Receive',
                          onTap: () {
                            Navigator.pushNamed(context, '/receive');
                          },
                          bgColor: const Color(0x80D7F0F1),
                        ),
                        _ActionButton(
                          icon: 'assets/images/history.png',
                          label: 'History',
                          onTap: () {
                            Navigator.pushNamed(context, '/history');
                          },
                          bgColor: const Color(0x80D6E8FF),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tabs
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _TabButton(
                          label: 'Cryptos',
                          selected: selectedTab == 0,
                          onTap: () => setState(() => selectedTab = 0),
                        ),
                        _TabButton(
                          label: "NFT's",
                          selected: selectedTab == 1,
                          onTap: () => setState(() => selectedTab = 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Token list or NFT
                  Expanded(
                    child: selectedTab == 0
                        ? ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                            itemCount: tokens.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final token = tokens[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CryptoDetailsScreen(
                                        tokenName: token['name'],
                                        tokenSymbol: token['symbol'],
                                        iconUrl: token['icon'],
                                        isToken: true, // فرض بر این که همه توکن هستند، در صورت نیاز مقداردهی دقیق‌تر
                                        blockchainName: '', // اگر بلاک‌چین داری اضافه کن
                                        gasFee: 0.0, // اگر کارمزد داری اضافه کن
                                      ),
                                    ),
                                  );
                                },
                                child: _TokenRow(
                                  name: token['name'],
                                  symbol: token['symbol'],
                                  icon: token['icon'],
                                  amount: token['amount'],
                                  price: token['price'],
                                  change: token['change'],
                                  isHidden: isHidden,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset('assets/images/card.png', width: 90, height: 90, color: Colors.grey.withOpacity(0.2)),
                                const SizedBox(height: 8),
                                const Text('No NFT Found', style: TextStyle(color: Color(0x7E666666), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final Color bgColor;
  const _ActionButton({required this.icon, required this.label, required this.onTap, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Center(child: Image.asset(icon, width: 24, height: 24)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFF11c699) : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? const Color(0xFF11c699) : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  final String name;
  final String symbol;
  final String icon;
  final double amount;
  final double price;
  final String change;
  final bool isHidden;
  const _TokenRow({required this.name, required this.symbol, required this.icon, required this.amount, required this.price, required this.change, required this.isHidden});

  @override
  Widget build(BuildContext context) {
    final dollarValue = price * amount;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE7FAEF), Color(0xFFE7F0FB)]),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          Image.asset(icon, width: 30, height: 30, errorBuilder: (c, e, s) => const Icon(Icons.account_balance_wallet)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('($symbol)', style: const TextStyle(fontSize: 12, color: Color(0xff2b2b2b))),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(' 2${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Text(change, style: TextStyle(fontSize: 14, color: change.startsWith('-') ? Colors.red : Colors.green)),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isHidden ? '****' : amount.toStringAsFixed(4), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(isHidden ? '****' : ' 2${dollarValue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
} 