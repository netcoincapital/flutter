import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:io';
import '../layout/main_layout.dart';
import '../services/device_registration_manager.dart';
import '../services/secure_storage.dart';
import '../services/security_settings_manager.dart';
import '../services/balance_manager.dart';
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
import '../widgets/stable_balance_display.dart';
import '../services/balance_debug_helper.dart';
import '../screens/wallets_screen.dart'; // Added import for WalletsScreen
import '../utils/shared_preferences_utils.dart'; // Added import for formatAmount
import 'dart:async'; // Added import for Timer
import '../services/wallet_state_manager.dart'; // Added import for WalletStateManager

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isHidden = false;
  int selectedTab = 0;
  bool _isRefreshing = false; // جلوگیری از concurrent refresh

  // ✅ Remove global cache - now handled per-wallet in AppProvider/WalletStateManager
  // Map<String, double> _cachedBalances = {}; // ❌ Removed global cache
  // Map<String, double> _displayBalances = {}; // ❌ Removed global display cache

  int _debugTapCount = 0; // شمارنده تپ برای debug مخفی

  // Sort and filter options
  String _sortOption = 'balance'; // 'balance', 'name', 'price'
  bool _hideZeroBalances = false;
  bool _showOnlyEnabled = false;
  List<String> _selectedBlockchains = [];

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

    // Listen to BalanceManager updates for UI refresh
    BalanceManager.instance.addListener(_onBalanceManagerUpdate);

    // ✅ Remove global cache loading - now handled per-wallet
    // _loadCachedBalances(); // ❌ Removed
    _initializeHomeScreen();
  }

  void _onBalanceManagerUpdate() {
    if (mounted) {
      setState(() {
        // This will trigger a rebuild with updated balance data
      });
    }
  }

  Future<void> _initializeHomeScreen() async {
    print('🏠 HomeScreen: Starting initialization...');

    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);

      // Initialize SecuritySettingsManager
      await _securityManager.initialize();
      print('🏠 HomeScreen: Security manager initialized');

      // Initialize BalanceManager
      await BalanceManager.instance.initialize(appProvider.apiService);
      print('🏠 HomeScreen: BalanceManager initialized');

      // Set current user and wallet context for BalanceManager
      // Use immediate setup if possible, otherwise delay briefly
      if (appProvider.currentUserId != null && appProvider.currentWalletName != null) {
        Timer(const Duration(milliseconds: 300), () async {
          await BalanceManager.instance.setCurrentUserAndWallet(
            appProvider.currentUserId!,
            appProvider.currentWalletName!,
          );
          print('🏠 HomeScreen: BalanceManager context set for user: ${appProvider.currentUserId}');

          // Force UI refresh after BalanceManager is ready
          if (mounted) {
            setState(() {});
          }
        });
      } else {
        // If no current user yet, try again after a longer delay
        Timer(const Duration(milliseconds: 1000), () async {
          if (appProvider.currentUserId != null && appProvider.currentWalletName != null) {
            await BalanceManager.instance.setCurrentUserAndWallet(
              appProvider.currentUserId!,
              appProvider.currentWalletName!,
            );
            print('🏠 HomeScreen: BalanceManager context set (delayed) for user: ${appProvider.currentUserId}');

            // Force UI refresh after BalanceManager is ready
            if (mounted) {
              setState(() {});
            }
          }
        });
      }

      // Initialize price provider
      await priceProvider.loadSelectedCurrency();
      print('🏠 HomeScreen: Price provider currency loaded');

      // بلافاصله قیمت‌ها را بارگذاری کن (همزمان با UI loading)
      final tokenProvider = appProvider.tokenProvider;
      if (tokenProvider != null) {
        final enabledTokens = tokenProvider.enabledTokens;
        print('🏠 HomeScreen: TokenProvider available, enabled tokens count: ${enabledTokens.length}');
        if (enabledTokens.isNotEmpty) {
          print('🏠 HomeScreen: Loading prices immediately for enabled tokens: ${enabledTokens.map((t) => t.symbol).toList()}');
          _loadPricesForTokens(enabledTokens, priceProvider).then((_) {
            print('✅ HomeScreen: Initial prices loaded successfully');
          }).catchError((e) {
            print('❌ HomeScreen: Error loading initial prices: $e');
          });
        } else {
          print('⚠️ HomeScreen: No enabled tokens found for price loading');
        }
      } else {
        print('⚠️ HomeScreen: TokenProvider is null, will wait for background loading');
        // اگر TokenProvider هنوز آماده نیست، از AppProvider listener استفاده کن
        appProvider.addListener(() {
          final tp = appProvider.tokenProvider;
          if (tp != null && tp.enabledTokens.isNotEmpty && mounted) {
            print('🏠 HomeScreen: TokenProvider became ready, loading prices now');
            _loadPricesForTokens(tp.enabledTokens, priceProvider).then((_) {
              print('✅ HomeScreen: Delayed prices loaded successfully');
            }).catchError((e) {
              print('❌ HomeScreen: Error loading delayed prices: $e');
            });
            appProvider.removeListener(() {}); // Remove this specific listener
          }
        });
      }

      // Register device in background
      _registerDeviceOnHome();
      print('🏠 HomeScreen: Device registration started');

      // Background data loading - بدون await (برای موجودی‌ها)
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
          // _applyCachedBalancesToTokens(enabledTokens); // ❌ Removed global apply

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

  // ✅ Cached balance application is now handled per-wallet in AppProvider
  // No longer needed as balances are managed per-wallet through WalletStateManager

  /// بارگذاری موجودی‌ها برای توکن‌های فعال با BalanceManager
  Future<void> _loadBalancesForEnabledTokens(tokenProvider) async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing balances, skipping...');
      return;
    }

    _isRefreshing = true;

    try {
      print('💰 HomeScreen: Loading balances for enabled tokens using BalanceManager');

      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final currentUserId = appProvider.currentUserId;

      if (currentUserId != null && currentUserId.isNotEmpty) {
        // Set active tokens for the current user in BalanceManager
        final enabledTokens = tokenProvider.enabledTokens;
        final activeSymbols = enabledTokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();

        BalanceManager.instance.setActiveTokensForUser(currentUserId, activeSymbols);
        print('🔄 HomeScreen: Set ${activeSymbols.length} active tokens in BalanceManager');

        // Check if we have cached balances first
        final upToDate = BalanceManager.instance.areBalancesUpToDate(currentUserId);
        if (!upToDate) {
          // Only refresh if we don't have recent cached data
          print('🔄 HomeScreen: No recent cached balances, refreshing...');
          await BalanceManager.instance.refreshBalancesForUser(currentUserId, force: false);
          print('✅ HomeScreen: BalanceManager refresh completed');
        } else {
          print('✅ HomeScreen: Using cached balances (still valid)');
        }

      } else {
        print('⚠️ HomeScreen: No valid user ID found for balance loading');
      }

      // Debug: نمایش موجودی‌های فعلی
      final enabledTokens = tokenProvider.enabledTokens;
      print('🔍 HomeScreen DEBUG: Current enabled tokens with balances:');
      for (final token in enabledTokens) {
        final balanceFromManager = currentUserId != null
            ? BalanceManager.instance.getTokenBalance(currentUserId, token.symbol ?? '')
            : 0.0;
        final displayAmount = _getDisplayAmount(token);
        print('   - ${token.symbol}: Manager=${balanceFromManager}, Token=${token.amount ?? 0.0}, Display=${displayAmount}');
      }

      // Also debug BalanceManager state
      BalanceManager.instance.debugBalanceState();

      // Full debug check
      BalanceDebugHelper.debugFullBalanceState(appProvider);

      // Emergency fix: if all display amounts are 0, force a refresh
      final allZero = enabledTokens.every((token) => _getDisplayAmount(token) == 0.0);
      if (allZero && enabledTokens.isNotEmpty && currentUserId != null) {
        print('🚨 HomeScreen: All balances are zero, forcing emergency refresh...');
        Timer(const Duration(milliseconds: 500), () async {
          try {
            await BalanceManager.instance.refreshBalancesForUser(currentUserId, force: true);
            if (mounted) setState(() {});
          } catch (e) {
            print('❌ Emergency refresh failed: $e');
          }
        });
      }

    } catch (e) {
      print('❌ HomeScreen: Error loading balances: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  // ✅ Balance restoration is now handled per-wallet in AppProvider
  // Cached balances are automatically restored when selecting wallets

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
  Timer? _periodicTimer;

  void _startPeriodicUpdates() {
    // Cancel existing timer if any
    _periodicTimer?.cancel();

    // هر 90 ثانیه قیمت‌ها و موجودی‌ها را به‌روزرسانی کن برای پایداری
    _periodicTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      if (mounted) {
        _refreshPricesAndBalances();
      } else {
        // If widget is disposed, cancel the timer
        timer.cancel();
      }
    });
  }

  void _stopPeriodicUpdates() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// تنظیم مجدد کش موجودی‌ها در صورت مشکل
  void _resetBalanceCache() {
    // _cachedBalances.clear(); // ❌ Removed global cache
    // _displayBalances.clear(); // ❌ Removed global cache
    // _saveCachedBalances(); // ❌ Removed global cache
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

    // Remove BalanceManager listener
    BalanceManager.instance.removeListener(_onBalanceManagerUpdate);

    // ✅ Save current wallet's balance cache automatically through AppProvider
    // This is handled automatically when the app goes to background or switches context

    _stopPeriodicUpdates(); // Stop periodic updates on dispose
    super.dispose();
  }

  /// نمایش گزینه‌های مرتب‌سازی
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11c699).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sort,
                      color: Color(0xFF11c699),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _safeTranslate('sort by', 'Sort by'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),

            // Sort options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _SortOption(
                    title: _safeTranslate('balance', 'Balance'),
                    subtitle: _safeTranslate('highest to lowest', 'Highest to lowest'),
                    value: 'balance',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      Navigator.pop(context);
                    },
                  ),
                  _SortOption(
                    title: _safeTranslate('name', 'Name'),
                    subtitle: _safeTranslate('alphabetical order', 'A-Z alphabetical'),
                    value: 'name',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      Navigator.pop(context);
                    },
                  ),
                  _SortOption(
                    title: _safeTranslate('price', 'Price'),
                    subtitle: _safeTranslate('highest price first', 'Highest price first'),
                    value: 'price',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // Additional filter state
  double _minBalanceFilter = 0.0;
  String _balanceFilterType = 'all'; // 'all', 'above', 'range'

  /// نمایش گزینه‌های فیلتر
  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11c699).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.tune,
                        color: Color(0xFF11c699),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _safeTranslate('filter tokens', 'Filter Tokens'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          _hideZeroBalances = false;
                          _showOnlyEnabled = false;
                          _selectedBlockchains.clear();
                          _minBalanceFilter = 0.0;
                          _balanceFilterType = 'all';
                        });
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: Text(_safeTranslate('clear all', 'Clear All')),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF11c699),
                        textStyle: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Balance filters with visual slider
                      _buildAdvancedFilterSection(
                        title: _safeTranslate('balance filter', 'Balance Filter'),
                        icon: Icons.account_balance_wallet,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildToggleOption(
                              title: _safeTranslate('hide zero balances', 'Hide Zero Balances'),
                              subtitle: _safeTranslate('show only tokens with balance', 'Show only tokens with balance'),
                              value: _hideZeroBalances,
                              onChanged: (value) {
                                setModalState(() => _hideZeroBalances = value);
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildToggleOption(
                              title: _safeTranslate('show only enabled tokens', 'Show Only Enabled Tokens'),
                              subtitle: _safeTranslate('tokens you have enabled', 'Tokens you have enabled'),
                              value: _showOnlyEnabled,
                              onChanged: (value) {
                                setModalState(() => _showOnlyEnabled = value);
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 20),

                            // Advanced balance filter
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _safeTranslate('minimum display value', 'Minimum Display Value'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _safeTranslate('tokens below value hidden', 'Tokens with value below this amount will be hidden'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Quick preset buttons
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildPresetButton(_safeTranslate('all', 'All'), 0.0, setModalState),
                                      _buildPresetButton('\$1+', 1.0, setModalState),
                                      _buildPresetButton('\$10+', 10.0, setModalState),
                                      _buildPresetButton('\$100+', 100.0, setModalState),
                                      _buildPresetButton('\$1000+', 1000.0, setModalState),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Custom slider
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '\$${_minBalanceFilter.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF11c699),
                                              ),
                                            ),
                                            Text(
                                              '\$10,000',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                        SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 6,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                                            activeTrackColor: const Color(0xFF11c699),
                                            inactiveTrackColor: Colors.grey.withOpacity(0.3),
                                            thumbColor: const Color(0xFF11c699),
                                            overlayColor: const Color(0xFF11c699).withOpacity(0.2),
                                          ),
                                          child: Slider(
                                            value: _minBalanceFilter,
                                            min: 0,
                                            max: 10000,
                                            divisions: 100,
                                            onChanged: (value) {
                                              setModalState(() => _minBalanceFilter = value);
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Blockchain filters with chips
                      _buildAdvancedFilterSection(
                        title: _safeTranslate('blockchain networks', 'Blockchain Networks'),
                        icon: Icons.account_tree,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Bitcoin',
                            'Ethereum',
                            'Binance Smart Chain',
                            'Polygon',
                            'Arbitrum',
                            'Avalanche'
                          ].map((blockchain) => _buildBlockchainChip(
                            label: blockchain,
                            isSelected: _selectedBlockchains.contains(blockchain),
                            onTap: () {
                              setModalState(() {
                                if (_selectedBlockchains.contains(blockchain)) {
                                  _selectedBlockchains.remove(blockchain);
                                } else {
                                  _selectedBlockchains.add(blockchain);
                                }
                              });
                              setState(() {});
                            },
                          )).toList(),
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // Apply button
              Container(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF11c699),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _safeTranslate('apply filters', 'Apply Filters'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedFilterSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF11c699)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  Widget _buildToggleOption({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF11c699).withOpacity(0.1) : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: value ? const Color(0xFF11c699) : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF11c699),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, double value, StateSetter setModalState) {
    final isSelected = _minBalanceFilter == value;
    return GestureDetector(
      onTap: () {
        setModalState(() => _minBalanceFilter = value);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockchainChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  /// اعمال فیلترها به لیست tokens
  List<CryptoToken> _applyFilters(List<CryptoToken> tokens, PriceProvider priceProvider) {
    var filteredTokens = tokens;

    // Filter by zero balances
    if (_hideZeroBalances) {
      filteredTokens = filteredTokens.where((token) => (token.amount ?? 0.0) > 0).toList();
    }

    // Filter by enabled status
    if (_showOnlyEnabled) {
      filteredTokens = filteredTokens.where((token) => token.isEnabled).toList();
    }

    // Filter by minimum balance value
    if (_minBalanceFilter > 0) {
      filteredTokens = filteredTokens.where((token) {
        final tokenAmount = token.amount ?? 0.0;
        final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
        final totalValue = tokenAmount * price;
        return totalValue >= _minBalanceFilter;
      }).toList();
    }

    // Filter by blockchain
    if (_selectedBlockchains.isNotEmpty) {
      filteredTokens = filteredTokens.where((token) =>
          _selectedBlockchains.contains(token.blockchainName)
      ).toList();
    }

    return filteredTokens;
  }

  /// اعمال مرتب‌سازی به لیست tokens
  List<CryptoToken> _applySorting(List<CryptoToken> tokens, PriceProvider priceProvider) {
    var sortedTokens = List<CryptoToken>.from(tokens);

    switch (_sortOption) {
      case 'balance':
        sortedTokens.sort((a, b) {
          final aBalance = a.amount ?? 0.0;
          final bBalance = b.amount ?? 0.0;
          return bBalance.compareTo(aBalance); // Descending
        });
        break;

      case 'name':
        sortedTokens.sort((a, b) {
          final aName = a.name ?? a.symbol ?? '';
          final bName = b.name ?? b.symbol ?? '';
          return aName.toLowerCase().compareTo(bName.toLowerCase()); // Ascending
        });
        break;

      case 'price':
        sortedTokens.sort((a, b) {
          final aPrice = priceProvider.getPrice(a.symbol ?? '') ?? 0.0;
          final bPrice = priceProvider.getPrice(b.symbol ?? '') ?? 0.0;
          return bPrice.compareTo(aPrice); // Descending
        });
        break;
    }

    return sortedTokens;
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

      // موجودی‌ها را فقط اگر لازم باشد
      if (_shouldUpdateBalances()) {
        await _loadBalancesForEnabledTokens(appProvider.tokenProvider!);
      }
    } catch (e) {
      print('❌ HomeScreen: Error in full refresh: $e');
    }
  }

  /// چک کن که آیا باید موجودی‌ها را به‌روزرسانی کرد
  bool _shouldUpdateBalances() {
    // Always update balances as we use per-wallet cache now
    return true;
  }

  void _refreshPricesForEnabledTokens() async {
    await _safeRefreshPricesOnly();
  }

  /// Refresh هم قیمت‌ها و هم موجودی‌ها برای پایداری
  void _refreshPricesAndBalances() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      final currentUserId = appProvider.currentUserId;

      if (appProvider.tokenProvider != null && currentUserId != null) {
        final enabledTokens = appProvider.tokenProvider!.enabledTokens;

        if (enabledTokens.isNotEmpty) {
          print('🔄 HomeScreen: Periodic refresh - updating prices and balances');

          // Refresh prices
          await _loadPricesForTokens(enabledTokens, priceProvider);

          // Refresh balances through BalanceManager
          await BalanceManager.instance.refreshBalancesForUser(currentUserId, force: false);

          print('✅ HomeScreen: Periodic refresh completed');
        }
      }
    } catch (e) {
      print('❌ HomeScreen: Error in periodic refresh: $e');
    }
  }

  /// refresh با balance update برای دکمه refresh
  Future<void> _performManualRefresh() async {
    if (_isRefreshing) {
      print('⏳ HomeScreen: Already refreshing, skipping manual refresh...');
      return;
    }

    _isRefreshing = true;
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    final currentUserId = appProvider.currentUserId;

    if (appProvider.tokenProvider == null) return;

    try {
      print('🔄 HomeScreen: Manual refresh started');

      final enabledTokens = appProvider.tokenProvider!.enabledTokens;
      if (enabledTokens.isEmpty) return;

      // موازی: refresh موجودی‌ها و قیمت‌ها
      await Future.wait<void>([
        // Force refresh balances through BalanceManager
        if (currentUserId != null)
          BalanceManager.instance.refreshBalancesForUser(currentUserId, force: true),
        // Refresh prices
        _loadPricesForTokens(enabledTokens, priceProvider),
      ]);

      print('✅ HomeScreen: Manual refresh completed successfully');

    } catch (e) {
      print('❌ HomeScreen: Error in manual refresh: $e');
      rethrow; // re-throw for UI handling
    } finally {
      _isRefreshing = false;
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

  /// به‌روزرسانی موجودی یک توکن با per-wallet caching
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
        print('✅ HomeScreen: Updated balance for ${token.symbol}: ${token.amount}');

        // ✅ Save updated balance per-wallet automatically
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        if (appProvider.currentWalletName != null && appProvider.currentUserId != null) {
          final balanceCache = {token.symbol ?? '': token.amount};

          // Get existing cache and update
          final existingCache = await SecureStorage.instance.getWalletBalanceCache(
              appProvider.currentWalletName!,
              appProvider.currentUserId!
          );
          existingCache.addAll(balanceCache);

          await WalletStateManager.instance.saveBalanceCacheForWallet(
              appProvider.currentWalletName!,
              appProvider.currentUserId!,
              existingCache
          );
        }

      } else {
        print('⚠️ HomeScreen: Failed to update ${token.symbol} balance, keeping existing value');
        // TokenProvider retains its existing state, no manual cache restoration needed
      }
      setState(() {});
    } catch (e) {
      print('❌ HomeScreen: Error updating single token balance: $e');
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

  // ✅ Balance caching is now handled per-wallet in WalletStateManager
  // Global SharedPreferences caching has been replaced with per-wallet SecureStorage caching

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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 8),
                child: Text(
                  _safeTranslate('select wallet', 'Select Wallet'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Wallets list
              Flexible(
                child: FutureBuilder<List<Map<String, String>>>(
                  future: SecureStorage.instance.getWalletsList(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            _safeTranslate('no wallets found', 'No wallets found'),
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    }

                    final wallets = snapshot.data!;

                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: wallets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final wallet = wallets[index];
                        final walletName = wallet['walletName'] ?? '';
                        final userId = wallet['userID'] ?? '';

                        return GestureDetector(
                          onTap: () async {
                            try {
                              // Save selected wallet to SecureStorage
                              await SecureStorage.instance.saveSelectedWallet(walletName, userId);

                              // Update AppProvider
                              final appProvider = Provider.of<AppProvider>(context, listen: false);
                              await appProvider.selectWallet(walletName);

                              // Close modal
                              Navigator.pop(context);

                              // Force refresh after wallet change
                              await _performImmediateRefreshAfterTokenChange();

                              // Show success message
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_safeTranslate('wallet switched', 'Switched to {wallet}').replaceAll('{wallet}', walletName)),
                                  backgroundColor: const Color(0xFF0BAB9B),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } catch (e) {
                              print('❌ Error switching wallet: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_safeTranslate('error switching wallet', 'Error switching wallet')),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF08C495), Color(0xFF39b6fb)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    walletName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Image.asset(
                                  'assets/images/rightarrow.png',
                                  width: 18,
                                  height: 18,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// تریگر debug mode برای iOS - فراخوانی debug methods
  void _triggerDebugMode(AppProvider appProvider) async {
    if (!Platform.isIOS) {
      print('🤖 Debug mode: Not iOS, skipping');
      return;
    }

    print('🍎 === DEBUG MODE TRIGGERED ===');

    try {
      // نمایش loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Running diagnostics...'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );

      final tokenProvider = appProvider.tokenProvider;
      if (tokenProvider != null) {
        // 1. نمایش وضعیت فعلی
        // await tokenProvider.tokenPreferences.debugTokenRecoveryStatus(); // Method not available in utils TokenPreferences

        // 2. اگر توکن‌های فعال کم هستند، force recovery کن
        final enabledCount = tokenProvider.enabledTokens.length;
        print('🍎 Debug: Current enabled tokens count: $enabledCount');

        if (enabledCount <= 3) { // فقط توکن‌های پیش‌فرض
          print('🍎 Debug: Low token count detected, forcing recovery...');

          // نمایش دیالوگ تأیید
          final shouldRecover = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('🍎 iOS Token Recovery'),
              content: Text('Found only $enabledCount active tokens.\n\nWould you like to attempt recovery from secure storage?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Recover'),
                ),
              ],
            ),
          );

          if (shouldRecover == true) {
            print('🍎 Debug: User confirmed recovery, starting...');

            // نمایش loading
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🍎 Recovering tokens from secure storage...'),
                duration: Duration(seconds: 5),
                backgroundColor: Colors.green,
              ),
            );

            // Force recovery
            // await tokenProvider.tokenPreferences.forceRecoveryFromSecureStorage(); // Method not available in utils TokenPreferences

            // اجبار به همگام‌سازی مجدد
            await tokenProvider.ensureTokensSynchronized();

            // نمایش نتیجه
            final newEnabledCount = tokenProvider.enabledTokens.length;
            print('🍎 Debug: Recovery completed. New enabled tokens count: $newEnabledCount');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🍎 Recovery completed!\nEnabled tokens: $enabledCount → $newEnabledCount'),
                duration: const Duration(seconds: 4),
                backgroundColor: newEnabledCount > enabledCount ? Colors.green : Colors.orange,
              ),
            );
          }
        } else {
          print('🍎 Debug: Token count looks good ($enabledCount tokens)');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Diagnostics completed successfully.'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('🍎 Debug mode error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred during diagnostics'),
          backgroundColor: Colors.red,
        ),
      );
    }

    print('🍎 === DEBUG MODE COMPLETED ===');
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
                          _safeTranslate('loading wallet', 'Loading wallet...'),
                          style: const TextStyle(color: Color(0xFF666666)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final walletName = appProvider.currentWalletName ?? _safeTranslate('my wallet', 'My Wallet');
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
                          _safeTranslate('initializing wallet', 'Initializing wallet...'),
                          style: const TextStyle(color: Color(0xFF666666)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _safeTranslate('loading tokens', 'Loading your tokens...'),
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
                          _safeTranslate('initializing wallet', 'Initializing wallet...'),
                          style: const TextStyle(color: Color(0xFF666666)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _safeTranslate('please wait', 'Please wait...'),
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
                          _safeTranslate('no active tokens found', 'No active tokens found'),
                          style: const TextStyle(color: Color(0xFF555555), fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/add-token'),
                              child: Text(_safeTranslate('add token', 'Add Token')),
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
                              onTap: () {
                                // Debug tap counter مخفی برای iOS
                                _debugTapCount++;
                                print('🔍 Debug tap count: $_debugTapCount');

                                // اگر ۷ بار tap شده، debug methods رو فراخوانی کن
                                if (_debugTapCount >= 7) {
                                  _debugTapCount = 0; // ریست کن
                                  _triggerDebugMode(appProvider);
                                }

                                // اگر کمتر از 7 بار tap شده و iOS است، countdown نمایش بده
                                if (_debugTapCount > 3 && Platform.isIOS) {
                                  final remaining = 7 - _debugTapCount;
                                  // Hide explicit debug text in UI
                                }

                                // همچنین والت مودال را نمایش بده
                                _showWalletModal();
                              },
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
                                final formattedValue = SharedPreferencesUtils.formatPortfolioValue(totalValue, currencySymbol);
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
                            _ActionButtonWithImage(
                              imagePath: 'assets/images/send.png',
                              label: _safeTranslate('send', 'Send'),
                              onTap: () {
                                Navigator.pushNamed(context, '/send');
                              },
                              bgColor: const Color(0x80D7FBE7),
                            ),
                            _ActionButtonWithImage(
                              imagePath: 'assets/images/receive.png',
                              label: _safeTranslate('receive', 'Receive'),
                              onTap: () {
                                Navigator.pushNamed(context, '/receive');
                              },
                              bgColor: const Color(0x80D7F0F1),
                            ),
                            Consumer<HistoryProvider>(
                              builder: (context, historyProvider, child) {
                                final pendingCount = historyProvider.pendingTransactionCount;
                                return _ActionButtonWithImage(
                                  imagePath: 'assets/images/history.png',
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
                      // Tabs with filter and sort icons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
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
                            // Filter and Sort icons
                            Row(
                              children: [
                                _FilterSortIcon(
                                  icon: Icons.sort_by_alpha,
                                  tooltip: _safeTranslate('sort alphabetically', 'Sort A-Z'),
                                  onTap: () => _showSortOptions(),
                                ),
                                const SizedBox(width: 12),
                                _FilterSortIcon(
                                  icon: Icons.filter_list,
                                  tooltip: _safeTranslate('filter tokens', 'Filter tokens'),
                                  onTap: () => _showFilterOptions(),
                                ),
                              ],
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
                            var enabledTokens = tokenProvider.enabledTokens;

                            // Apply filters
                            enabledTokens = _applyFilters(enabledTokens, priceProvider);

                            // Apply sorting
                            enabledTokens = _applySorting(enabledTokens, priceProvider);
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
                                  return _SwipeableTokenRow(
                                    key: ValueKey(token.symbol ?? token.name ?? index),
                                    token: token,
                                    isHidden: isHidden,
                                    tokenLogoCacheManager: tokenLogoCacheManager,
                                    price: price,
                                    displayAmount: _getDisplayAmount(token),
                                    onSwipeToDisable: () async {
                                      print('🔄 HomeScreen: Swiping to disable token ${token.symbol}');

                                      try {
                                        // غیرفعال کردن توکن در TokenProvider - مشابه Android
                                        await tokenProvider.toggleToken(token, false);

                                        // ذخیره لیست active tokens برای والت فعلی (Persistence برای بعد از kill)
                                        try {
                                          final appProvider = Provider.of<AppProvider>(context, listen: false);
                                          final walletName = appProvider.currentWalletName;
                                          final userId = appProvider.currentUserId;
                                          if (walletName != null && userId != null) {
                                            final activeSymbols = tokenProvider.enabledTokens.map((t) => t.symbol ?? '').toList();
                                            await WalletStateManager.instance.saveActiveTokensForWallet(
                                              walletName,
                                              userId,
                                              activeSymbols,
                                            );
                                            print('💾 HomeScreen: Persisted active tokens after disable (${activeSymbols.length})');
                                          }
                                        } catch (persistError) {
                                          print('⚠️ HomeScreen: Error persisting active tokens after disable: $persistError');
                                        }

                                        // اطمینان از به‌روزرسانی کش add_token_screen
                                        await _updateAddTokenScreenCache(token);

                                        // نمایش پیام confirmation مشابه Android
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(_safeTranslate('token disabled', 'Token {symbol} disabled').replaceAll('{symbol}', token.symbol ?? '')),
                                            backgroundColor: const Color(0xFFFF1961),
                                            duration: const Duration(seconds: 3),
                                            action: SnackBarAction(
                                              label: _safeTranslate('undo', 'Undo'),
                                              textColor: Colors.white,
                                              onPressed: () async {
                                                // Re-enable the token
                                                await tokenProvider.toggleToken(token, true);
                                                await _updateAddTokenScreenCache(token);
                                                // ذخیره active tokens پس از فعال‌سازی مجدد
                                                try {
                                                  final appProvider = Provider.of<AppProvider>(context, listen: false);
                                                  final walletName = appProvider.currentWalletName;
                                                  final userId = appProvider.currentUserId;
                                                  if (walletName != null && userId != null) {
                                                    final activeSymbols = tokenProvider.enabledTokens.map((t) => t.symbol ?? '').toList();
                                                    await WalletStateManager.instance.saveActiveTokensForWallet(
                                                      walletName,
                                                      userId,
                                                      activeSymbols,
                                                    );
                                                    print('💾 HomeScreen: Persisted active tokens after re-enable (${activeSymbols.length})');
                                                  }
                                                } catch (persistError) {
                                                  print('⚠️ HomeScreen: Error persisting active tokens after re-enable: $persistError');
                                                }

                                                // Refresh balance and price for re-enabled token
                                                await _performTokenReactivation(token);
                                              },
                                            ),
                                          ),
                                        );

                                        print('✅ HomeScreen: Token ${token.symbol} disabled successfully');
                                      } catch (e) {
                                        print('❌ HomeScreen: Error disabling token ${token.symbol}: $e');

                                        // نمایش پیام خطا
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(_safeTranslate('error disabling token', 'Error disabling token: {error}').replaceAll('{error}', e.toString())),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CryptoDetailsScreen(
                                            tokenName: token.name ?? '',
                                            tokenSymbol: token.symbol ?? '',
                                            iconUrl: token.iconUrl ?? 'https://coinceeper.com/defaultIcons/coin.png',
                                            isToken: token.isToken,
                                            blockchainName: token.blockchainName ?? '',
                                            gasFee: 0.0, // TODO: دریافت از API
                                          ),
                                        ),
                                      );
                                    },
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
                              child: _NFTEmptyWidget(_safeTranslate('no nft found', 'No NFT Found')),
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
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final currentUserId = appProvider.currentUserId;

      // Get the token's own amount first as baseline
      final tokenAmount = token.amount ?? 0.0;

      // If we have a user ID, try to get from BalanceManager as well
      if (currentUserId != null && currentUserId.isNotEmpty) {
        final balanceFromManager = BalanceManager.instance.getTokenBalance(
          currentUserId,
          token.symbol ?? '',
        );

        // Priority logic: prefer the higher value or the most recently valid one
        if (balanceFromManager > 0.0 && tokenAmount > 0.0) {
          // Both have values - prefer the higher one
          return balanceFromManager > tokenAmount ? balanceFromManager : tokenAmount;
        } else if (balanceFromManager > 0.0) {
          // Only BalanceManager has value
          return balanceFromManager;
        } else if (tokenAmount > 0.0) {
          // Only token has value
          return tokenAmount;
        }

        // If both are 0, at least show the token's amount (might be 0 but consistent)
        return tokenAmount;
      }

      // Fallback to token amount if no user ID
      return tokenAmount;

    } catch (e) {
      print('❌ HomeScreen: Error in _getDisplayAmount for ${token.symbol}: $e');
      // Safe fallback
      return token.amount ?? 0.0;
    }
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

class _ActionButtonWithImage extends StatelessWidget {
  final String imagePath;
  final String label;
  final VoidCallback onTap;
  final Color bgColor;
  final String? badge;
  const _ActionButtonWithImage({
    required this.imagePath,
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
                  child: Image.asset(
                    imagePath,
                    width: 24,
                    height: 24,
                    color: Colors.black87,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.error,
                      size: 24,
                      color: Colors.black87,
                    ),
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

/// Widget قابل swipe برای disable کردن توکن - مشابه TokenRow در Android
class _SwipeableTokenRow extends StatefulWidget {
  final CryptoToken token;
  final bool isHidden;
  final CacheManager? tokenLogoCacheManager;
  final double price;
  final double displayAmount;
  final VoidCallback onSwipeToDisable;
  final VoidCallback onTap;

  const _SwipeableTokenRow({
    Key? key,
    required this.token,
    required this.isHidden,
    this.tokenLogoCacheManager,
    required this.price,
    required this.displayAmount,
    required this.onSwipeToDisable,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_SwipeableTokenRow> createState() => _SwipeableTokenRowState();
}

class _SwipeableTokenRowState extends State<_SwipeableTokenRow>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  static const double _maxSwipe = -80.0;
  static const double _disableThreshold = -48.0; // 60% of maxSwipe - مشابه Android

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(_maxSwipe * 1.2, 0.0);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragOffset <= _disableThreshold) {
      // اگر از threshold گذشت، توکن را disable کن
      widget.onSwipeToDisable();
      _resetPosition();
    } else {
      // در غیر این صورت، برگردان به موقعیت اولیه
      _resetPosition();
    }
  }

  void _resetPosition() {
    _slideAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward().then((_) {
      setState(() {
        _dragOffset = 0.0;
      });
      _animationController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dragOffset == 0 ? widget.onTap : _resetPosition,
      child: Stack(
        children: [
          // Background قرمز با متن "Disable" - مشابه Android
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF1961).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 80,
                  height: 68,
                  alignment: Alignment.center,
                  child: const Text(
                    'Disable',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // محتوای اصلی توکن - مشابه Android
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              final currentOffset = _animationController.isAnimating
                  ? _slideAnimation.value
                  : _dragOffset;

              return Transform.translate(
                offset: Offset(currentOffset, 0),
                child: GestureDetector(
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: _TokenRow(
                    token: widget.token,
                    isHidden: widget.isHidden,
                    tokenLogoCacheManager: widget.tokenLogoCacheManager,
                    price: widget.price,
                    displayAmount: widget.displayAmount,
                  ),
                ),
              );
            },
          ),
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

    // Format amount using the same logic as Android
    final formattedAmount = isHidden ? '****' : SharedPreferencesUtils.formatAmount(displayAmount, price);

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
      print('🔍 HomeScreen NCC Debug:');
      print('  - Symbol: $symbol');
      print('  - AssetIcon path: $assetIcon');
      print('  - Token iconUrl: ${token.iconUrl}');
      print('  - Token name: ${token.name}');
      print('  - Will use network: ${(symbol == 'NCC' && (token.iconUrl ?? '').startsWith('http'))}');
      print('  - iconUrl starts with http: ${(token.iconUrl ?? '').startsWith('http')}');
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE7FAEF), Color(0xFFE7F0FB)]),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          // Token icon - circular and larger size
          ClipOval(
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
                cacheManager: tokenLogoCacheManager,
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
                      cacheManager: tokenLogoCacheManager,
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
                cacheManager: tokenLogoCacheManager,
                errorWidget: (context, url, error) => const Icon(Icons.error),
              )
                  : (token.iconUrl ?? '').startsWith('assets/')
                  ? Image.asset(
                token.iconUrl ?? '',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
              )
                  : const Icon(Icons.error),
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
              Text(formattedAmount, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedValue = SharedPreferencesUtils.formatTokenValue(tokenValue, currencySymbol);
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

/// Widget آیکون فیلتر و مرتب‌سازی
class _FilterSortIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FilterSortIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 20,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

/// Widget گزینه مرتب‌سازی
class _SortOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String currentValue;
  final ValueChanged<String> onChanged;

  const _SortOption({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == currentValue;

    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF11c699) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? const Color(0xFF11c699) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF11c699),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

