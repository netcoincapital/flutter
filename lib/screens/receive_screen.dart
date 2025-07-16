import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:my_flutter_app/screens/receive_wallet_screen.dart'; // Added import for ReceiveWalletScreen
import 'package:http/http.dart' as http;
import '../services/secure_storage.dart';
import '../providers/price_provider.dart';
import '../utils/shared_preferences_utils.dart';

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
  String? userId;
  List<String> blockchains = ['All Blockchains'];

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
    _initUserAndLoadTokens();
  }

  Future<void> _initUserAndLoadTokens() async {
    setState(() => isLoading = true);
    
    // بارگذاری کیف پول انتخاب شده (مطابق با Kotlin)
    final selectedWallet = await SecureStorage.instance.getSelectedWallet();
    final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
    
    if (selectedWallet != null && selectedUserId != null) {
      userId = selectedUserId;
      print('💰 Receive Screen - Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
    } else {
      // Fallback: try to get from first available wallet
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        final firstWallet = wallets.first;
        userId = firstWallet['userID'];
        print('⚠️ No selected wallet found, using first available wallet: ${firstWallet['walletName']}');
      }
    }
    
    print('UserID: ' + (userId ?? 'NULL'));
    
    await _fetchTokensAndAddresses();
  }

  // --- کش لیست توکن‌ها (کریپتوها) ---
  Future<List<Map<String, dynamic>>> _loadTokensFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('crypto_tokens_cache');
    if (jsonStr == null) return [];
    final List<dynamic> list = jsonDecode(jsonStr);
    return List<Map<String, dynamic>>.from(list);
  }

  Future<void> _saveTokensToCache(List<Map<String, dynamic>> tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('crypto_tokens_cache', jsonEncode(tokens));
  }

  // --- کش آدرس‌های هر والت ---
  Future<Map<String, String>> _loadAddressesFromCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('wallet_addresses_cache_$userId');
    if (jsonStr == null) return {};
    final Map<String, dynamic> map = jsonDecode(jsonStr);
    return Map<String, String>.from(map);
  }

  Future<void> _saveAddressesToCache(String userId, Map<String, String> addresses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallet_addresses_cache_$userId', jsonEncode(addresses));
  }

  Future<void> _fetchTokensAndAddresses() async {
    setState(() => isLoading = true);
    // 1. لیست توکن‌ها را از کش بخوان
    List<Map<String, dynamic>> tokensList = await _loadTokensFromCache();
    if (tokensList.isEmpty) {
      // اگر کش نبود، از سرور بگیر و کش کن
      final response = await http.get(Uri.parse('https://coinceeper.com/api/all-currencies'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> currencies = data['currencies'] ?? [];
        tokensList = currencies.map((e) => Map<String, dynamic>.from(e)).toList();
        await _saveTokensToCache(tokensList);
      }
    }
    // 2. آدرس‌های این والت را از کش بخوان
    Map<String, String> addresses = await _loadAddressesFromCache(userId ?? '');
    // اگر کش نبود، از سرور بگیر و کش کن
    if (addresses.isEmpty && userId != null) {
      final List<String> blockchainNames = tokensList.map((t) => (t['BlockchainName'] ?? '').toString()).toSet().toList();
      for (final blockchain in blockchainNames) {
        final reciveResponse = await http.post(
          Uri.parse('https://coinceeper.com/api/Recive'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'UserID': userId,
            'BlockchainName': blockchain,
          }),
        );
        if (reciveResponse.statusCode == 200) {
          final reciveData = jsonDecode(reciveResponse.body);
          if (reciveData['success'] == true && reciveData['PublicAddress'] != null) {
            addresses[blockchain] = reciveData['PublicAddress'];
          }
        }
      }
      await _saveAddressesToCache(userId!, addresses);
    }
    // 3. مپ کردن توکن‌ها و آدرس‌ها برای نمایش
    List<Map<String, dynamic>> updatedTokens = [];
    Set<String> blockchainSet = {};
    for (final token in tokensList) {
      final blockchain = token['BlockchainName'] ?? '';
      blockchainSet.add(blockchain);
      final address = addresses[blockchain] ?? '';
      updatedTokens.add({
        'name': token['CurrencyName'] ?? '',
        'symbol': token['Symbol'] ?? '',
        'blockchain': blockchain,
        'icon': token['Icon'] ?? '',
        'address': address,
      });
    }
    setState(() {
      tokens = updatedTokens;
      blockchains = ['All Blockchains', ...blockchainSet];
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

  void _showTokenSelector() {
    // Remove modal bottom sheet - token selector removed
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
      case 'Arbitrum':
        return Image.asset('assets/images/arb.png', width: 24, height: 24);
      case 'XRP':
        return Image.asset('assets/images/xrp.png', width: 24, height: 24);
      case 'Avalanche':
        return Image.asset('assets/images/avax.png', width: 24, height: 24);
      case 'Polkadot':
        return Image.asset('assets/images/dot.png', width: 24, height: 24);
      case 'Solana':
        return Image.asset('assets/images/sol.png', width: 24, height: 24);
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
        title: Text(_safeTranslate('receive_token', 'Receive Token'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                      hintText: _safeTranslate('search', 'Search'),
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
                    onTap: _showTokenSelector,
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
                              selectedNetwork == 'All Blockchains' ? _safeTranslate('select_network', 'Select Network') : selectedNetwork,
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
                                Image.network(
                                  token['icon'],
                                  width: 30,
                                  height: 30,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${token['name']} (${token['symbol']})',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              address.length > 16 ? '${address.substring(0, 8)}...${address.substring(address.length - 5)}' : address,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                                            ),
                                          ),
                                        ],
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
                                    // Remove success message - copied silently
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