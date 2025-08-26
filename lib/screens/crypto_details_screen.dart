import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';

import 'package:my_flutter_app/screens/receive_wallet_screen.dart';
import '../models/transaction.dart';
import '../models/crypto_token.dart';
import '../services/api_models.dart' as api;
import '../services/secure_storage.dart';
import '../services/service_provider.dart';
import '../services/chart_api_service.dart';
import '../services/crypto_logo_cache_service.dart';
import '../providers/price_provider.dart';
import '../utils/number_formatter.dart';
import '../providers/app_provider.dart';
import '../providers/token_provider.dart';
import '../widgets/crypto_chart_widget.dart';

/// Simple data class for price information
class CurrentPriceData {
  final double price;
  final double change24h;
  final double marketCap;
  final double volume24h;
  final DateTime lastUpdated;

  CurrentPriceData({
    required this.price,
    required this.change24h,
    required this.marketCap,
    required this.volume24h,
    required this.lastUpdated,
  });
}

/// Simple service for price data
class CoinMarketCapService {
  static Future<CurrentPriceData?> getCurrentPrice(String symbol) async {
    try {
      // Check if symbol has real price data by trying actual API call first
      // For now, return null to indicate no price data is available
      // This prevents showing fake prices for tokens without real data
      print('⚠️ No real price data available for symbol: $symbol');
      return null;
    } catch (e) {
      print('❌ Error fetching crypto price: $e');
      return null;
    }
  }
}

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

class _CryptoDetailsScreenState extends State<CryptoDetailsScreen> with SingleTickerProviderStateMixin {
  Color? dominantColor;

  List<Transaction> transactions = [];
  bool isLoading = true;
  String? errorMessage;
  double tokenBalance = 0.0;
  bool isLoadingBalance = true;
  TokenProvider? _tokenProvider;
  
  // New state variables for the redesigned UI
  late TabController _tabController;
  int _selectedTabIndex = 0;
  CurrentPriceData? currentPriceData;
  LivePriceData? livePrice; // Live price from new API
  bool isLoadingPrice = true;
  String? apiIconUrl; // Store the icon URL from API
  void _onTokenProviderChanged() {
    if (_tokenProvider == null) return;
    _syncBalanceFromProvider(_tokenProvider!);
  }

  void _syncBalanceFromProvider(TokenProvider tokenProvider) {
    try {
      final symbol = widget.tokenSymbol;
      final blockchain = widget.blockchainName;
      // Prefer enabled tokens, fallback to full list
      CryptoToken? token = tokenProvider.enabledTokens.firstWhere(
        (t) => (t.symbol ?? '').toUpperCase() == symbol.toUpperCase() &&
               (t.blockchainName ?? '') == blockchain,
        orElse: () => tokenProvider.currencies.firstWhere(
          (t) => (t.symbol ?? '').toUpperCase() == symbol.toUpperCase() &&
                 (t.blockchainName ?? '') == blockchain,
          orElse: () => CryptoToken(
            name: symbol,
            symbol: symbol,
            blockchainName: blockchain,
            iconUrl: widget.iconUrl,
            isEnabled: true,
            amount: 0.0,
            isToken: widget.isToken,
            smartContractAddress: null,
          ),
        ),
      );

      if (token?.amount != tokenBalance && mounted) {
        setState(() {
          tokenBalance = token?.amount ?? 0.0;
        });
      }
    } catch (_) {
      // Silent
    }
  }

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
    _tabController = TabController(length: 3, vsync: this);
    _initializeCryptoLogoCache(); // Initialize logo cache first
    _updatePalette(widget.iconUrl);
    _loadTransactions();
    _loadTokenBalance(); // اضافه کردن بارگذاری موجودی توکن
    _loadCurrentPrice(); // Load current price from CoinMarketCap
    _loadCryptoIcon(); // Load crypto icon from API
    
    // Immediately show balance from TokenProvider if available, and listen for updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        _tokenProvider = appProvider.tokenProvider;
        if (_tokenProvider != null) {
          _syncBalanceFromProvider(_tokenProvider!);
          _tokenProvider!.addListener(_onTokenProviderChanged);
        }
      } catch (_) {}
    });
    
    // Load selected currency and fetch price for this token (مطابق با Kotlin crypto_details.kt)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      await priceProvider.loadSelectedCurrency();
      
      // دریافت قیمت این توکن خاص (مطابق با Kotlin crypto_details.kt)
      await priceProvider.fetchPrices([widget.tokenSymbol], currencies: [priceProvider.selectedCurrency]);
    });
  }

  @override
  void dispose() {
    _tokenProvider?.removeListener(_onTokenProviderChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Load current price data from new Chart API
  Future<void> _loadCurrentPrice() async {
    setState(() {
      isLoadingPrice = true;
    });

    try {
      // Try new API first
      final livePrices = await ChartApiService.getLivePrices(
        symbols: [widget.tokenSymbol],
      );

      if (livePrices != null && livePrices.containsKey(widget.tokenSymbol)) {
        setState(() {
          livePrice = livePrices[widget.tokenSymbol];
          isLoadingPrice = false;
        });
        print('✅ Live price loaded: \$${livePrice?.price.toStringAsFixed(2)}');
      } else {
        // Fallback to old API
        final priceData = await CoinMarketCapService.getCurrentPrice(widget.tokenSymbol);
        setState(() {
          currentPriceData = priceData;
          isLoadingPrice = false;
        });
        print('✅ Fallback price loaded from CoinMarketCap');
      }
    } catch (e) {
      print('❌ Error loading current price: $e');
      // Try fallback to old API
      try {
        final priceData = await CoinMarketCapService.getCurrentPrice(widget.tokenSymbol);
        setState(() {
          currentPriceData = priceData;
          isLoadingPrice = false;
        });
      } catch (fallbackError) {
        print('❌ Fallback also failed: $fallbackError');
        setState(() {
          isLoadingPrice = false;
        });
      }
    }
  }

  /// Initialize crypto logo cache
  Future<void> _initializeCryptoLogoCache() async {
    try {
      await CryptoLogoCacheService.initialize();
      print('✅ Crypto logo cache initialized');
    } catch (e) {
      print('❌ Error initializing crypto logo cache: $e');
    }
  }

  /// Load crypto icon from cache
  Future<void> _loadCryptoIcon() async {
    try {
      print('🔍 Loading crypto icon for ${widget.tokenSymbol} from cache');
      
      final cachedUrl = await CryptoLogoCacheService.getLogoUrl(
        widget.tokenSymbol,
        blockchain: widget.blockchainName,
      );
      
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        print('✅ Found cached icon for ${widget.tokenSymbol}: $cachedUrl');
        setState(() {
          apiIconUrl = cachedUrl;
        });
        // Update palette with new icon
        _updatePalette(widget.iconUrl);
      } else {
        print('❌ No cached icon found for ${widget.tokenSymbol}');
      }
    } catch (e) {
      print('❌ Error loading crypto icon from cache: $e');
    }
  }

  /// ایجاد CryptoToken object برای ارسال به صفحه Send
  CryptoToken _createCryptoTokenForSend() {
    return CryptoToken(
      name: widget.tokenName,
      symbol: widget.tokenSymbol,
      blockchainName: widget.blockchainName,
      iconUrl: widget.iconUrl,
      isEnabled: true,
      amount: tokenBalance,
      isToken: widget.isToken,
      smartContractAddress: null, // می‌تواند null باشد یا از API دریافت شود
    );
  }

  /// هدایت به صفحه Send
  void _navigateToSendScreen() async {
    try {
      // ایجاد CryptoToken object
      final cryptoToken = _createCryptoTokenForSend();
      
      // تبدیل به JSON و encode کردن
      final tokenJson = jsonEncode(cryptoToken.toJson());
      final encodedTokenJson = Uri.encodeComponent(tokenJson);
      
      print('🚀 Navigating to Send screen with token data:');
      print('   Token: ${widget.tokenSymbol}');
      print('   Balance: $tokenBalance');
      print('   Blockchain: ${widget.blockchainName}');
      print('   Encoded JSON length: ${encodedTokenJson.length}');
      
      // هدایت به صفحه Send با format مطابق onGenerateRoute
      Navigator.pushNamed(
        context,
        '/send_detail/$encodedTokenJson',
      );
    } catch (e) {
      print('❌ Error navigating to send screen: $e');
      // Remove error message - silent failure
    }
  }

  /// دریافت آدرس کیف پول از API
  Future<String?> _getWalletAddress() async {
    try {
      final userId = await SecureStorage.getUserId();
      if (userId == null) {
        print('❌ CryptoDetails - No userId found for getting wallet address');
        return null;
      }

      print('🔍 CryptoDetails - Getting wallet address for blockchain: ${widget.blockchainName}');
      
      final apiService = ServiceProvider.instance.apiService;
      final response = await apiService.receiveToken(userId, widget.blockchainName);
      
      if (response.success && response.publicAddress != null) {
        print('✅ CryptoDetails - Wallet address received: ${response.publicAddress}');
        return response.publicAddress;
      } else {
        print('❌ CryptoDetails - Failed to get wallet address: ${response.message}');
        return null;
      }
    } catch (e) {
      print('❌ CryptoDetails - Error getting wallet address: $e');
      return null;
    }
  }

  /// دریافت موجودی توکن خاص فقط با API update-balance
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
        
        // فقط خواندن: استفاده از getBalance برای یک توکن خاص
        final response = await apiService.getBalance(
          userId,
          currencyNames: [widget.tokenSymbol],
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
          print('❌ CryptoDetails - No balance data received from getBalance');
          // Fallback to provider's current amount if available (بدون فراخوانی API دیگر)
          try {
            final appProvider = Provider.of<AppProvider>(context, listen: false);
            final tp = appProvider.tokenProvider;
            if (tp != null) {
              _syncBalanceFromProvider(tp);
            }
          } catch (_) {}
          setState(() {
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
      // Fallback to provider state on error as well (بدون استفاده از API balance)
      try {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        final tp = appProvider.tokenProvider;
        if (tp != null) {
          _syncBalanceFromProvider(tp);
        }
      } catch (_) {}
      setState(() {
        isLoadingBalance = false;
      });
    }
  }

  Future<void> _updatePalette(String iconUrl) async {
    try {
      // Use API icon if available, otherwise use provided iconUrl
      final effectiveIconUrl = apiIconUrl ?? iconUrl;
      final ImageProvider provider = effectiveIconUrl.startsWith('http')
          ? NetworkImage(effectiveIconUrl)
          : AssetImage(effectiveIconUrl) as ImageProvider;
      // Palette generation removed for now
      print('Palette generation removed for $effectiveIconUrl');
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
    // Prioritize API icon if available, otherwise use the provided iconUrl
    final effectiveIconUrl = apiIconUrl ?? iconUrl;
    
    print('🖼️ Building token icon for ${widget.tokenSymbol}:');
    print('   - Original iconUrl: $iconUrl');
    print('   - API iconUrl: $apiIconUrl');
    print('   - Effective iconUrl: $effectiveIconUrl');
    
    if (effectiveIconUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: effectiveIconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 52,
          height: 52,
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          print('❌ Error loading network icon from $url: $error');
          return const Icon(Icons.monetization_on, size: 52, color: Colors.grey);
        },
      );
    } else {
      return Image.asset(
        effectiveIconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error loading asset icon: $error');
          return const Icon(Icons.monetization_on, size: 52, color: Colors.grey);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and notification icon
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    widget.tokenName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.grey),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Token info section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          // Token icon with cached logo
                          CachedCryptoLogo(
                            symbol: widget.tokenSymbol,
                            blockchain: widget.blockchainName,
                            fallbackUrl: widget.iconUrl,
                            size: 60,
                            backgroundColor: const Color(0xFF0BAB9B),
                            backgroundOpacity: 0.15, // Much lighter background
                          ),
                          const SizedBox(height: 8),
                          
                          // Token name and symbol
                          Text(
                            widget.tokenSymbol,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            "${widget.isToken ? _safeTranslate('token', 'Token') : _safeTranslate('coin', 'Coin')} | ${widget.blockchainName}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Current price - prioritize live price
                          if (isLoadingPrice)
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                            )
                          else if (livePrice != null)
                            Column(
                              children: [
                                Text(
                                  '\$${NumberFormatter.formatDouble(livePrice!.price)}',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      livePrice!.change24h >= 0 
                                          ? Icons.arrow_upward 
                                          : Icons.arrow_downward,
                                      color: livePrice!.change24h >= 0 
                                          ? const Color(0xFF0BAB9B) 
                                          : const Color(0xFFF43672),
                                      size: 16,
                                    ),
                                    Text(
                                      '${livePrice!.change24h >= 0 ? '+' : ''}${livePrice!.change24h.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: livePrice!.change24h >= 0 
                                            ? const Color(0xFF0BAB9B) 
                                            : const Color(0xFFF43672),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          else if (currentPriceData != null)
                            Column(
                              children: [
                                Text(
                                  '\$${NumberFormatter.formatDouble(currentPriceData!.price)}',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      currentPriceData!.change24h >= 0 
                                          ? Icons.arrow_upward 
                                          : Icons.arrow_downward,
                                      color: currentPriceData!.change24h >= 0 
                                          ? const Color(0xFF0BAB9B) 
                                          : const Color(0xFFF43672),
                                      size: 16,
                                    ),
                                    Text(
                                      '${currentPriceData!.change24h >= 0 ? '+' : ''}${currentPriceData!.change24h.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: currentPriceData!.change24h >= 0 
                                            ? const Color(0xFF0BAB9B) 
                                            : const Color(0xFFF43672),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                const Text(
                                  '\$0.00',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'No price data available',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    
                    // Chart widget
                    CryptoChartWidget(
                      symbol: widget.tokenSymbol,
                      height: 250,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Tab bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: TabBar(
                        controller: _tabController,
                        onTap: (index) {
                          setState(() {
                            _selectedTabIndex = index;
                          });
                        },
                        labelColor: const Color(0xFF0BAB9B),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF0BAB9B),
                        indicatorWeight: 2,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 16,
                        ),
                        tabs: [
                          Tab(text: _safeTranslate('holdings', 'Holdings')),
                          Tab(text: _safeTranslate('history', 'History')),
                          Tab(text: _safeTranslate('about', 'About')),
                        ],
                      ),
                    ),
                    
                    // Tab content
                    Container(
                      height: 400,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Holdings tab
                          _buildHoldingsTab(),
                          // History tab
                          _buildHistoryTab(),
                          // About tab
                          _buildAboutTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomActionButton(
                    assetIcon: 'assets/images/send.png',
                    label: _safeTranslate('send', 'Send'),
                    onTap: () => _navigateToSendScreen(),
                  ),
                  _BottomActionButton(
                    assetIcon: 'assets/images/receive.png',
                    label: _safeTranslate('receive', 'Receive'),
                    onTap: () async {
                      try {
                        final address = await _getWalletAddress();
                        if (address != null && address.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiveWalletScreen(
                                cryptoName: widget.tokenName,
                                blockchainName: widget.blockchainName,
                                address: address,
                                symbol: widget.tokenSymbol,
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        // Silent failure
                      }
                    },
                  ),
                  _BottomActionButton(
                    icon: Icons.swap_horiz,
                    label: _safeTranslate('swap', 'Swap'),
                    onTap: () {
                      // TODO: Implement swap functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_safeTranslate('swap_coming_soon', 'Swap feature coming soon')),
                          backgroundColor: const Color(0xFF0BAB9B),
                        ),
                      );
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

  Widget _buildHoldingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            _safeTranslate('my_balance', 'My Balance'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CachedCryptoLogo(
                  symbol: widget.tokenSymbol,
                  blockchain: widget.blockchainName,
                  fallbackUrl: widget.iconUrl,
                  size: 40,
                  backgroundColor: const Color(0xFF0BAB9B),
                  backgroundOpacity: 0.12, // Even lighter for smaller size
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.blockchainName} ${widget.tokenSymbol}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        isLoadingBalance 
                            ? 'Loading...' 
                            : '${NumberFormatter.formatDouble(tokenBalance)} ${widget.tokenSymbol}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      () {
                        final price = livePrice?.price ?? currentPriceData?.price ?? 0.0;
                        if (price == 0.0) {
                          return '\$0.00';
                        }
                        return '\$${(tokenBalance * price).toStringAsFixed(2)}';
                      }(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: (livePrice?.price ?? currentPriceData?.price ?? 0.0) == 0.0 
                            ? Colors.grey 
                            : Colors.black,
                      ),
                    ),
                    Text(
                      '+\$0.00',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF0BAB9B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Use live price data if available, otherwise use current price data
          if (livePrice != null) ...[
            _buildInfoRow('Current Price', '\$${NumberFormatter.formatDouble(livePrice!.price)}'),
            _buildInfoRow('24h Volume', '\$${_formatLargeNumber(livePrice!.volume24h)}'),
            _buildInfoRow('24h Change', '${livePrice!.change24h >= 0 ? '+' : ''}${livePrice!.change24h.toStringAsFixed(2)}%'),
          ] else if (currentPriceData != null) ...[
            _buildInfoRow('Current Price', '\$${NumberFormatter.formatDouble(currentPriceData!.price)}'),
            _buildInfoRow('Market Cap', '\$${_formatLargeNumber(currentPriceData!.marketCap)}'),
            _buildInfoRow('24h Volume', '\$${_formatLargeNumber(currentPriceData!.volume24h)}'),
            _buildInfoRow('24h Change', '${currentPriceData!.change24h >= 0 ? '+' : ''}${currentPriceData!.change24h.toStringAsFixed(2)}%'),
          ] else ...[
            _buildInfoRow('Current Price', '\$0.00'),
            _buildInfoRow('Market Cap', 'Not available'),
            _buildInfoRow('24h Volume', 'Not available'),
            _buildInfoRow('24h Change', '0.00%'),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            )
          else if (errorMessage != null)
            Expanded(
              child: Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else
            Expanded(
              child: _TransactionHistorySection(
                transactions: transactions,
                tokenSymbol: widget.tokenSymbol,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            _safeTranslate('about', 'About') + ' ${widget.tokenName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Symbol', widget.tokenSymbol),
          _buildInfoRow('Blockchain', widget.blockchainName),
          _buildInfoRow('Type', widget.isToken ? 'Token' : 'Coin'),
          // Use live price data if available, otherwise use current price data
          if (livePrice != null) ...[
            _buildInfoRow('Current Price', '\$${NumberFormatter.formatDouble(livePrice!.price)}'),
            _buildInfoRow('24h Volume', '\$${_formatLargeNumber(livePrice!.volume24h)}'),
            _buildInfoRow('24h Change', '${livePrice!.change24h >= 0 ? '+' : ''}${livePrice!.change24h.toStringAsFixed(2)}%'),
          ] else if (currentPriceData != null) ...[
            _buildInfoRow('Current Price', '\$${NumberFormatter.formatDouble(currentPriceData!.price)}'),
            _buildInfoRow('Market Cap', '\$${_formatLargeNumber(currentPriceData!.marketCap)}'),
            _buildInfoRow('24h Volume', '\$${_formatLargeNumber(currentPriceData!.volume24h)}'),
            _buildInfoRow('24h Change', '${currentPriceData!.change24h >= 0 ? '+' : ''}${currentPriceData!.change24h.toStringAsFixed(2)}%'),
          ] else ...[
            _buildInfoRow('Current Price', '\$0.00'),
            _buildInfoRow('Market Cap', 'Not available'),
            _buildInfoRow('24h Volume', 'Not available'),
            _buildInfoRow('24h Change', '0.00%'),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLargeNumber(double number) {
    if (number >= 1e12) {
      return '${(number / 1e12).toStringAsFixed(2)}T';
    } else if (number >= 1e9) {
      return '${(number / 1e9).toStringAsFixed(2)}B';
    } else if (number >= 1e6) {
      return '${(number / 1e6).toStringAsFixed(2)}M';
    } else if (number >= 1e3) {
      return '${(number / 1e3).toStringAsFixed(2)}K';
    } else {
      return number.toStringAsFixed(2);
    }
  }
}

// Bottom action button widget
class _BottomActionButton extends StatelessWidget {
  final IconData? icon;
  final String? assetIcon;
  final String label;
  final VoidCallback onTap;

  const _BottomActionButton({
    this.icon,
    this.assetIcon,
    required this.label,
    required this.onTap,
  }) : assert(icon != null || assetIcon != null, 'Either icon or assetIcon must be provided');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF0BAB9B),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: assetIcon != null
                    ? Image.asset(
                        assetIcon!,
                        width: 24,
                        height: 24,
                        color: Colors.white,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to icon if asset fails
                          return Icon(
                            icon ?? Icons.help,
                            color: Colors.white,
                            size: 24,
                          );
                        },
                      )
                    : Icon(
                        icon!,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ],
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
    return NumberFormatter.formatAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = tx.direction == "inbound";
    final icon = isReceived ? Icons.arrow_downward : Icons.arrow_upward;
    final iconColor = isReceived ? const Color(0xFF0BAB9B) : const Color(0xFFF43672);
    final bgColor = isReceived ? const Color(0xFF0BAB9B).withOpacity(0.1) : const Color(0xFFF43672).withOpacity(0.1);
    final address = isReceived ? tx.from : tx.to;
    final shortAddress = address.length > 15 ? "${address.substring(0, 10)}...${address.substring(address.length - 5)}" : address;
    final amountPrefix = isReceived ? "+" : "-";
    final amountValue = "$amountPrefix${_formatAmount(tx.amount)}";
    final isPending = !isReceived && (tx.status ?? '').toLowerCase() == "pending";
    
    return GestureDetector(
      onTap: () {
        // Navigate to transaction detail screen with txHash for API loading
        Navigator.pushNamed(
          context,
          '/transaction_detail',
          arguments: {
            'transactionId': tx.txHash, // ارسال txHash برای دریافت جزئیات از API
          },
        );
      },
      child: Container(
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
                  Text(amountValue, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: amountValue.startsWith("-") ? const Color(0xFFF43672) : const Color(0xFF0BAB9B))),
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
      ),
    );
  }
} 