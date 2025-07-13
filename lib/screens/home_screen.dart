import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/main_layout.dart';
import '../services/device_registration_manager.dart';
import '../services/secure_storage.dart';
import '../providers/history_provider.dart';
import '../models/crypto_token.dart';
import 'crypto_details_screen.dart';
import '../providers/app_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:my_flutter_app/providers/price_provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart'; // Added import for APIService
import 'package:shared_preferences/shared_preferences.dart'; // Added import for SharedPreferences

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isHidden = false;
  int selectedTab = 0;
  bool _isInitialized = false;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  // کش سفارشی لوگوها
  final CacheManager tokenLogoCacheManager = CacheManager(
    Config(
      'tokenLogoCache',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 200,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHomeScreen();
  }

  Future<void> _initializeHomeScreen() async {
    print('🏠 HomeScreen: Starting initialization...');
    
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // Initialize price provider
      await priceProvider.loadSelectedCurrency();
      print('🏠 HomeScreen: Price provider currency loaded');
      
      // Register device in background
      _registerDeviceOnHome();
      print('🏠 HomeScreen: Device registration started');
      
      // Debug API calls مطابق با Home.kt
      await _debugApiCalls();
      
      // موازی: بارگذاری توکن‌ها و قیمت‌ها
      if (appProvider.tokenProvider != null) {
        await Future.wait<void>([
          // دریافت موجودی‌های فوری
          _loadBalancesForEnabledTokens(appProvider.tokenProvider!),
          // دریافت قیمت‌های فوری
          _loadPricesForEnabledTokens(appProvider.tokenProvider!, priceProvider),
        ]);
      }
      
      setState(() {
        _isInitialized = true;
      });
      
      // شروع periodic updates در background
      _startPeriodicUpdates();
      
    } catch (e) {
      print('❌ HomeScreen: Error initializing: $e');
      setState(() {
        _isInitialized = true;
      });
    }
  }

  /// بارگذاری موجودی‌ها برای توکن‌های فعال
  Future<void> _loadBalancesForEnabledTokens(tokenProvider) async {
    try {
      print('💰 HomeScreen: Loading balances for enabled tokens');
      await tokenProvider.updateBalance();
      print('✅ HomeScreen: Balances loaded successfully');
    } catch (e) {
      print('❌ HomeScreen: Error loading balances: $e');
    }
  }

  /// بارگذاری قیمت‌ها برای توکن‌های فعال
  Future<void> _loadPricesForEnabledTokens(tokenProvider, PriceProvider priceProvider) async {
    final enabledTokens = tokenProvider.enabledTokens;
    await _loadPricesForTokens(enabledTokens, priceProvider);
  }

  Future<void> _loadPricesForTokens(List<CryptoToken> tokens, PriceProvider priceProvider) async {
    if (tokens.isEmpty) return;
    
    print('🔄 HomeScreen: Loading prices for ${tokens.length} tokens');
    
    // Get symbols from actual loaded tokens
    final tokenSymbols = tokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
    
    // Add common cryptocurrencies even if not in enabled tokens
    final commonSymbols = ['BTC', 'ETH', 'SOL', 'AVAX', 'DOT', 'BNB', 'TRX', 'USDT', 'ADA', 'MATIC'];
    
    // Combine and remove duplicates
    final allSymbols = {...tokenSymbols, ...commonSymbols}.toList();
    
    // Fetch prices for all available currencies
    final currencies = [
      'USD', 'CAD', 'AUD', 'GBP', 'EUR', 'KWD', 'TRY', 'SAR', 'CNY', 'KRW', 
      'JPY', 'INR', 'RUB', 'IQD', 'TND', 'BHD'
    ];
    
    print('🔄 HomeScreen: Fetching prices for symbols: $allSymbols');
    await priceProvider.fetchPrices(allSymbols, currencies: currencies);
    print('✅ HomeScreen: Prices loaded successfully');
  }

  /// شروع periodic updates برای wallet استاندارد
  void _startPeriodicUpdates() {
    // هر 30 ثانیه قیمت‌ها را به‌روزرسانی کن
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _isInitialized) {
        _refreshPricesForEnabledTokens();
        _startPeriodicUpdates(); // recursive call for continuous updates
      }
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isInitialized) {
      // هنگام بازگشت به اپ، فوراً balance و قیمت‌ها را به‌روزرسانی کن
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performFullRefresh();
      });
    }
  }

  /// refresh کامل برای بازگشت به اپ
  Future<void> _performFullRefresh() async {
    if (!_isInitialized) return;
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    // موازی: refresh موجودی‌ها و قیمت‌ها
    await Future.wait<void>([
      _loadBalancesForEnabledTokens(appProvider.tokenProvider!),
      _loadPricesForEnabledTokens(appProvider.tokenProvider!, priceProvider),
    ]);
  }

  void _refreshPricesForEnabledTokens() async {
    if (!_isInitialized) return;
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    final enabledTokens = appProvider.tokenProvider!.enabledTokens;
    await _loadPricesForTokens(enabledTokens, priceProvider);
  }

  /// refresh با balance update برای دکمه refresh
  Future<void> _performManualRefresh() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    try {
      // موازی: refresh موجودی‌ها و قیمت‌ها
      await Future.wait<void>([
        appProvider.tokenProvider!.updateBalance().then((_) => null), // convert Future<bool> to Future<void>
        _loadPricesForEnabledTokens(appProvider.tokenProvider!, priceProvider),
      ]);
      
      return; // success
    } catch (e) {
      print('❌ HomeScreen: Error in manual refresh: $e');
      rethrow; // re-throw for UI handling
    }
  }

  /// refresh فوری بعد از تغییر توکن‌ها
  Future<void> _performImmediateRefreshAfterTokenChange() async {
    if (!_isInitialized) return;
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    try {
      print('⚡ HomeScreen: Performing immediate refresh after token change');
      
      // Get newly enabled tokens
      final enabledTokens = appProvider.tokenProvider!.enabledTokens;
      print('⚡ HomeScreen: Current enabled tokens: ${enabledTokens.map((t) => t.symbol).toList()}');
      
      // موازی: دریافت موجودی‌ها و قیمت‌ها برای تمام توکن‌های فعال
      await Future.wait<void>([
        // دریافت موجودی‌های جدید
        appProvider.tokenProvider!.updateBalance().then((_) => null), // convert Future<bool> to Future<void>
        // دریافت قیمت‌های جدید برای تمام توکن‌های فعال
        _loadPricesForTokens(enabledTokens, priceProvider),
      ]);
      
      print('✅ HomeScreen: Immediate refresh completed successfully');
      
    } catch (e) {
      print('❌ HomeScreen: Error in immediate refresh: $e');
    }
  }

  /// به‌روزرسانی کش صفحه add_token برای همگام‌سازی
  Future<void> _updateAddTokenScreenCache(CryptoToken token) async {
    try {
      print('🔄 HomeScreen: Updating add_token screen cache for ${token.symbol}');
      
      // Clear the add_token cache to force refresh
      // این کار باعث می‌شود که وقتی کاربر به add_token برود، حالت جدید نمایش داده شود
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('add_token_cached_tokens');
      
      print('✅ HomeScreen: add_token cache cleared for synchronization');
    } catch (e) {
      print('❌ HomeScreen: Error updating add_token cache: $e');
    }
  }

  /// فعال‌سازی مجدد توکن با دریافت فوری موجودی و قیمت
  Future<void> _performTokenReactivation(CryptoToken token) async {
    try {
      print('🔄 HomeScreen: Reactivating token ${token.symbol}');
      
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      if (appProvider.tokenProvider != null) {
        // موازی: دریافت موجودی و قیمت فوری برای توکن فعال شده مجدد
        await Future.wait<void>([
          appProvider.tokenProvider!.updateSingleTokenBalance(token),
          _fetchTokenPrice(token, priceProvider),
        ]);
        
        print('✅ HomeScreen: Token ${token.symbol} reactivated with fresh data');
      }
    } catch (e) {
      print('❌ HomeScreen: Error reactivating token ${token.symbol}: $e');
    }
  }

  /// دریافت قیمت برای یک توکن خاص
  Future<void> _fetchTokenPrice(CryptoToken token, PriceProvider priceProvider) async {
    try {
      final symbol = token.symbol ?? '';
      if (symbol.isNotEmpty) {
        await priceProvider.fetchPrices([symbol]);
      }
    } catch (e) {
      print('❌ HomeScreen: Error fetching price for ${token.symbol}: $e');
    }
  }

  /// ثبت دستگاه هنگام ورود به صفحه home
  Future<void> _registerDeviceOnHome() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final userId = appProvider.currentUserId;
      final walletId = appProvider.currentWalletName;
      if (userId != null && walletId != null) {
        await DeviceRegistrationManager.instance.registerDeviceWithCallback(
          userId: userId,
          walletId: walletId,
          onResult: (success) {
            if (success) {
              print('✅ Device registered successfully on home screen');
            } else {
              print('❌ Device registration failed on home screen');
            }
          },
        );
      } else {
        print('⚠️ User ID or Wallet ID not available for device registration');
      }
    } catch (e) {
      print('❌ Error registering device on home screen: $e');
    }
  }

  /// تست API مطابق با Home.kt
  Future<void> _debugApiCalls() async {
    try {
      print('🧪 HomeScreen: Starting debug API calls (matching Home.kt)...');
      
      final apiService = ApiService();
      
      // تست مستقیم API با UserID ثابت مطابق Home.kt
      const testUserId = "0d32dfd0-f7ba-4d5a-a408-75e6c2961e23";
      print('🧪 HomeScreen: Testing balance API with fixed UserID: $testUserId');
      
      final request = await apiService.getBalance(
        testUserId,
        currencyNames: [], // خالی برای دریافت همه موجودی‌ها مانند کاتلین
        blockchain: {},
      );
      
      print('📥 HomeScreen: Debug API Response:');
      print('   Success: ${request.success}');
      print('   UserID: ${request.userID}');
      print('   Balances count: ${request.balances?.length ?? 0}');
      
      if (request.success && request.balances != null) {
        print('   Balances details:');
        for (final balance in request.balances!) {
          print('     Token: ${balance.symbol ?? 'Unknown'}');
          print('       Balance: ${balance.balance ?? '0'}');
          print('       Blockchain: ${balance.blockchain ?? 'Unknown'}');
          print('       Currency: ${balance.currencyName ?? 'Unknown'}');
          print('       IsToken: ${balance.isToken ?? false}');
        }
      }
      
      if (request.message != null) {
        print('   Message: ${request.message}');
      }
      
      print('✅ HomeScreen: Debug API calls completed');
      
    } catch (e) {
      print('❌ HomeScreen: Error in debug API calls: $e');
    }
  }

  // Pre-cache token logos
  Future<void> preCacheTokenLogos(List<CryptoToken> tokens) async {
    for (final token in tokens) {
      final url = token.iconUrl;
      if (url != null && url.startsWith('http')) {
        try {
          await tokenLogoCacheManager.downloadFile(url);
        } catch (e) {
          print('Failed to cache logo for ${token.symbol}: $e');
        }
      }
    }
  }

  void _showWalletModal() {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final wallets = appProvider.wallets;
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
            Text(_safeTranslate('select_wallet', 'Select Wallet'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 16),
            ...wallets.map((w) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF08C495), Color(0xFF39b6fb)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(w['walletName'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    onTap: () async {
                      await appProvider.selectWallet(w['walletName'] ?? '');
                      Navigator.pop(context);
                      // Immediate refresh after wallet change
                      print('🔄 HomeScreen: Wallet changed, performing immediate refresh');
                      await _performImmediateRefreshAfterTokenChange();
                    },
                  ),
                )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// تست API برای دیباگ (مطابق با Kotlin Home.kt)
  Future<void> _testGetBalanceAPI() async {
    print('🧪 HomeScreen - Testing getBalance API (matching Kotlin Home.kt)...');
    
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final userId = appProvider.currentUserId;
      
      if (userId == null) {
        print('❌ HomeScreen - No userId available for API test');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No userId available for API test'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      print('🧪 HomeScreen - Test UserID: $userId');
      print('🧪 HomeScreen - Testing with empty currencyNames and blockchain (like Kotlin)');
      
      final apiService = ApiService();
      final response = await apiService.getBalance(
        userId,
        currencyNames: [], // خالی مانند Kotlin Home.kt
        blockchain: {},
      );
      
      print('🧪 HomeScreen - Test Response:');
      print('   Success: ${response.success}');
      print('   UserID: ${response.userID}');
      print('   Balances count: ${response.balances?.length ?? 0}');
      
      if (response.balances != null) {
        for (final balance in response.balances!) {
          final balanceValue = double.tryParse(balance.balance ?? '0') ?? 0.0;
          if (balanceValue > 0.0) {
            print('   Active Balance: ${balance.symbol ?? 'Unknown'} = ${balance.balance ?? '0'} (${balance.blockchain ?? 'Unknown'})');
          }
        }
      }
      
      // نمایش نتیجه در UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Debug getBalance API: ${response.success ? 'Success' : 'Failed'}'),
            backgroundColor: response.success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('🧪 HomeScreen - Test Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Debug getBalance API Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, _) {
        // Show loading if AppProvider is not initialized yet
        if (!_isInitialized || appProvider.tokenProvider == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            ),
          );
        }

        final walletName = appProvider.currentWalletName ?? _safeTranslate('my_wallet', 'My Wallet');
        final tokenProvider = appProvider.tokenProvider!;
        
        // Pre-cache logos when tokens are available
        if (tokenProvider.enabledTokens.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            preCacheTokenLogos(tokenProvider.enabledTokens);
          });
        }
        
        // Show loading while TokenProvider is initializing
        if (tokenProvider.isLoading) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            ),
          );
        }
        
        // Show "Add Token" screen only if loading is complete and no tokens found
        if (tokenProvider.enabledTokens.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      _safeTranslate('no_active_tokens_found', 'No active tokens found'),
                      style: const TextStyle(color: Color(0xFF555555), fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/add-token'),
                      child: Text(_safeTranslate('add_token', 'Add Token')),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
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
                              onTap: () async {
                                // Navigate to add token screen with immediate refresh on return
                                final result = await Navigator.pushNamed(context, '/add-token');
                                
                                // فوراً refresh کن بدون توجه به result
                                print('🔄 HomeScreen: Returned from add-token screen, performing immediate refresh');
                                await _performImmediateRefreshAfterTokenChange();
                              },
                              child: Image.asset('assets/images/music.png', width: 18, height: 18),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                        // Center wallet name and visibility
                        GestureDetector(
                          onTap: _showWalletModal,
                          onDoubleTap: _testGetBalanceAPI, // تست API با double tap برای دیباگ
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
                                    color: const Color(0xFF666666),
                                  ),
                              ),
                            ],
                          ),
                        ),
                        // Right icon
                        GestureDetector(
                          onTap: () async {
                            // Navigate to add token screen with immediate refresh on return
                            final result = await Navigator.pushNamed(context, '/add-token');
                            
                            // فوراً refresh کن بدون توجه به result
                            print('🔄 HomeScreen: Returned from add-token screen, performing immediate refresh');
                            await _performImmediateRefreshAfterTokenChange();
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
                        Consumer<PriceProvider>(
                          builder: (context, priceProvider, child) {
                            final totalValue = _calculateTotalValue(tokenProvider.enabledTokens, priceProvider);
                            final currencySymbol = priceProvider.getCurrencySymbol();
                            final formattedValue = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2).format(totalValue);
                            return Text(
                              isHidden ? '****' : formattedValue,
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                            );
                          },
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
                          icon: Icons.send_rounded,
                          label: _safeTranslate('send', 'Send'),
                          onTap: () {
                            Navigator.pushNamed(context, '/send');
                          },
                          bgColor: const Color(0x80D7FBE7),
                        ),
                        _ActionButton(
                          icon: Icons.call_received_rounded,
                          label: _safeTranslate('receive', 'Receive'),
                          onTap: () {
                            Navigator.pushNamed(context, '/receive');
                          },
                          bgColor: const Color(0x80D7F0F1),
                        ),
                        _ActionButton(
                          icon: Icons.refresh_rounded,
                          label: _safeTranslate('refresh', 'Refresh'),
                          onTap: () async {
                            try {
                              // نمایش loading state
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(_safeTranslate('updating_balance_and_prices', 'Updating balance and prices...')),
                                    ],
                                  ),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                              
                              // انجام refresh کامل
                              await _performManualRefresh();
                              
                              // نمایش پیام موفقیت
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_safeTranslate('balance_and_prices_updated', 'Balance and prices updated successfully')),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            } catch (e) {
                              // نمایش پیام خطا
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_safeTranslate('update_error', 'Error updating: {error}').replaceAll('{error}', e.toString())),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          bgColor: const Color(0x80F0E7FD),
                        ),
                        Consumer<HistoryProvider>(
                          builder: (context, historyProvider, child) {
                            final pendingCount = historyProvider.pendingTransactionCount;
                            return _ActionButton(
                              icon: Icons.history_rounded,
                              label: _safeTranslate('history', 'History'),
                              onTap: () {
                                Navigator.pushNamed(context, '/history');
                              },
                              bgColor: const Color(0x80D6E8FF),
                              badge: pendingCount > 0 ? pendingCount.toString() : null,
                            );
                          },
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
                          label: _safeTranslate('cryptos', 'Cryptos'),
                          selected: selectedTab == 0,
                          onTap: () => setState(() => selectedTab = 0),
                        ),
                        _TabButton(
                          label: _safeTranslate('nfts', "NFT's"),
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
                        ? Consumer<PriceProvider>(
                            builder: (context, priceProvider, _) {
                              final enabledTokens = tokenProvider.enabledTokens;
                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                                itemCount: enabledTokens.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final token = enabledTokens[index];
                                  final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
                                  return Dismissible(
                                    key: ValueKey(token.symbol ?? token.name ?? index),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      color: Colors.red,
                                      child: const Icon(Icons.delete, color: Colors.white),
                                    ),
                                    onDismissed: (direction) async {
                                      print('🗑️ HomeScreen: Dismissing token ${token.symbol}');
                                      
                                      try {
                                        // غیرفعال کردن توکن در TokenProvider
                                        await tokenProvider.toggleToken(token, false);
                                        
                                        // اطمینان از به‌روزرسانی کش add_token_screen
                                        await _updateAddTokenScreenCache(token);
                                        
                                        // نمایش پیام confirmation
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(_safeTranslate('token_removed', 'Token {symbol} removed').replaceAll('{symbol}', token.symbol ?? '')),
                                            backgroundColor: Colors.orange,
                                            duration: const Duration(seconds: 2),
                                            action: SnackBarAction(
                                              label: _safeTranslate('undo', 'Undo'),
                                              textColor: Colors.white,
                                              onPressed: () async {
                                                // Re-enable the token
                                                await tokenProvider.toggleToken(token, true);
                                                await _updateAddTokenScreenCache(token);
                                                
                                                // Refresh balance and price for re-enabled token
                                                await _performTokenReactivation(token);
                                              },
                                            ),
                                          ),
                                        );
                                        
                                        print('✅ HomeScreen: Token ${token.symbol} dismissed and cache updated');
                                      } catch (e) {
                                        print('❌ HomeScreen: Error dismissing token ${token.symbol}: $e');
                                        
                                        // نمایش پیام خطا
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(_safeTranslate('error_removing_token', 'Error removing token: {error}').replaceAll('{error}', e.toString())),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CryptoDetailsScreen(
                                              tokenName: token.name ?? '',
                                              tokenSymbol: token.symbol ?? '',
                                              iconUrl: token.iconUrl ?? 'https://coinceeper.com/defualtIcons/coin.png',
                                              isToken: token.isToken,
                                              blockchainName: token.blockchainName ?? '',
                                              gasFee: 0.0, // TODO: دریافت از API
                                            ),
                                          ),
                                        );
                                      },
                                      child: _TokenRow(
                                        token: token,
                                        isHidden: isHidden,
                                        tokenLogoCacheManager: tokenLogoCacheManager,
                                        price: price,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          )
                        : _NFTEmptyWidget(_safeTranslate('no_nft_found', 'No NFT Found')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// محاسبه کل ارزش توکن‌ها با استفاده از PriceProvider
  double _calculateTotalValue(List<CryptoToken> tokens, PriceProvider priceProvider) {
    double total = 0.0;
    for (final token in tokens) {
      final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
      final value = token.amount * price;
      total += value;
    }
    return total;
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color bgColor;
  final String? badge;
  const _ActionButton({
    required this.icon, 
    required this.label, 
    required this.onTap, 
    required this.bgColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 24,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
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
            color: selected ? const Color(0xFF11c699) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}

class _NFTEmptyWidget extends StatelessWidget {
  final String text;
  const _NFTEmptyWidget(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/images/card.png', width: 90, height: 90, color: Colors.grey.withOpacity(0.2)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  final CryptoToken token;
  final bool isHidden;
  final CacheManager? tokenLogoCacheManager;
  final double price;
  
  const _TokenRow({
    required this.token,
    required this.isHidden,
    this.tokenLogoCacheManager,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final tokenValue = token.amount * price;
    
    // Helper for formatting
    final amountFormat = NumberFormat('#,##0.####');
    
    // لوگوهای معروف را از asset نمایش بده
    final assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      // ... سایر توکن‌های معروف
    };
    final symbol = (token.symbol ?? '').toUpperCase();
    final assetIcon = assetIcons[symbol];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE7FAEF), Color(0xFFE7F0FB)]),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          // Token icon
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: ClipOval(
              child: assetIcon != null
                  ? Image.asset(assetIcon, width: 28, height: 28, fit: BoxFit.cover)
                  : (token.iconUrl ?? '').startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: token.iconUrl ?? '',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          cacheManager: tokenLogoCacheManager,
                          placeholder: (context, url) => Image.asset(
                            'assets/images/default_token.png',
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                          ),
                          errorWidget: (context, url, error) => Icon(
                            Icons.currency_bitcoin,
                            size: 20,
                            color: Colors.orange,
                          ),
                        )
                      : (token.iconUrl ?? '').startsWith('assets/')
                          ? Image.asset(token.iconUrl ?? '', width: 28, height: 28, fit: BoxFit.cover)
                          : Icon(Icons.currency_bitcoin, size: 20, color: Colors.orange),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(token.name ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('(${token.symbol ?? ''})', style: const TextStyle(fontSize: 12, color: Color(0xff2b2b2b))),
                ],
              ),
              const SizedBox(height: 1),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedPrice = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2).format(price);
                  return Text(formattedPrice, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)));
                },
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isHidden ? '****' : amountFormat.format(token.amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedValue = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2).format(tokenValue);
                  return Text(isHidden ? '****' : formattedValue, style: const TextStyle(fontSize: 12, color: Color(0xFF666666)));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
} 