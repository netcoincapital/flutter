import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:my_flutter_app/screens/receive_wallet_screen.dart'; // Added import for ReceiveWalletScreen

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({Key? key}) : super(key: key);

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  String searchText = '';
  String selectedNetwork = 'All Blockchains';
  bool isLoading = true;
  List<Map<String, dynamic>> tokens = [];
  Map<String, String> addressCache = {};

  final List<Map<String, dynamic>> allTokens = [
    {
      'name': 'Bitcoin',
      'symbol': 'BTC',
      'blockchain': 'Bitcoin',
      'icon': 'assets/images/btc.png',
      'address': 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
    },
    {
      'name': 'Ethereum',
      'symbol': 'ETH',
      'blockchain': 'Ethereum',
      'icon': 'assets/images/ethereum_logo.png',
      'address': '0x742d35Cc6Afa4C532c6c5d9e79f4d4C2b9C0b0c7',
    },
    {
      'name': 'Tether',
      'symbol': 'USDT',
      'blockchain': 'Binance Smart Chain',
      'icon': 'assets/images/binance_logo.png',
      'address': '0x742d35Cc6Afa4C532c6c5d9e79f4d4C2b9C0b0c7',
    },
    {
      'name': 'Tron',
      'symbol': 'TRX',
      'blockchain': 'Tron',
      'icon': 'assets/images/tron.png',
      'address': 'TRX9aAqoDxtDFhNqDiXU7MH3ULMa2ZfCDC',
    },
    {
      'name': 'Polygon',
      'symbol': 'MATIC',
      'blockchain': 'Polygon',
      'icon': 'assets/images/pol.png',
      'address': '0x742d35Cc6Afa4C532c6c5d9e79f4d4C2b9C0b0c7',
    },
  ];

  final List<String> blockchains = [
    'All Blockchains',
    'Bitcoin',
    'Ethereum',
    'Binance Smart Chain',
    'Polygon',
    'Tron',
  ];

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  void _loadTokens() async {
    // در نسخه واقعی، اینجا باید از API یا کش بخوانی
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      tokens = allTokens;
      isLoading = false;
    });
  }

  List<Map<String, dynamic>> get filteredTokens {
    return tokens.where((token) {
      final matchesSearch = searchText.isEmpty ||
          token['symbol'].toString().toLowerCase().contains(searchText.toLowerCase()) ||
          token['name'].toString().toLowerCase().contains(searchText.toLowerCase());
      final matchesNetwork = selectedNetwork == 'All Blockchains' || token['blockchain'] == selectedNetwork;
      return matchesSearch && matchesNetwork;
    }).toList();
  }

  void _showNetworkSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Select Blockchain', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: blockchains.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final bc = blockchains[index];
                    final isSelected = selectedNetwork == bc;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => selectedNetwork = bc);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0x1A1AC89E) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _blockchainIcon(bc),
                            const SizedBox(width: 14),
                            Text(bc, style: const TextStyle(fontSize: 16, color: Colors.black)),
                            if (isSelected) ...[
                              const Spacer(),
                              const Icon(Icons.check, color: Color(0xFF08C495)),
                            ],
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
      },
    );
  }

  Widget _blockchainIcon(String bc) {
    switch (bc) {
      case 'Bitcoin':
        return Image.asset('assets/images/btc.png', width: 24, height: 24);
      case 'Ethereum':
        return Image.asset('assets/images/ethereum_logo.png', width: 24, height: 24);
      case 'Binance Smart Chain':
        return Image.asset('assets/images/binance_logo.png', width: 24, height: 24);
      case 'Polygon':
        return Image.asset('assets/images/pol.png', width: 24, height: 24);
      case 'Tron':
        return Image.asset('assets/images/tron.png', width: 24, height: 24);
      default:
        return Image.asset('assets/images/all.png', width: 24, height: 24);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Receive Token', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0x25757575),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (val) => setState(() => searchText = val),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _showNetworkSelector,
                    child: Container(
                      width: 200,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0x25757575),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              selectedNetwork == 'All Blockchains' ? 'Select Network' : selectedNetwork,
                              style: const TextStyle(fontSize: 16, color: Color(0xFF2c2c2c)),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 20),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredTokens.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final token = filteredTokens[index];
                        final address = token['address'] ?? '';
                        void openReceiveWallet() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiveWalletScreen(
                                cryptoName: token['name'],
                                blockchainName: token['blockchain'],
                                address: address,
                                symbol: token['symbol'],
                              ),
                            ),
                          );
                        }
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: openReceiveWallet,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            child: Row(
                              children: [
                                Image.asset(token['icon'], width: 30, height: 30),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(token['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          const SizedBox(width: 4),
                                          Text('(${token['symbol']})', style: const TextStyle(fontSize: 12, color: Color(0xff2b2b2b))),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        address.length > 16 ? '${address.substring(0, 8)}...${address.substring(address.length - 5)}' : address,
                                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.qr_code, color: Colors.grey),
                                  onPressed: openReceiveWallet,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.grey),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: address));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wallet address copied')));
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
} 