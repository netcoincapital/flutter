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
import '../services/api_models.dart';
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
        // تأیید اینکه wallet واقعا موجود است
        try {
          final mnemonic = await SecureStorage.instance.getMnemonic(selectedWallet, selectedUserId);
          if (mnemonic != null && mnemonic.isNotEmpty) {
            setState(() {
              walletName = selectedWallet;
              userId = selectedUserId;
            });
            print('✅ Send Screen - Loaded selected wallet: $selectedWallet with userId: $selectedUserId');
            return;
          } else {
            print('⚠️ Selected wallet has no mnemonic, trying alternative...');
          }
        } catch (e) {
          print('⚠️ Error validating selected wallet: $e');
        }
      }
      
      print('⚠️ No valid selected wallet found, trying first available wallet...');
      // Fallback: use first available wallet
      final wallets = await SecureStorage.instance.getWalletsList();
      print('📋 Available wallets count: ${wallets.length}');
      
      if (wallets.isNotEmpty) {
        // تلاش برای پیدا کردن اولین wallet معتبر
        for (int i = 0; i < wallets.length; i++) {
          final wallet = wallets[i];
          print('📋 Checking wallet $i: $wallet');
          
          final walletName = wallet['walletName'] ?? wallet['name'];
          final walletUserId = wallet['userID'] ?? wallet['userId'];
          
          print('📋 Extracted from wallet $i:');
          print('   Wallet name: $walletName');
          print('   User ID: $walletUserId');
          
          if (walletName != null && walletUserId != null) {
            try {
              final mnemonic = await SecureStorage.instance.getMnemonic(walletName, walletUserId);
              if (mnemonic != null && mnemonic.isNotEmpty) {
                setState(() {
                  this.walletName = walletName;
                  userId = walletUserId;
                });
                
                // Set this as the selected wallet for future use
                await SecureStorage.instance.saveSelectedWallet(walletName, walletUserId);
                
                print('✅ Using valid wallet: $walletName with userId: $walletUserId');
                return;
              } else {
                print('⚠️ Wallet $i has no mnemonic');
              }
            } catch (e) {
              print('⚠️ Error checking wallet $i: $e');
              continue;
            }
          } else {
            print('⚠️ Wallet $i has invalid name or userId');
          }
        }
        
        print('❌ No valid wallets found in list!');
      } else {
        print('❌ No wallets found at all!');
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
      final symbols = tokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
      
      if (symbols.isNotEmpty && priceProvider != null) {
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
    
    try {
      // بررسی اولیه userId
      if (userId == null || userId!.isEmpty) {
        print('⚠️ UserId is null or empty, attempting to recover...');
        
        // تلاش برای دریافت مجدد userId از SecureStorage
        await _loadSelectedWallet();
        
        // اگر هنوز userId نداریم، تلاش برای دریافت اولین wallet موجود
        if (userId == null || userId!.isEmpty) {
          print('⚠️ Still no userId, trying to get first available wallet...');
          final wallets = await SecureStorage.instance.getWalletsList();
          
          if (wallets.isNotEmpty) {
            final firstWallet = wallets.first;
            final walletName = firstWallet['walletName'] ?? firstWallet['name'];
            final walletUserId = firstWallet['userID'] ?? firstWallet['userId'];
            
            if (walletName != null && walletUserId != null) {
              setState(() {
                this.walletName = walletName;
                userId = walletUserId;
              });
              print('🔄 Using first available wallet: $walletName with userId: $walletUserId');
            } else {
              print('❌ No valid wallet found in list');
              throw Exception('No valid wallet found. Please select a wallet first.');
            }
          } else {
            print('❌ No wallets available at all');
            throw Exception('No wallets available. Please create or import a wallet first.');
          }
        }
      }

      print('✅ UserId validation passed: $userId');
      print('✅ WalletName: $walletName');
      
      setState(() {
        isLoading = true;
      });

      final apiService = ApiService();
      
      // بررسی در دسترس بودن providers
      TokenProvider? tokenProvider;
      PriceProvider? priceProvider;
      
      try {
        tokenProvider = Provider.of<TokenProvider>(context, listen: false);
        priceProvider = Provider.of<PriceProvider>(context, listen: false);
      } catch (e) {
        print('⚠️ Error accessing providers: $e');
        tokenProvider = null;
        priceProvider = null;
      }
      
      // دریافت لیست توکن‌های موجود
      final availableTokens = tokenProvider?.currencies ?? [];
      print('📋 Available tokens count: ${availableTokens.length}');
      
      // فراخوانی API با error handling بهبود یافته
      print('💰 Calling getBalance API...');
      print('📤 Request - UserID: $userId');
      print('📤 Request - CurrencyNames: [] (empty for all balances)');
      print('📤 Request - Blockchain: {} (empty map)');
      
      BalanceResponse response;
      try {
        response = await apiService.getBalance(
          userId!,
          currencyNames: [], // خالی برای دریافت همه موجودی‌ها
          blockchain: {},
        );
        
        print('📥 API Response received:');
        print('   Success: ${response.success}');
        print('   UserID: ${response.userID}');
        print('   Balances count: ${response.balances?.length ?? 0}');
        print('   Message: ${response.message}');
        
      } catch (apiError) {
        print('❌ API Error occurred: $apiError');
        
        // بدون نوشتن در دیتابیس: عدم استفاده از update-balance در retry
        rethrow;
      }
      
      // بررسی پاسخ API
      if (response.success && response.balances != null && response.balances!.isNotEmpty) {
        print('✅ getBalance API response successful');
        print('📊 Processing ${response.balances!.length} balance items...');
        
        final newTokens = <CryptoToken>[];
        final newBalanceItems = <models.BalanceItem>[];
        int processedBalances = 0;
        int tokensWithBalance = 0;
        
        // پردازش موجودی‌ها
        for (final balanceItem in response.balances!) {
          processedBalances++;
          
          try {
            final balance = double.tryParse(balanceItem.balance ?? '0') ?? 0.0;
            
            print('🔍 Processing balance $processedBalances: ${balanceItem.symbol ?? 'Unknown'} = ${balanceItem.balance ?? '0'} (parsed: $balance)');
            
            // فقط موجودی‌های مثبت
            if (balance > 0.0 && balanceItem.symbol != null && balanceItem.symbol!.isNotEmpty) {
              tokensWithBalance++;
              print('   ✅ Token has positive balance: ${balanceItem.symbol} = $balance');
              
              // پیدا کردن توکن مطابق یا ایجاد جدید
              final matchingToken = availableTokens.firstWhere(
                (token) => token.symbol == balanceItem.symbol,
                orElse: () {
                  print('   📝 Creating new token for: ${balanceItem.symbol}');
                  return CryptoToken(
                    name: balanceItem.currencyName ?? balanceItem.symbol ?? 'Unknown',
                    symbol: balanceItem.symbol ?? 'Unknown',
                    blockchainName: balanceItem.blockchain ?? 'Unknown',
                    iconUrl: 'https://coinceeper.com/defaultIcons/coin.png',
                    isEnabled: true,
                    amount: 0.0,
                    isToken: balanceItem.isToken ?? true,
                  );
                },
              );

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
              print('   ⏭️ Token has zero balance or invalid symbol: ${balanceItem.symbol ?? 'Unknown'} = $balance');
            }
            
          } catch (itemError) {
            print('❌ Error processing balance item: $itemError');
            continue; // ادامه پردازش سایر items
          }
        }

        print('📊 Processing complete:');
        print('   Total balance items processed: $processedBalances');
        print('   Tokens with positive balance: $tokensWithBalance');
        print('   Final newTokens count: ${newTokens.length}');

        setState(() {
          balanceItems = newBalanceItems;
          tokens = newTokens;
        });

        print('✅ State updated with ${newTokens.length} tokens');

        // دریافت قیمت‌ها
        if (newTokens.isNotEmpty && priceProvider != null) {
          try {
            final symbols = newTokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
            final currencies = [selectedCurrency];
            
            print('🔄 Fetching prices for symbols: $symbols');
            await priceProvider.fetchPrices(symbols, currencies: currencies);
            print('✅ Prices fetched successfully');
          } catch (priceError) {
            print('⚠️ Error fetching prices: $priceError');
            // عدم دریافت قیمت‌ها مانع نمایش توکن‌ها نمی‌شود
          }
        } else {
          print('⚠️ Skipping price fetch - no tokens or price provider unavailable');
        }
        
        print('✅ Successfully loaded ${newTokens.length} tokens with positive balance');
        
      } else {
        print('❌ getBalance API failed or returned no data');
        print('   Success: ${response.success}');
        print('   Balances empty: ${response.balances?.isEmpty ?? true}');
        print('   Message: ${response.message}');
        
        // اگر API موفق نبود ولی هیچ خطایی نداشت، پیام متفاوتی نمایش دهیم
        String errorMessage;
        if (!response.success) {
          errorMessage = response.message ?? 'Server returned failure status';
        } else if (response.balances == null || response.balances!.isEmpty) {
          errorMessage = 'No balance data available. This might be a new wallet or all balances are zero.';
        } else {
          errorMessage = 'Unknown error occurred while fetching balance';
        }
        
        setState(() {
          tokens = [];
          balanceItems = [];
        });
        
      }
      
    } catch (e, stackTrace) {
      print('❌ Error fetching balance: $e');
      print('❌ Stack trace: $stackTrace');
      
      setState(() {
        tokens = [];
        balanceItems = [];
      });
      
      // تشخیص نوع خطا برای نمایش پیام مناسب
      String errorMessage;
      if (e.toString().contains('No valid wallet found')) {
        errorMessage = 'No valid wallet found. Please select a wallet first.';
      } else if (e.toString().contains('No wallets available')) {
        errorMessage = 'No wallets available. Please create or import a wallet first.';
      } else if (e.toString().contains('network') || e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timeout. Please try again.';
      } else if (e.toString().contains('Server communication error')) {
        errorMessage = 'Server error. Please try again later.';
      } else {
        errorMessage = 'Error loading balances: ${e.toString()}';
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
    try {
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
    } catch (e) {
      print('❌ Error getting safe token price for $tokenSymbol: $e');
      return 0.0;
    }
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

  /// نمایش modal برای انتخاب شبکه (مطابق با receive screen)
  void _showNetworkFilter() {
    // Remove modal bottom sheet - network filter removed
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

  void _showTokenSelector() {
    // Remove modal bottom sheet - token selector removed
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
        ),

        body: RefreshIndicator(
          onRefresh: _refreshTokens,
          child: Column(
            children: [
              // Search and filter section - مطابق با receive screen
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar - مطابق با receive screen
                    TextField(
                      decoration: InputDecoration(
                        hintText: _safeTranslate('search_tokens', 'Search tokens...'),
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0x25757575),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // Network filter - مطابق با receive screen
                    GestureDetector(
                      onTap: _showNetworkFilter,
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
                                selectedNetwork == 'All' ? _safeTranslate('select_network', 'Select Network') : selectedNetwork,
                                style: const TextStyle(fontSize: 16, color: Color(0xFF2c2c2c)),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 20),
                            const SizedBox(width: 8),
                          ],
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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredTokens.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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

  /// ساخت آیکن توکن مطابق با home screen
  Widget _buildTokenIcon(CryptoToken token) {
    // لوگوهای معروف را از asset نمایش بده
    final assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      'USDT': 'assets/images/usdt.png',
      'USDC': 'assets/images/usdc.png',
      'ADA': 'assets/images/cardano.png',
      'DOT': 'assets/images/dot.png',
      'SOL': 'assets/images/sol.png',
      'AVAX': 'assets/images/avax.png',
      'MATIC': 'assets/images/pol.png',
      'XRP': 'assets/images/xrp.png',
      'LINK': 'assets/images/chainlink.png',
      'UNI': 'assets/images/uniswap.png',
      'SHIB': 'assets/images/shiba.png',
      'LTC': 'assets/images/litecoin_logo.png',
      'DOGE': 'assets/images/dogecoin.png',
      'NCC': 'assets/images/ncc.png', // اضافه کردن NCC
    };
    
    final symbol = (token.symbol ?? '').toUpperCase();
    final assetIcon = assetIcons[symbol];

    // Debug log for NCC specifically
    if (symbol == 'NCC') {
      print('🔍 SendScreen NCC Debug:');
      print('  - Symbol: $symbol');
      print('  - AssetIcon path: $assetIcon');
      print('  - Token iconUrl: ${token.iconUrl}');
      print('  - Token name: ${token.name}');
      print('  - Will use network: ${(symbol == 'NCC' && (token.iconUrl ?? '').startsWith('http'))}');
      print('  - iconUrl starts with http: ${(token.iconUrl ?? '').startsWith('http')}');
    }

    return ClipOval(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: symbol == 'NCC' ? Colors.grey[100] : Colors.white, // Different background for NCC
          shape: BoxShape.circle,
        ),
        child: (symbol == 'NCC' && (token.iconUrl ?? '').startsWith('http'))
            ? CachedNetworkImage(
                imageUrl: token.iconUrl ?? '',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorWidget: (context, url, error) {
                  // Fallback to asset if network fails for NCC
                  return assetIcon != null
                      ? Image.asset(
                          assetIcon,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                        )
                      : const Icon(Icons.error);
                },
              )
            : assetIcon != null
                ? Image.asset(
                    assetIcon, 
                    width: 40, 
                    height: 40, 
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Asset error for $symbol: $error');
                      // Fallback to network image if asset fails
                      if ((token.iconUrl ?? '').startsWith('http')) {
                        return CachedNetworkImage(
                          imageUrl: token.iconUrl ?? '',
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                        );
                      }
                      return const Icon(Icons.error);
                    },
                  )
                : (token.iconUrl ?? '').startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: token.iconUrl ?? '',
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                      )
                    : (token.iconUrl ?? '').startsWith('assets/')
                        ? Image.asset(
                            token.iconUrl ?? '', 
                            width: 40, 
                            height: 40, 
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.currency_bitcoin, size: 28, color: Colors.orange),
                          )
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.currency_bitcoin, 
                              size: 28, 
                              color: Colors.orange,
                            ),
                          ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = token.amount ?? 0.0;
    final price = getSafeTokenPrice(token.symbol ?? '');
    final formattedAmount = formatAmount(amount, price);
    final dollarValue = calculateDollarValue(amount, price);
    
    // Debug log برای NCC
    if ((token.symbol ?? '').toUpperCase() == 'NCC') {
      print('🔍 SendScreen NCC Debug:');
      print('   Symbol: ${token.symbol}');
      print('   Name: ${token.name}');
      print('   Amount: $amount');
      print('   Price: $price');
      print('   Blockchain: ${token.blockchainName}');
      print('   IconUrl: ${token.iconUrl}');
      print('   FormattedAmount: $formattedAmount');
      print('   DollarValue: $dollarValue');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            // Token icon - مطابق با receive screen
            _buildTokenIcon(token),
            const SizedBox(width: 12),
            // Token info - مطابق با receive screen
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${token.name ?? (token.symbol ?? '')} (${token.symbol ?? ''})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        formattedAmount,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          token.blockchainName ?? '',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      Text(
                        dollarValue,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

  /// کامپوننت انتخاب شبکه (مطابق با receive screen)
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x1A1AC89E) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
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
            const SizedBox(width: 14),
            Text(
              name,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
            if (isSelected) ...[
              const Spacer(),
              const Icon(Icons.check, color: Color(0xFF08C495)),
            ],
          ],
        ),
      ),
    );
  }
}