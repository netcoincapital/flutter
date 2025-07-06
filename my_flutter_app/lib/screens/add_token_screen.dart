import 'package:flutter/material.dart';
import '../layout/main_layout.dart';

class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({Key? key}) : super(key: key);

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  String searchText = '';
  String selectedNetwork = 'All Blockchains';
  bool isLoading = false;
  bool refreshing = false;
  String? errorMessage;
  List<Map<String, dynamic>> tokens = [];
  final List<Map<String, dynamic>> blockchains = [
    {'name': 'All Blockchains', 'icon': 'assets/images/all.png'},
    {'name': 'Bitcoin', 'icon': 'assets/images/btc.png'},
    {'name': 'Ethereum', 'icon': 'assets/images/ethereum_logo.png'},
    {'name': 'Binance Smart Chain', 'icon': 'assets/images/binance_logo.png'},
    {'name': 'Polygon', 'icon': 'assets/images/pol.png'},
    {'name': 'Tron', 'icon': 'assets/images/tron.png'},
    {'name': 'Arbitrum', 'icon': 'assets/images/arb.png'},
    {'name': 'XRP', 'icon': 'assets/images/xrp.png'},
    {'name': 'Avalanche', 'icon': 'assets/images/avax.png'},
    {'name': 'Polkadot', 'icon': 'assets/images/dot.png'},
    {'name': 'Solana', 'icon': 'assets/images/sol.png'},
  ];
  
  bool showNetworkModal = false;

  Future<void> _refreshTokens() async {
    setState(() => refreshing = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => refreshing = false);
  }

  void _showNetworkModal() {
    setState(() {
      showNetworkModal = true;
    });
  }

  void _hideNetworkModal() {
    setState(() {
      showNetworkModal = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const Text('Manage Tokens', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              iconTheme: const IconThemeData(color: Colors.black),
            ),
            body: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _refreshTokens,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: [
                      const SizedBox(height: 16),
                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0x25757575),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (val) => setState(() => searchText = val),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Network filter
                      GestureDetector(
                        onTap: _showNetworkModal,
                        child: Container(
                          width: 200,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0x25757575),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Text(selectedNetwork, style: const TextStyle(fontSize: 16, color: Color(0xFF2c2c2c))),
                              const Spacer(),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Cryptos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xCB838383))),
                      const SizedBox(height: 8),
                      // Token list (empty)
                      if (tokens.isEmpty && errorMessage == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('No tokens available', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          ),
                        ),
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('Error: $errorMessage', style: const TextStyle(color: Colors.red, fontSize: 16)),
                          ),
                        ),
                      // اگر توکن بود، اینجا لیستشون رو نمایش بده
                      // ...
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
                if (isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
          if (showNetworkModal)
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideNetworkModal,
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                ),
              ),
            ),
          if (showNetworkModal)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select Blockchain',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 320, // ارتفاع کمتر برای جلوگیری از رفتن زیر منو
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: blockchains.length,
                        itemBuilder: (context, index) {
                          final bc = blockchains[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() => selectedNetwork = bc['name']!);
                              _hideNetworkModal();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                              child: Row(
                                children: [
                                  Image.asset(bc['icon']!, width: 24, height: 24, errorBuilder: (c, e, s) => const Icon(Icons.blur_on)),
                                  const SizedBox(width: 12),
                                  Text(
                                    bc['name']!,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF2c2c2c),
                                      fontWeight: FontWeight.normal,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Custom Switch Widget (UI only, no logic)
class CustomSwitch extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;
  const CustomSwitch({required this.checked, required this.onChanged, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: checked ? const Color(0xFF27B6AC) : Colors.grey,
        ),
        child: Align(
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
} 