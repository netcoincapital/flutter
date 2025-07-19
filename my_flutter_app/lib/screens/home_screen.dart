import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/main_layout.dart';
import '../services/device_registration_manager.dart';
import '../services/secure_storage.dart';
import '../services/security_settings_manager.dart';
import '../providers/history_provider.dart';
import '../models/crypto_token.dart';
import 'crypto_details_screen.dart';
import '../providers/app_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:my_flutter_app/providers/price_provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart'; // Added import for APIService
import 'package:shared_preferences/shared_preferences.dart'; // Added import for SharedPreferences
import 'dart:convert'; // Added import for json

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isHidden = false;
  int selectedTab = 0;
  bool _isRefreshing = false; // جلوگیری از concurrent refresh
  Map<String, double> _cachedBalances = {}; // کش موجودی‌ها
  Map<String, double> _displayBalances = {}; // موجودی‌های نمایشی
  
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

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
    _loadCachedBalances(); // بارگذاری کش موجودی‌ها از SharedPreferences
    _initializeHomeScreen();
  }

  Future<void> _initializeHomeScreen() async {
    print('🏠 HomeScreen: Starting initialization...');
    
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // Initialize SecuritySettingsManager
      await _securityManager.initialize();
      print('🏠 HomeScreen: Security manager initialized');
      
      // Initialize price provider
      await priceProvider.loadSelectedCurrency();
      print('🏠 HomeScreen: Price provider currency loaded');
      
      // بلافاصله نمایش صفحه با cached data
      // UI will be shown immediately when AppProvider is ready
      
      // Register device in background
      _registerDeviceOnHome();
      print('🏠 HomeScreen: Device registration started');
      
      // Background data loading - بدون await
      _loadDataInBackground(appProvider, priceProvider);
      
      // شروع periodic updates در background
      _startPeriodicUpdates();
      
    } catch (e) {
      print('❌ HomeScreen: Error initializing: $e');
      // UI will still be shown even if initialization fails
    }
  }
  
  /// بارگذاری داده‌ها در background بدون مسدود کردن UI
  Future<void> _loadDataInBackground(AppProvider appProvider, PriceProvider priceProvider) async {
    print('🔄 HomeScreen: Loading data in background...');
    
    try {
      if (appProvider.tokenProvider != null) {
        final enabledTokens = appProvider.tokenProvider!.enabledTokens;
        
        if (enabledTokens.isNotEmpty) {
          // ابتدا موجودی‌های cached را نمایش بده
          _applyCachedBalancesToTokens(enabledTokens);
          
          // بارگذاری موجودی‌ها و قیمت‌ها به صورت موازی در background
          await Future.wait<void>([
            // دریافت موجودی‌های فوری
            _loadBalancesForEnabledTokens(appProvider.tokenProvider!),
            // دریافت قیمت‌های فوری
            _loadPricesForTokens(enabledTokens, priceProvider),
          ]);
        }
        
        print('✅ HomeScreen: Background data loading completed');
      }
    } catch (e) {
      print('❌ HomeScreen: Error loading data in background: $e');
    }
  }

  /// اعمال موجودی‌های cached به توکن‌ها
  void _applyCachedBalancesToTokens(List<CryptoToken> tokens) {
    try {
      for (final token in tokens) {
        final cachedBalance = _cachedBalances[token.symbol ?? ''];
        if (cachedBalance != null && cachedBalance > 0) {
          // فقط اگر token.amount صفر باشد، از cached balance استفاده کن
          if (token.amount <= 0) {
            _displayBalances[token.symbol ?? ''] = cachedBalance;
            print('📦 HomeScreen: Applied cached balance for ${token.symbol}: $cachedBalance');
          } else {
            // اگر token.amount موجود باشد، آن را به عنوان display balance استفاده کن
            _displayBalances[token.symbol ?? ''] = token.amount;
            print('📦 HomeScreen: Applied actual balance for ${token.symbol}: ${token.amount}');
          }
        }
      }
    } catch (e) {
      print('❌ HomeScreen: Error applying cached balances: $e');
    }
  }

  /// بارگذاری موجودی‌ها برای توکن‌های فعال با cache
  Future<void> _loadBalancesForEnabledTokens(tokenProvider) async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing balances, skipping...');
      return;
    }
    
    _isRefreshing = true;
    
    try {
      print('💰 HomeScreen: Loading balances for enabled tokens');
      
      // ذخیره موجودی‌های فعلی به عنوان backup
      final currentTokens = tokenProvider.enabledTokens;
      for (final token in currentTokens) {
        if (token.amount > 0) {
          _cachedBalances[token.symbol ?? ''] = token.amount;
        }
      }
      
      // تلاش برای به‌روزرسانی موجودی با timeout
      final success = await tokenProvider.updateBalance().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⚠️ HomeScreen: Balance update timeout');
          return false;
        },
      );
      
      if (success) {
        print('✅ HomeScreen: Balances loaded successfully');
        // به‌روزرسانی کش با موجودی‌های جدید
        for (final token in tokenProvider.enabledTokens) {
          if (token.amount > 0) {
            _cachedBalances[token.symbol ?? ''] = token.amount;
            _displayBalances[token.symbol ?? ''] = token.amount;
          }
        }
        // ذخیره کش در SharedPreferences
        await _saveCachedBalances();
      } else {
        print('⚠️ HomeScreen: Failed to load balances, using cached values');
        // بازگردانی موجودی‌ها از کش
        _restoreBalancesFromCache(tokenProvider);
      }
      
    } catch (e) {
      print('❌ HomeScreen: Error loading balances: $e');
      // بازگردانی موجودی‌ها از کش در صورت خطا
      _restoreBalancesFromCache(tokenProvider);
    } finally {
      _isRefreshing = false;
    }
  }

  /// بازگردانی موجودی‌ها از کش
  void _restoreBalancesFromCache(tokenProvider) {
    try {
      final tokens = tokenProvider.enabledTokens;
      for (final token in tokens) {
        final cachedBalance = _cachedBalances[token.symbol ?? ''];
        if (cachedBalance != null && cachedBalance > 0) {
          // استفاده از _displayBalances بجای تغییر مستقیم token.amount
          _displayBalances[token.symbol ?? ''] = cachedBalance;
          print('📦 HomeScreen: Restored ${token.symbol} balance from cache: $cachedBalance');
        }
      }
      // Force UI update
      setState(() {});
    } catch (e) {
      print('❌ HomeScreen: Error restoring balances from cache: $e');
    }
  }

  // _loadPricesForEnabledTokens removed - use _loadPricesForTokens directly

  Future<void> _loadPricesForTokens(List<CryptoToken> tokens, PriceProvider priceProvider) async {
    if (tokens.isEmpty) return;
    
    print('🔄 HomeScreen: Loading prices for ${tokens.length} tokens');
    
    // Get symbols from actual loaded tokens only
    final tokenSymbols = tokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
    
    if (tokenSymbols.isEmpty) {
      print('⚠️ HomeScreen: No valid token symbols found');
      return;
    }
    
    // Fetch prices only for selected currency (for performance)
    final selectedCurrency = priceProvider.selectedCurrency;
    final currencies = [selectedCurrency];
    
    print('🔄 HomeScreen: Fetching prices for symbols: $tokenSymbols (currency: $selectedCurrency)');
    await priceProvider.fetchPrices(tokenSymbols, currencies: currencies);
    print('✅ HomeScreen: Prices loaded successfully');
  }

  /// شروع periodic updates برای wallet استاندارد
  void _startPeriodicUpdates() {
    // هر 60 ثانیه قیمت‌ها را به‌روزرسانی کن (فقط قیمت‌ها، نه موجودی‌ها)
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) {
        _refreshPricesForEnabledTokens();
        _startPeriodicUpdates(); // recursive call for continuous updates
      }
    });
  }

  /// تنظیم مجدد کش موجودی‌ها در صورت مشکل
  void _resetBalanceCache() {
    _cachedBalances.clear();
    _displayBalances.clear();
    _saveCachedBalances();
    print('🔄 HomeScreen: Balance cache reset');
  }

  /// refresh امن فقط قیمت‌ها بدون تغییر موجودی‌ها
  Future<void> _safeRefreshPricesOnly() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      if (appProvider.tokenProvider != null) {
        final enabledTokens = appProvider.tokenProvider!.enabledTokens;
        if (enabledTokens.isNotEmpty) {
          await _loadPricesForTokens(enabledTokens, priceProvider);
          print('✅ HomeScreen: Safe prices-only refresh completed');
        }
      }
    } catch (e) {
      print('❌ HomeScreen: Error in safe prices-only refresh: $e');
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ذخیره کش موجودی‌ها قبل از dispose
    _saveCachedBalances();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused) {
      // Save background time when app goes to background
      _securityManager.saveLastBackgroundTime();
    } else if (state == AppLifecycleState.resumed) {
      // هنگام بازگشت به اپ، فوراً balance و قیمت‌ها را به‌روزرسانی کن
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performFullRefresh();
        
        // iOS-specific: Handle token state recovery
        _handleiOSAppResume();
      });
    }
  }

  /// iOS-specific: Handle app resume to recover token states
  Future<void> _handleiOSAppResume() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider != null) {
        await tokenProvider.handleiOSAppResume();
        print('🍎 HomeScreen: iOS app resume handling completed');
      }
    } catch (e) {
      print('❌ HomeScreen: Error handling iOS app resume: $e');
    }
  }

  /// refresh کامل برای بازگشت به اپ
  Future<void> _performFullRefresh() async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing, skipping full refresh...');
      return;
    }
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    final enabledTokens = appProvider.tokenProvider!.enabledTokens;
    if (enabledTokens.isEmpty) return;
    
    try {
      // فقط قیمت‌ها را refresh کن، موجودی‌ها فقط اگر لازم باشد
      await _loadPricesForTokens(enabledTokens, priceProvider);
      
      // موجودی‌ها را فقط اگر کش خالی باشد یا قدیمی باشد
      if (_cachedBalances.isEmpty || _shouldUpdateBalances()) {
        await _loadBalancesForEnabledTokens(appProvider.tokenProvider!);
      }
    } catch (e) {
      print('❌ HomeScreen: Error in full refresh: $e');
    }
  }

  /// چک کن که آیا باید موجودی‌ها را به‌روزرسانی کرد
  bool _shouldUpdateBalances() {
    // فقط در صورت خالی بودن کش یا اگر کش خیلی قدیمی باشد
    return _cachedBalances.isEmpty;
  }

  void _refreshPricesForEnabledTokens() async {
    await _safeRefreshPricesOnly();
  }

  /// refresh با balance update برای دکمه refresh
  Future<void> _performManualRefresh() async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing, skipping manual refresh...');
      return;
    }
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    try {
      // موازی: refresh موجودی‌ها و قیمت‌ها - اما فقط برای توکن‌های فعال
      final enabledTokens = appProvider.tokenProvider!.enabledTokens;
      if (enabledTokens.isEmpty) return;
      
      await Future.wait<void>([
        _loadBalancesForEnabledTokens(appProvider.tokenProvider!), // استفاده از متد cache دار
        _loadPricesForTokens(enabledTokens, priceProvider),
      ]);
      
      return; // success
    } catch (e) {
      print('❌ HomeScreen: Error in manual refresh: $e');
      rethrow; // re-throw for UI handling
    }
  }

  /// refresh فوری بعد از تغییر توکن‌ها
  Future<void> _performImmediateRefreshAfterTokenChange() async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing, skipping immediate refresh...');
      return;
    }
    
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    
    if (appProvider.tokenProvider == null) return;
    
    try {
      print('⚡ HomeScreen: Performing immediate refresh after token change');
      
      // Get newly enabled tokens
      final enabledTokens = appProvider.tokenProvider!.enabledTokens;
      print('⚡ HomeScreen: Current enabled tokens: ${enabledTokens.map((t) => t.symbol).toList()}');
      
      if (enabledTokens.isEmpty) {
        print('⚠️ HomeScreen: No enabled tokens, skipping refresh');
        return;
      }
      
      // موازی: دریافت موجودی‌ها و قیمت‌ها برای تمام توکن‌های فعال
      await Future.wait<void>([
        // دریافت موجودی‌های جدید با cache
        _loadBalancesForEnabledTokens(appProvider.tokenProvider!),
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
          _updateSingleTokenBalanceWithCache(token, appProvider.tokenProvider!),
          _fetchTokenPrice(token, priceProvider),
        ]);
        
        print('✅ HomeScreen: Token ${token.symbol} reactivated with fresh data');
      }
    } catch (e) {
      print('❌ HomeScreen: Error reactivating token ${token.symbol}: $e');
    }
  }

  /// به‌روزرسانی موجودی یک توکن با استفاده از کش
  Future<void> _updateSingleTokenBalanceWithCache(CryptoToken token, tokenProvider) async {
    try {
      final success = await tokenProvider.updateSingleTokenBalance(token).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('⚠️ HomeScreen: Single token balance update timeout for ${token.symbol}');
          return false;
        },
      );
      
      if (success && token.amount > 0) {
        // به‌روزرسانی کش
        _cachedBalances[token.symbol ?? ''] = token.amount;
        _displayBalances[token.symbol ?? ''] = token.amount;
        print('📦 HomeScreen: Updated cache for ${token.symbol}: ${token.amount}');
        // ذخیره کش در SharedPreferences
        await _saveCachedBalances();
      } else {
        // بازگردانی از کش
        final cachedBalance = _cachedBalances[token.symbol ?? ''];
        if (cachedBalance != null && cachedBalance > 0) {
          _displayBalances[token.symbol ?? ''] = cachedBalance;
          print('📦 HomeScreen: Restored ${token.symbol} from cache: $cachedBalance');
        }
      }
      setState(() {});
    } catch (e) {
      print('❌ HomeScreen: Error updating single token balance: $e');
      // بازگردانی از کش در صورت خطا
      final cachedBalance = _cachedBalances[token.symbol ?? ''];
      if (cachedBalance != null && cachedBalance > 0) {
        _displayBalances[token.symbol ?? ''] = cachedBalance;
        print('📦 HomeScreen: Restored ${token.symbol} from cache after error: $cachedBalance');
      }
      setState(() {});
    }
  }

  /// دریافت قیمت برای یک توکن خاص
  Future<void> _fetchTokenPrice(CryptoToken token, PriceProvider priceProvider) async {
    try {
      final symbol = token.symbol ?? '';
      if (symbol.isNotEmpty) {
        final selectedCurrency = priceProvider.selectedCurrency;
        await priceProvider.fetchPrices([symbol], currencies: [selectedCurrency]);
      }
    } catch (e) {
      print('❌ HomeScreen: Error fetching price for ${token.symbol}: $e');
    }
  }

  /// بارگذاری کش موجودی‌ها از SharedPreferences
  Future<void> _loadCachedBalances() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedBalancesJson = prefs.getString('cached_balances');
      
      if (cachedBalancesJson != null) {
        final Map<String, dynamic> decoded = json.decode(cachedBalancesJson);
        _cachedBalances = decoded.map((key, value) => MapEntry(key, value.toDouble()));
        // همچنین display balances را initialize کن
        _displayBalances = Map.from(_cachedBalances);
        print('📦 HomeScreen: Loaded cached balances: $_cachedBalances');
      }
    } catch (e) {
      print('❌ HomeScreen: Error loading cached balances: $e');
    }
  }

  /// ذخیره کش موجودی‌ها در SharedPreferences
  Future<void> _saveCachedBalances() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedBalances = json.encode(_cachedBalances);
      await prefs.setString('cached_balances', encodedBalances);
      print('📦 HomeScreen: Saved cached balances: $_cachedBalances');
    } catch (e) {
      print('❌ HomeScreen: Error saving cached balances: $e');
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

  // Debug API calls removed for performance optimization

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
    // Remove modal bottom sheet - wallet selection removed
  }

  // Debug API test removed for performance optimization

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // خروج از اپلیکیشن بجای برگشت به صفحه قبل
        SystemNavigator.pop();
        return false;
      },
      child: Consumer<AppProvider>(
        builder: (context, appProvider, _) {
        // Show loading only if AppProvider is not initialized yet
        if (appProvider.tokenProvider == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _safeTranslate('loading_wallet', 'Loading wallet...'),
                      style: const TextStyle(color: Color(0xFF666666)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final walletName = appProvider.currentWalletName ?? _safeTranslate('my_wallet', 'My Wallet');
        final tokenProvider = appProvider.tokenProvider!;
        
        // Wait for TokenProvider to be fully initialized
        if (tokenProvider.isLoading || 
            (!tokenProvider.isFullyReady && tokenProvider.enabledTokens.isEmpty)) {
          
          // Debug current state
          print('🏠 HomeScreen: TokenProvider not ready yet');
          tokenProvider.debugCurrentState();
          
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _safeTranslate('initializing_wallet', 'Initializing wallet...'),
                      style: const TextStyle(color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _safeTranslate('loading_tokens', 'Loading your tokens...'),
                      style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        // Debug final state
        print('🏠 HomeScreen: TokenProvider is ready, rendering UI');
        tokenProvider.debugCurrentState();
        
        // Additional debug: Check token preferences state
        WidgetsBinding.instance.addPostFrameCallback((_) {
          tokenProvider.debugTokenPreferences();
        });
        
        // Pre-cache logos when tokens are available (but don't wait for it)
        if (tokenProvider.enabledTokens.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            preCacheTokenLogos(tokenProvider.enabledTokens);
          });
        }
        
        // Show loading indicator if TokenProvider is still loading and has no tokens
        if (tokenProvider.isLoading && tokenProvider.enabledTokens.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _safeTranslate('initializing_wallet', 'Initializing wallet...'),
                      style: const TextStyle(color: Color(0xFF666666)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _safeTranslate('please_wait', 'Please wait...'),
                      style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        // Show "Add Token" screen only if loading is complete and no tokens found
        if (!tokenProvider.isLoading && tokenProvider.enabledTokens.isEmpty) {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/add-token'),
                          child: Text(_safeTranslate('add_token', 'Add Token')),
                        ),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: () async {
                            // Force refresh TokenProvider
                            await tokenProvider.forceRefresh();
                            // Also ensure synchronization
                            await tokenProvider.ensureTokensSynchronized();
                          },
                          child: Text(_safeTranslate('refresh', 'Refresh')),
                        ),
                      ],
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
                  // Loading indicator for background tasks
                  if (tokenProvider.isLoading)
                    Container(
                      height: 3,
                      child: const LinearProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                        backgroundColor: Color(0xFFE0E0E0),
                      ),
                    ),
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
                              return RefreshIndicator(
                                onRefresh: _performManualRefresh,
                                color: const Color(0xFF0BAB9B),
                                child: ListView.separated(
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
                                          displayAmount: _getDisplayAmount(token),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          )
                        : RefreshIndicator(
                            onRefresh: _performManualRefresh,
                            color: const Color(0xFF0BAB9B),
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Container(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: _NFTEmptyWidget(_safeTranslate('no_nft_found', 'No NFT Found')),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    )
);  }


  /// محاسبه کل ارزش توکن‌ها با استفاده از PriceProvider
  double _calculateTotalValue(List<CryptoToken> tokens, PriceProvider priceProvider) {
    double total = 0.0;
    for (final token in tokens) {
      final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
      // استفاده از موجودی نمایشی
      final amount = _getDisplayAmount(token);
      final value = amount * price;
      total += value;
    }
    return total;
  }

  /// دریافت موجودی نمایشی برای یک توکن
  double _getDisplayAmount(CryptoToken token) {
    final symbol = token.symbol ?? '';
    // اولویت: display balance, سپس actual amount, سپس cached balance
    return _displayBalances[symbol] ?? 
           (token.amount > 0 ? token.amount : (_cachedBalances[symbol] ?? 0.0));
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
  final double displayAmount;
  
  const _TokenRow({
    required this.token,
    required this.isHidden,
    this.tokenLogoCacheManager,
    required this.price,
    required this.displayAmount,
  });

  @override
  Widget build(BuildContext context) {
    // استفاده از موجودی نمایشی که از parent دریافت شده
    final tokenValue = displayAmount * price;
    
    // Helper for formatting
    final amountFormat = NumberFormat('#,##0.####');
    
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
          // Token icon - fixed to prevent cropping
          assetIcon != null
              ? Image.asset(
                  assetIcon,
                  width: 30,
                  height: 30,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                )
              : (token.iconUrl ?? '').startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: token.iconUrl ?? '',
                      width: 30,
                      height: 30,
                      cacheManager: tokenLogoCacheManager,
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    )
                  : (token.iconUrl ?? '').startsWith('assets/')
                      ? Image.asset(
                          token.iconUrl ?? '',
                          width: 30,
                          height: 30,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                        )
                      : const Icon(Icons.error),
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
              Text(isHidden ? '****' : amountFormat.format(displayAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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