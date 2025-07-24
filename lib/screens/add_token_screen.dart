import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../providers/price_provider.dart';
import '../models/crypto_token.dart';
import '../services/service_provider.dart';
import '../layout/main_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomSwitch extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onCheckedChange;

  const CustomSwitch({
    required this.checked,
    required this.onCheckedChange,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onCheckedChange(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: checked ? const Color(0xFF27B6AC) : Colors.grey,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({Key? key}) : super(key: key);

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  static List<CryptoToken>? _cachedTokens; // کش توکن‌ها
  String searchText = '';
  String selectedNetwork = 'All Blockchains';
  bool isLoading = false;
  bool refreshing = false;
  String? errorMessage;
  List<CryptoToken> allTokens = [];
  List<CryptoToken> filteredTokens = [];
  bool _needsRefresh = false; // فلگ برای تشخیص نیاز به refresh
  
  /// Safe translation helper with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      print('⚠️ Translation error for key "$key": $e');
      return fallback;
    }
  }
  
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
  


  @override
  void initState() {
    super.initState();
    // Load tokens after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokens();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // بررسی کن که آیا cache invalidate شده یا نه
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCacheInvalidation();
    });
  }

  /// بررسی invalidation کش و refresh در صورت نیاز
  Future<void> _checkCacheInvalidation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheExists = prefs.containsKey('add_token_cached_tokens');
      
      // اگر cache وجود نداشته باشد (یعنی در home حذف شده)، نیاز به refresh است
      if (!cacheExists && _cachedTokens != null) {
        print('🔄 AddTokenScreen: Cache invalidated, refreshing data...');
        _needsRefresh = true;
        _cachedTokens = null; // پاک کردن cache محلی
        
        // اگر widget ساخته شده، refresh کن
        if (mounted) {
          await _loadTokens(forceRefresh: true);
        }
      }
      
      // همیشه state توکن‌ها را از preferences به‌روزرسانی کن
      if (mounted) {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        final tokenProvider = appProvider.tokenProvider;
        if (tokenProvider != null) {
          // Ensure TokenPreferences is initialized
          await tokenProvider.tokenPreferences.initialize();
          await tokenProvider.forceUpdateTokenStates();
        }
      }
    } catch (e) {
      print('❌ AddTokenScreen: Error checking cache invalidation: $e');
    }
  }

  /// اعتبارسنجی حالت ماندگاری توکن‌ها
  Future<void> _validateTokenPersistence() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ TokenProvider is null - cannot validate persistence');
        return;
      }
      
      // اطمینان از مقداردهی اولیه TokenPreferences
      await tokenProvider.tokenPreferences.initialize();
      
      // بررسی اینکه آیا cache مقداردهی اولیه شده است
      if (!tokenProvider.tokenPreferences.isCacheInitialized) {
        print('⚠️ TokenPreferences cache not initialized - refreshing...');
        await tokenProvider.tokenPreferences.refreshCache();
      }
      
      // بررسی اینکه آیا state توکن‌ها از SharedPreferences load شده‌اند
      final enabledTokenKeys = await tokenProvider.tokenPreferences.getAllEnabledTokenKeys();
      print('✅ Persistence validation: Found ${enabledTokenKeys.length} enabled tokens in storage');
      
      // Force update token states from preferences
      await tokenProvider.forceUpdateTokenStates();
      
    } catch (e) {
      print('❌ Error validating token persistence: $e');
    }
  }

  String get _translatedSelectedNetwork {
    if (selectedNetwork == 'All Blockchains') {
      return _safeTranslate('all_blockchains', 'All Blockchains');
    }
    return selectedNetwork;
  }

  /// بارگذاری توکن‌ها - مشابه Kotlin
  Future<void> _loadTokens({bool forceRefresh = false}) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        setState(() {
          errorMessage = _safeTranslate('token_provider_not_available', 'Token provider not available');
          isLoading = false;
        });
        return;
      }

      print('🔄 AddTokenScreen: Loading tokens for user: ${tokenProvider.getCurrentUserId()}');

      // 1. اطمینان از مقداردهی اولیه TokenPreferences
      await tokenProvider.tokenPreferences.initialize();
      
      // 2. همگام‌سازی tokens - مشابه Kotlin
      await tokenProvider.ensureTokensSynchronized();
      
      // 3. اگر force refresh است یا cache معتبر نیست، از API بارگذاری کن
      if (forceRefresh) {
        print('🔄 AddTokenScreen: Force refresh requested, loading from API');
        await tokenProvider.smartLoadTokens(forceRefresh: true);
      }
      
      // 4. دریافت tokens از TokenProvider
      final tokens = tokenProvider.currencies;
      
      if (tokens.isNotEmpty) {
        print('✅ AddTokenScreen: Loaded ${tokens.length} tokens from TokenProvider');
        
        // به‌روزرسانی cache
        _cachedTokens = List<CryptoToken>.from(tokens);
        
        setState(() {
          allTokens = tokens;
          _filterTokens();
          isLoading = false;
        });
        
        // ذخیره cache key
        await _saveCacheKey();
        
        print('✅ AddTokenScreen: Tokens loaded and UI updated');
        return;
      }
      
      // 5. اگر هیچ token وجود نداشت، خطا نمایش بده
      print('⚠️ AddTokenScreen: No tokens found');
      setState(() {
        errorMessage = _safeTranslate('no_tokens_found', 'No tokens found');
        isLoading = false;
      });
      
    } catch (e) {
      print('❌ AddTokenScreen: Error loading tokens: $e');
      setState(() {
        errorMessage = _safeTranslate('error_loading_tokens', 'Error loading tokens') + ': $e';
        isLoading = false;
      });
    }
  }

  /// ذخیره cache key برای همگام‌سازی با home screen
  Future<void> _saveCacheKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('add_token_cached_tokens', DateTime.now().millisecondsSinceEpoch.toString());
      print('✅ AddTokenScreen: Cache key saved for synchronization');
    } catch (e) {
      print('❌ AddTokenScreen: Error saving cache key: $e');
    }
  }

  /// تازه‌سازی توکن‌ها - مشابه Kotlin
  Future<void> _refreshTokens() async {
    setState(() => refreshing = true);
    
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ AddTokenScreen: TokenProvider is null during refresh');
        return;
      }
      
      print('🔄 AddTokenScreen: Refreshing tokens for user: ${tokenProvider.getCurrentUserId()}');
      
      // 1. پاک کردن cache محلی
      _cachedTokens = null;
      
      // 2. Force refresh از TokenProvider - مشابه Kotlin
      await tokenProvider.forceRefresh();
      
      // 3. بارگذاری مجدد tokens
      await _loadTokens(forceRefresh: true);
      
      // 4. ذخیره cache key
      await _saveCacheKey();
      
      print('✅ AddTokenScreen: Tokens refreshed successfully');
      
    } catch (e) {
      print('❌ AddTokenScreen: Error refreshing tokens: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تازه‌سازی توکن‌ها: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => refreshing = false);
    }
  }

  /// Debug: بررسی وضعیت persistence توکن‌ها
  Future<void> _debugTokenPersistence() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ Debug: TokenProvider is null');
        return;
      }
      
      print('=== TOKEN PERSISTENCE DEBUG ===');
      print('Cache initialized: ${tokenProvider.tokenPreferences.isCacheInitialized}');
      
      final enabledTokenKeys = await tokenProvider.tokenPreferences.getAllEnabledTokenKeys();
      print('Enabled tokens in storage: ${enabledTokenKeys.length}');
      
      final enabledTokenNames = await tokenProvider.tokenPreferences.getAllEnabledTokenNames();
      print('Enabled token names: $enabledTokenNames');
      
      final enabledTokens = tokenProvider.enabledTokens;
      print('Enabled tokens in TokenProvider: ${enabledTokens.length}');
      print('Enabled tokens list: ${enabledTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
      
      // Test a few tokens
      if (allTokens.isNotEmpty) {
        for (int i = 0; i < allTokens.take(3).length; i++) {
          final token = allTokens[i];
          final storedState = await tokenProvider.tokenPreferences.getTokenState(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          );
          final syncState = tokenProvider.tokenPreferences.getTokenStateSync(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          );
          print('Token ${token.symbol}: current=${token.isEnabled}, stored=$storedState, sync=$syncState');
        }
      }
      
      print('=== END DEBUG ===');
    } catch (e) {
      print('❌ Error in debug token persistence: $e');
    }
  }

  void _filterTokens() {
    filteredTokens = allTokens.where((token) {
      final matchesSearch = searchText.isEmpty ||
          (token.name ?? '').toLowerCase().contains(searchText.toLowerCase()) ||
          (token.symbol ?? '').toLowerCase().contains(searchText.toLowerCase());
      
      final matchesNetwork = selectedNetwork == 'All Blockchains' ||
          token.blockchainName == selectedNetwork;

      return matchesSearch && matchesNetwork;
    }).toList();
  }

  void _showNetworkModal() {
    // Remove modal bottom sheet - network selection removed
  }

  void _onSearchChanged(String value) {
    setState(() {
      searchText = value;
      _filterTokens();
    });
  }

  void _onNetworkSelected(String network) {
    setState(() {
      selectedNetwork = network;
      _filterTokens();
    });
  }

  /// Toggle کردن وضعیت توکن - مشابه Kotlin
  Future<void> _toggleToken(CryptoToken token) async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      if (tokenProvider == null) {
        print('❌ AddTokenScreen: TokenProvider is null');
        return;
      }
      
      final newState = !token.isEnabled;
      print('🔄 AddTokenScreen: Toggle token ${token.symbol}: ${token.isEnabled} -> $newState');
      
      // 1. مستقیماً از TokenProvider برای toggle استفاده کن
      await tokenProvider.toggleToken(token, newState);
      
      // 2. یک کمی صبر کن تا state ذخیره شود
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 3. تأیید اینکه state درست ذخیره شده است
      final verifyState = tokenProvider.isTokenEnabled(token);
      if (verifyState != newState) {
        print('❌ AddTokenScreen: Token state verification failed for ${token.symbol}');
        // تلاش مجدد برای ذخیره
        await tokenProvider.saveTokenStateForUser(token, newState);
        print('🔄 AddTokenScreen: Retried saving token state for ${token.symbol}');
      } else {
        print('✅ AddTokenScreen: Token state verified for ${token.symbol}: $newState');
      }
      
      // 4. به‌روزرسانی local state
      setState(() {
        // Update token in allTokens
        final tokenIndex = allTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (tokenIndex != -1) {
          allTokens[tokenIndex] = allTokens[tokenIndex].copyWith(isEnabled: newState);
        }
        
        // Update token in filteredTokens
        final filteredIndex = filteredTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (filteredIndex != -1) {
          filteredTokens[filteredIndex] = filteredTokens[filteredIndex].copyWith(isEnabled: newState);
        }
        
        // Update cache
        if (_cachedTokens != null) {
          final cacheIndex = _cachedTokens!.indexWhere((t) => 
            t.symbol == token.symbol && 
            t.blockchainName == token.blockchainName &&
            t.smartContractAddress == token.smartContractAddress
          );
          
          if (cacheIndex != -1) {
            _cachedTokens![cacheIndex] = _cachedTokens![cacheIndex].copyWith(isEnabled: newState);
          }
        }
      });
      
      // 5. در صورت فعال بودن توکن، قیمت fetch کن
      if (newState && priceProvider != null) {
        print('✅ AddTokenScreen: Token ${token.symbol} activated - fetching price');
        final symbols = [token.symbol ?? ''];
        priceProvider.fetchPrices(symbols);
      }
      
      // 6. ذخیره cache key برای synchronization
      await _saveCacheKey();
      
      print('✅ AddTokenScreen: Token ${token.symbol} toggled successfully');
      
    } catch (e) {
      print('❌ AddTokenScreen: Error toggling token ${token.symbol}: $e');
      // نمایش خطا به کاربر
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تغییر وضعیت توکن: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// دریافت موجودی فوری برای یک توکن خاص
  Future<void> _fetchSingleTokenBalance(CryptoToken token, tokenProvider) async {
    try {
      print('💰 Fetching balance for ${token.symbol}...');
      
      // فراخوانی update موجودی برای توکن خاص
      await tokenProvider.updateSingleTokenBalance(token);
      
      print('✅ Balance fetched for ${token.symbol}');
    } catch (e) {
      print('❌ Error fetching balance for ${token.symbol}: $e');
    }
  }

  /// دریافت قیمت فوری برای یک توکن خاص
  Future<void> _fetchSingleTokenPrice(CryptoToken token, PriceProvider priceProvider) async {
    try {
      print('💲 Fetching price for ${token.symbol}...');
      
      final symbol = token.symbol ?? '';
      if (symbol.isNotEmpty) {
        await priceProvider.fetchPrices([symbol]);
      }
      
      print('✅ Price fetched for ${token.symbol}');
    } catch (e) {
      print('❌ Error fetching price for ${token.symbol}: $e');
    }
  }

  /// Refresh همه توکن‌های فعال در background
  Future<void> _refreshAllEnabledTokens(tokenProvider, PriceProvider priceProvider) async {
    try {
      print('🔄 Background refresh of all enabled tokens...');
      
      final enabledTokens = tokenProvider.enabledTokens;
      if (enabledTokens.isEmpty) return;
      
      // موازی: دریافت موجودی‌ها و قیمت‌ها
      await Future.wait<void>([
        // دریافت موجودی‌های همه توکن‌ها
        tokenProvider.updateBalance().then((_) => null), // convert Future<bool> to Future<void>
        // دریافت قیمت‌های همه توکن‌ها
        _fetchPricesForEnabledTokens(enabledTokens, priceProvider),
      ]);
      
      print('✅ Background refresh completed');
    } catch (e) {
      print('❌ Error in background refresh: $e');
    }
  }

  /// دریافت قیمت‌ها برای توکن‌های فعال
  Future<void> _fetchPricesForEnabledTokens(List<CryptoToken> tokens, PriceProvider priceProvider) async {
    if (tokens.isEmpty) return;
    
    final symbols = tokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
    
    if (symbols.isNotEmpty) {
      // دریافت قیمت برای ارزهای مختلف
      const currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
      await priceProvider.fetchPrices(symbols, currencies: currencies);
    }
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
              title: Text(
                _safeTranslate('token_management', 'Token Management'),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.black),
            ),
            body: RefreshIndicator(
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
                                decoration: InputDecoration(
                                  hintText: _safeTranslate('search', 'Search'),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: _onSearchChanged,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Network filter
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
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
                                Text(
                                  _translatedSelectedNetwork,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF2c2c2c),
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.arrow_drop_down, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _safeTranslate('cryptocurrencies', 'Cryptocurrencies'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xCB838383),
                            ),
                          ),
                          Text(
                            _safeTranslate('cryptos_count', '${filteredTokens.length} Cryptos').replaceAll('{count}', filteredTokens.length.toString()),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xCB838383),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Loading state
                      if (isLoading)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(_safeTranslate('loading', 'Loading...')),
                              ],
                            ),
                          ),
                        )
                      // Error state
                      else if (errorMessage != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                const Icon(Icons.error, color: Colors.red, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadTokens,
                                  child: Text(_safeTranslate('try_again', 'Try Again')),
                                ),
                              ],
                            ),
                          ),
                        )
                      // Empty state
                      else if (filteredTokens.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              _safeTranslate('no_tokens_found', 'No tokens found'),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      // Token list
                      else
                        Consumer<AppProvider>(
                          builder: (context, appProvider, child) {
                            if (appProvider.tokenProvider == null) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    context.tr('token_provider_not_available'),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              );
                            }
                            
                            final tokenProvider = appProvider.tokenProvider!;
                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredTokens.length,
                              itemBuilder: (context, index) {
                                final token = filteredTokens[index];
                                // Use the token's isEnabled state directly instead of checking preferences
                                final isEnabled = token.isEnabled;
                                
                                return _TokenItem(
                                  token: token,
                                  isEnabled: isEnabled,
                                  onToggle: () async {
                                    await _toggleToken(token);
                                  },
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _TokenItem extends StatelessWidget {
  final CryptoToken token;
  final bool isEnabled;
  final VoidCallback onToggle;

  const _TokenItem({
    required this.token,
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Token icon
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: (token.iconUrl ?? '').startsWith('http')
                  ? Image.network(
                      token.iconUrl ?? '',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.currency_bitcoin, size: 24, color: Colors.orange);
                      },
                    )
                  : (token.iconUrl ?? '').startsWith('assets/')
                      ? Image.asset(token.iconUrl ?? '', width: 32, height: 32, fit: BoxFit.cover)
                      : const Icon(Icons.currency_bitcoin, size: 24, color: Colors.orange),
            ),
          ),
          const SizedBox(width: 12),
          // Token info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      token.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      token.symbol ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  token.blockchainName ?? '',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Custom Switch
          CustomSwitch(
            checked: isEnabled,
            onCheckedChange: (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}

