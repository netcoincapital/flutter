import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'dart:convert';
import '../providers/token_provider.dart';
import '../providers/price_provider.dart';
import '../models/crypto_token.dart';
import '../models/balance_item.dart' as models;
import '../services/secure_storage.dart';
import '../services/api_service.dart';
import '../utils/shared_preferences_utils.dart';
import '../layout/main_layout.dart';
import '../layout/loading_overlay.dart';


class SendScreen extends StatefulWidget {
  final Map<String, dynamic>? qrArguments;
  
  const SendScreen({
    super.key,
    this.qrArguments,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  String searchText = '';
  String selectedNetwork = 'All';
  List<CryptoToken> tokens = [];
  List<models.BalanceItem> balanceItems = [];
  String? userId;
  String? walletName;
  Timer? _priceRefreshTimer;
  String selectedCurrency = 'USD';
  String currencySymbol = '\$';

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
    print('🚀 Send Screen initState started');
    _loadSelectedWallet().then((_) {
      print('🔄 Wallet loaded, now loading currency...');
      return _loadSelectedCurrency();
    }).then((_) {
      print('🔄 Currency loaded, now fetching balance...');
      return _fetchBalanceDirectly();
    }).then((_) {
      print('🔄 Balance fetched, processing QR arguments...');
      _processQRArguments();
      print('🔄 Setting up auto refresh...');
      _setupAutoRefreshPrices();
      print('✅ Send Screen initialization completed');
    }).catchError((error) {
      print('❌ Error during Send Screen initialization: $error');
    });
  }

  @override
  void dispose() {
    _priceRefreshTimer?.cancel();
    super.dispose();
  }

  /// بارگذاری کیف پول انتخاب شده (مطابق با Kotlin)
  Future<void> _loadSelectedWallet() async {
    print('🔍 Starting _loadSelectedWallet...');
    try {
      print('🔍 Getting selected wallet from SecureStorage...');
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      final selectedUserId = await SecureStorage.instance.getUserIdForSelectedWallet();
      
      print('📋 SecureStorage results:');
      print('   Selected wallet: $selectedWallet');
      print('   Selected userId: $selectedUserId');
      
      if (selectedWallet != null && selectedUserId != null) {
        setState(() {
          walletName = selectedWallet;
          userId = selectedUserId;
        });
        print('✅ Send Screen - Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
      } else {
        print('⚠️ No selected wallet found, trying first available wallet...');
        // Fallback: use first available wallet
        final wallets = await SecureStorage.instance.getWalletsList();
        print('📋 Available wallets count: ${wallets.length}');
        
        if (wallets.isNotEmpty) {
          final firstWallet = wallets.first;
          print('📋 First wallet data: $firstWallet');
          
          final walletName = firstWallet['walletName'] ?? firstWallet['name'];
          final walletUserId = firstWallet['userID'] ?? firstWallet['userId'];
          
          print('📋 Extracted from first wallet:');
          print('   Wallet name: $walletName');
          print('   User ID: $walletUserId');
          
          setState(() {
            this.walletName = walletName;
            userId = walletUserId;
          });
          print('✅ Using first available wallet: $walletName with userId: $walletUserId');
        } else {
          print('❌ No wallets found at all!');
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error loading selected wallet: $e');
      print('❌ Stack trace: $stackTrace');
    }
    print('🏁 _loadSelectedWallet completed. Final userId: $userId, walletName: $walletName');
  }

  /// بارگذاری ارز انتخابی (مطابق با Kotlin)
  Future<void> _loadSelectedCurrency() async {
    try {
      final currency = await SharedPreferencesUtils.getSelectedCurrency();
      final symbol = SharedPreferencesUtils.getCurrencySymbol(currency);
      
      setState(() {
        selectedCurrency = currency;
        currencySymbol = symbol;
      });
      
      print('💰 Send Screen - Loaded selected currency: $currency with symbol: $symbol');
    } catch (e) {
      print('❌ Error loading selected currency: $e');
    }
  }

  /// راه‌اندازی تازه‌سازی خودکار قیمت‌ها (مطابق با Kotlin)
  void _setupAutoRefreshPrices() {
    _priceRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!isLoading && !isRefreshing && tokens.isNotEmpty) {
        _refreshPricesOnly();
      }
    });
  }

  /// تازه‌سازی فقط قیمت‌ها (مطابق با Kotlin)
  Future<void> _refreshPricesOnly() async {
    try {
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      final symbols = tokens.map((t) => t.symbol == null ? '' : t.symbol!).where((s) => s.isNotEmpty).toList();
      
      if (symbols.isNotEmpty) {
        final currencies = [selectedCurrency];
        await priceProvider.fetchPrices(symbols, currencies: currencies);
        print('🔄 Auto-refreshed prices for symbols: $symbols');
      }
    } catch (e) {
      print('❌ Error auto-refreshing prices: $e');
    }
  }

  void _processQRArguments() {
    if (widget.qrArguments != null) {
      final address = widget.qrArguments!['address'];
      final paymentUrl = widget.qrArguments!['paymentUrl'];
      final tokenTransfer = widget.qrArguments!['tokenTransfer'];
      final text = widget.qrArguments!['text'];
      
      if (address != null) {
        print('📍 QR Address detected: $address');
      } else if (paymentUrl != null) {
        print('💰 QR Payment URL detected: $paymentUrl');
      } else if (tokenTransfer != null) {
        print('🪙 QR Token transfer detected: $tokenTransfer');
      } else if (text != null) {
        print('📝 QR Text detected: $text');
      }
    }
  }

  /// دریافت موجودی مستقیم از API (مطابق با Kotlin send_screen.kt)
  Future<void> _fetchBalanceDirectly() async {
    print('🔍 Starting _fetchBalanceDirectly...');
    print('🔍 Current userId: $userId');
    print('🔍 Current walletName: $walletName');
    print('🔍 userId?.isEmpty: ${userId?.isEmpty}');
    print('🔍 userId == null: ${userId == null}');
    
    try {
      if (userId == null || userId!.isEmpty) {
        print('❌ UserId is null or empty, cannot fetch balance');
        print('❌ Available walletName: $walletName');
        
        // Try to reload wallet info
        print('🔄 Attempting to reload wallet info...');
        await _loadSelectedWallet();
        
        if (userId == null || userId!.isEmpty) {
          print('❌ Still no userId after reload, showing error');
          setState(() {
            isLoading = false;
            isRefreshing = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_safeTranslate('no_wallet_selected', 'No wallet selected. Please select a wallet first.')),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      print('✅ UserId validation passed, proceeding with API call');
      
      setState(() {
        isLoading = true;
      });

      print('🔄 Fetching balance for userId: $userId');
      print('🔄 Wallet name: $walletName');
      
      final apiService = ApiService();
      final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // دریافت لیست توکن‌های موجود
      final availableTokens = tokenProvider.currencies;
      print('📋 Available tokens count: ${availableTokens.length}');
      
      // استفاده از getBalance API مطابق با Kotlin send_screen.kt (همه موجودی‌ها)
      print('💰 Calling getBalance API (matching Kotlin send_screen.kt)...');
      print('📤 Request - UserID: $userId');
      print('📤 Request - CurrencyNames: [] (empty list to get all balances)');
      print('📤 Request - Blockchain: {} (empty map)');
      
      final response = await apiService.getBalance(
        userId!,
        currencyNames: [], // خالی برای دریافت همه موجودی‌ها مانند Kotlin
        blockchain: {},
      );
      
      print('📥 API Response received:');
      print('   Success: ${response.success}');
      print('   UserID: ${response.userID}');
      print('   Balances count: ${response.balances?.length ?? 0}');
      
      if (response.success && response.balances != null && response.balances!.isNotEmpty) {
        print('✅ getBalance API response successful');
        print('📊 Processing ${response.balances!.length} balance items...');
        
        final newTokens = <CryptoToken>[];
        final newBalanceItems = <models.BalanceItem>[];
        int processedBalances = 0;
        int tokensWithBalance = 0;
        
        // فیلتر کردن موجودی‌های مثبت مطابق با Kotlin
        for (final balanceItem in response.balances!) {
          processedBalances++;
          final balance = double.tryParse(balanceItem.balance ?? '0') ?? 0.0;
          
          print('🔍 Processing balance $processedBalances: ${balanceItem.symbol ?? 'Unknown'} = ${balanceItem.balance ?? '0'} (parsed: $balance)');
          
          // فقط موجودی‌های مثبت مانند Kotlin send_screen.kt
          if (balance > 0.0 && balanceItem.symbol != null) {
            tokensWithBalance++;
            print('   ✅ Token has positive balance: ${balanceItem.symbol} = $balance');
            
            // پیدا کردن توکن مطابق در لیست موجود
            final matchingToken = availableTokens.firstWhere(
              (token) => token.symbol == balanceItem.symbol,
              orElse: () {
                print('   📝 Creating new token for: ${balanceItem.symbol}');
                return CryptoToken(
                  name: balanceItem.currencyName ?? balanceItem.symbol ?? 'Unknown',
                  symbol: balanceItem.symbol ?? 'Unknown',
                  blockchainName: balanceItem.blockchain ?? 'Unknown',
                  iconUrl: 'https://coinceeper.com/defualtIcons/coin.png',
                  isEnabled: true,
                  amount: 0.0,
                  isToken: balanceItem.isToken ?? true,
                );
              },
            );

            print('   🔗 Token blockchain: ${balanceItem.blockchain ?? 'Unknown'}');

            final cryptoToken = matchingToken.copyWith(
              amount: balance,
              blockchainName: balanceItem.blockchain ?? 'Unknown',
              isToken: balanceItem.isToken ?? true,
            );
            
            newTokens.add(cryptoToken);
            print('   ➕ Added token to list: ${cryptoToken.symbol} = ${cryptoToken.amount}');
            
            // ایجاد BalanceItem برای سازگاری
            newBalanceItems.add(models.BalanceItem(
              symbol: balanceItem.symbol ?? 'Unknown',
              balance: balanceItem.balance ?? '0',
              blockchain: balanceItem.blockchain ?? 'Unknown',
            ));
          } else {
            print('   ⏭️ Token has zero balance: ${balanceItem.symbol ?? 'Unknown'} = $balance');
          }
        }

        print('📊 Processing complete:');
        print('   Total balance items processed: $processedBalances');
        print('   Tokens with positive balance: $tokensWithBalance');
        print('   Final newTokens count: ${newTokens.length}');
        print('   Final newBalanceItems count: ${newBalanceItems.length}');

        setState(() {
          balanceItems = newBalanceItems;
          tokens = newTokens;
        });

        print('✅ State updated with ${newTokens.length} tokens');

        // دریافت قیمت‌ها برای توکن‌هایی که موجودی دارند
        if (newTokens.isNotEmpty) {
          final symbols = newTokens.map((t) => t.symbol == null ? '' : t.symbol!).where((s) => s.isNotEmpty).toList();
          final currencies = [selectedCurrency];
          
          print('🔄 Fetching prices for symbols: $symbols');
          await priceProvider.fetchPrices(symbols, currencies: currencies);
        } else {
          print('⚠️ No tokens with balance found, skipping price fetch');
        }
        
        print('✅ Successfully loaded ${newTokens.length} tokens with positive balance');
      } else {
        print('❌ getBalance API failed or returned no data');
        print('   Success: ${response.success}');
        print('   Balances empty: ${response.balances?.isEmpty ?? true}');
        print('   Response: $response');
        
        setState(() {
          tokens = [];
          balanceItems = [];
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_safeTranslate('no_balance_data', 'No balance data received from server')),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error fetching balance: $e');
      print('❌ Stack trace: $stackTrace');
      
      setState(() {
        tokens = [];
        balanceItems = [];
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('error_loading_balances', 'Error loading balances: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
        isRefreshing = false;
      });
      print('🏁 _fetchBalanceDirectly completed');
    }
  }

  /// تازه‌سازی توکن‌ها (مطابق با Kotlin)
  Future<void> _refreshTokens() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('loading', 'Loading...')), duration: const Duration(seconds: 1)),
      );
    }
    
    setState(() {
      isRefreshing = true;
    });
    
    await _fetchBalanceDirectly();
  }

  /// دریافت قیمت امن برای توکن (مطابق با Kotlin getSafeTokenPrice)
  double getSafeTokenPrice(String tokenSymbol) {
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    // تلاش برای دریافت قیمت استاندارد
    final standardPrice = priceProvider.getPriceForCurrency(tokenSymbol, selectedCurrency);
    
    if (standardPrice != null && standardPrice > 0.0) {
      return standardPrice;
    }
    
    // تلاش با تغییرات نام توکن
    final variations = [
      tokenSymbol.toLowerCase(),
      tokenSymbol.toUpperCase(),
      _getTokenAlternativeName(tokenSymbol),
    ].where((name) => name != null).cast<String>().toList();
    
    for (final symbol in variations) {
      final price = priceProvider.getPriceForCurrency(symbol, selectedCurrency);
      if (price != null && price > 0.0) {
        return price;
      }
    }
    
    return 0.0; // برگرداندن 0.0 که باعث نمایش "Fetching price..." می‌شود
  }

  /// دریافت نام جایگزین برای توکن (مطابق با Kotlin)
  String? _getTokenAlternativeName(String tokenSymbol) {
    final alternatives = {
      'TRX': 'tron',
      'BNB': 'binance',
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'SHIB': 'shiba inu',
      'USDT': 'tether',
      'USDC': 'usd coin',
      'BUSD': 'binance usd',
      'ADA': 'cardano',
      'DOT': 'polkadot',
      'AVAX': 'avalanche',
      'MATIC': 'polygon',
      'UNI': 'uniswap',
      'LINK': 'chainlink',
    };
    
    return alternatives[tokenSymbol.toUpperCase()];
  }

  /// فرمت کردن مقدار (مطابق با Kotlin formatAmount)
  String formatAmount(double amount, double price) {
    if (amount == 0.0) return '0.00';
    
    if (price > 0.0) {
      // اگر قیمت موجود است، بر اساس ارزش دلاری فرمت کن
      final dollarValue = amount * price;
      if (dollarValue >= 1000000) {
        return '${(amount / 1000000).toStringAsFixed(2)}M';
      } else if (dollarValue >= 1000) {
        return '${(amount / 1000).toStringAsFixed(2)}K';
      } else if (amount >= 1) {
        return amount.toStringAsFixed(2);
      } else {
        return amount.toStringAsFixed(6);
      }
    } else {
      // اگر قیمت موجود نیست، بر اساس مقدار توکن فرمت کن
      if (amount >= 1000000) {
        return '${(amount / 1000000).toStringAsFixed(2)}M';
      } else if (amount >= 1000) {
        return '${(amount / 1000).toStringAsFixed(2)}K';
      } else if (amount >= 1) {
        return amount.toStringAsFixed(2);
      } else {
        return amount.toStringAsFixed(6);
      }
    }
  }

  /// محاسبه ارزش دلاری (مطابق با Kotlin)
  String calculateDollarValue(double amount, double price) {
    if (price <= 0.0) return _safeTranslate('fetching_price', 'Fetching price...');
    
    final dollarValue = amount * price;
    if (dollarValue >= 1000000) {
      return '$currencySymbol${(dollarValue / 1000000).toStringAsFixed(2)}M';
    } else if (dollarValue >= 1000) {
      return '$currencySymbol${(dollarValue / 1000).toStringAsFixed(2)}K';
    } else {
      return '$currencySymbol${dollarValue.toStringAsFixed(2)}';
    }
  }

  /// نمایش modal برای انتخاب شبکه (مطابق با سایر صفحات)
  void _showNetworkFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            Text(
              _safeTranslate('select_network', 'Select Network'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _NetworkOption(
                    name: _safeTranslate('all', 'All'),
                    icon: "assets/images/all.png",
                    isSelected: selectedNetwork == "All",
                    onTap: () {
                      setState(() => selectedNetwork = "All");
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
                    name: "Binance Smart Chain",
                    icon: "assets/images/binance_logo.png",
                    isSelected: selectedNetwork == "Binance Smart Chain",
                    onTap: () {
                      setState(() => selectedNetwork = "Binance Smart Chain");
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
                    name: "Tron",
                    icon: "assets/images/tron.png",
                    isSelected: selectedNetwork == "Tron",
                    onTap: () {
                      setState(() => selectedNetwork = "Tron");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Arbitrum",
                    icon: "assets/images/arb.png",
                    isSelected: selectedNetwork == "Arbitrum",
                    onTap: () {
                      setState(() => selectedNetwork = "Arbitrum");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "XRP",
                    icon: "assets/images/xrp.png",
                    isSelected: selectedNetwork == "XRP",
                    onTap: () {
                      setState(() => selectedNetwork = "XRP");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Avalanche",
                    icon: "assets/images/avax.png",
                    isSelected: selectedNetwork == "Avalanche",
                    onTap: () {
                      setState(() => selectedNetwork = "Avalanche");
                      Navigator.pop(context);
                    },
                  ),
                  _NetworkOption(
                    name: "Polkadot",
                    icon: "assets/images/dot.png",
                    isSelected: selectedNetwork == "Polkadot",
                    onTap: () {
                      setState(() => selectedNetwork = "Polkadot");
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

  /// فیلتر کردن توکن‌ها (مطابق با Kotlin)
  List<CryptoToken> get filteredTokens {
    return tokens.where((token) {
      final matchesSearch = searchText.isEmpty ||
          (token.name ?? '').toLowerCase().contains(searchText.toLowerCase()) ||
          (token.symbol == null ? '' : token.symbol!).toLowerCase().contains(searchText.toLowerCase());
      
      final matchesNetwork = selectedNetwork == 'All' ||
          (token.blockchainName ?? '').toLowerCase().contains(selectedNetwork.toLowerCase());

      return matchesSearch && matchesNetwork;
    }).toList();
  }

  /// تست دستی برای بررسی API (مطابق با Kotlin send_screen.kt)
  Future<void> _testGetUserBalance() async {
    print('🧪 Manual Test - Starting getBalance test (matching Kotlin send_screen.kt)...');
    
    try {
      // Test با userId واقعی
      final testUserId = userId ?? 'd7fd960c-0b3b-4f0c-8963-baa6b365953d';
      
      print('🧪 Test UserID: $testUserId');
      print('🧪 Test - Using getBalance API with empty currencyNames and blockchain');
      
      final apiService = ApiService();
      final response = await apiService.getBalance(
        testUserId,
        currencyNames: [], // خالی مانند Kotlin send_screen.kt
        blockchain: {},
      );
      
      print('🧪 Test Response:');
      print('   Success: ${response.success}');
      print('   UserID: ${response.userID}');
      print('   Balances count: ${response.balances?.length ?? 0}');
      
      if (response.balances != null) {
        for (final balance in response.balances!) {
          print('   Balance: ${balance.symbol} = ${balance.balance} (${balance.blockchain})');
        }
      }
      
      // نمایش نتیجه در UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test getBalance API Result: ${response.success ? 'Success' : 'Failed'}'),
            backgroundColor: response.success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      print('🧪 Test Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test getBalance API Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _safeTranslate('send_token', 'Send Token'),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: () {
                _fetchBalanceDirectly();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _testGetUserBalance,
          backgroundColor: Colors.blue,
          child: const Icon(Icons.bug_report),
          tooltip: 'Test getBalance API',
        ),
        body: RefreshIndicator(
          onRefresh: _refreshTokens,
          child: Column(
            children: [
              // Search and filter section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Search bar
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: _safeTranslate('search_tokens', 'Search tokens...'),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  searchText = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Network filter - مطابق با سایر صفحات
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: _showNetworkFilter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F3F4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedNetwork,
                                style: const TextStyle(fontSize: 14, color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.black, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Token list
              Expanded(
                child: Stack(
                  children: [
                    _buildContent(),
                    if (isLoading) const LoadingOverlay(isLoading: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (filteredTokens.isEmpty && !isLoading) {
      return Center(
        child: Text(
          _safeTranslate('no_tokens_with_balance', 'No tokens with balance found'),
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredTokens.length,
      itemBuilder: (context, index) {
        final token = filteredTokens[index];
        return _TokenItem(
          token: token,
          selectedCurrency: selectedCurrency,
          currencySymbol: currencySymbol,
          getSafeTokenPrice: getSafeTokenPrice,
          formatAmount: formatAmount,
          calculateDollarValue: calculateDollarValue,
          onTap: () {
            try {
              final tokenJson = Uri.encodeComponent(jsonEncode(token.toJson()));
              Navigator.pushNamed(context, '/send_detail/$tokenJson');
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_safeTranslate('error_displaying_token', 'Error displaying token details'))),
              );
            }
          },
        );
      },
    );
  }
}

class _TokenItem extends StatelessWidget {
  final CryptoToken token;
  final String selectedCurrency;
  final String currencySymbol;
  final double Function(String) getSafeTokenPrice;
  final String Function(double, double) formatAmount;
  final String Function(double, double) calculateDollarValue;
  final VoidCallback onTap;

  const _TokenItem({
    required this.token,
    required this.selectedCurrency,
    required this.currencySymbol,
    required this.getSafeTokenPrice,
    required this.formatAmount,
    required this.calculateDollarValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final amount = token.amount ?? 0.0;
    final price = getSafeTokenPrice(token.symbol == null ? '' : token.symbol!);
    final formattedAmount = formatAmount(amount, price);
    final dollarValue = calculateDollarValue(amount, price);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Token icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: token.iconUrl ?? 'https://coinceeper.com/defualtIcons/coin.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) {
                    return const Icon(Icons.currency_bitcoin, size: 32, color: Colors.orange);
                  },
                  placeholder: (context, url) {
                    return const CircularProgressIndicator(strokeWidth: 2);
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Token info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    token.name ?? (token.symbol == null ? '' : token.symbol!),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${token.symbol == null ? '' : token.symbol!} • ${token.blockchainName ?? ''}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Amount and price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formattedAmount,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dollarValue,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Arrow icon
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

/// کامپوننت انتخاب شبکه (مطابق با سایر صفحات)
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
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 24,
              height: 24,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.currency_bitcoin, size: 24, color: Colors.orange);
              },
            ),
            const SizedBox(width: 12),
            Text(
              name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF11c699) : Colors.black,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check, color: Color(0xFF11c699)),
          ],
        ),
      ),
    );
  }
}