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
    _loadTokens();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // بررسی کن که آیا cache invalidate شده یا نه
    _checkCacheInvalidation();
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
    } catch (e) {
      print('❌ AddTokenScreen: Error checking cache invalidation: $e');
    }
  }

  String get _translatedSelectedNetwork {
    if (selectedNetwork == 'All Blockchains') {
      return _safeTranslate('all_blockchains', 'All Blockchains');
    }
    return selectedNetwork;
  }

  Future<void> _loadTokens({bool forceRefresh = false}) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    // اگر کش وجود دارد و رفرش دستی نیست، از کش استفاده کن
    if (!forceRefresh && _cachedTokens != null) {
      setState(() {
        allTokens = List<CryptoToken>.from(_cachedTokens!);
        _filterTokens();
        isLoading = false;
      });
      return;
    }

    try {
      final apiService = ServiceProvider.instance.apiService;
      final response = await apiService.getAllCurrencies();
      if (response.success) {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        final tokenProvider = appProvider.tokenProvider;
        
        if (tokenProvider == null) {
          setState(() {
            errorMessage = _safeTranslate('token_provider_not_available', 'Token provider not available');
            isLoading = false;
          });
          return;
        }
        
        final tokens = response.currencies.map((currency) {
          final tempToken = CryptoToken(
            name: currency.currencyName ?? '',
            symbol: currency.symbol ?? '',
            blockchainName: currency.blockchainName ?? '',
            iconUrl: (currency.icon == null || currency.icon!.isEmpty)
                ? "https://coinceeper.com/defualtIcons/coin.png"
                : currency.icon,
            isEnabled: false, // We'll set the correct value below
            amount: 0.0,
            isToken: currency.isToken ?? true,
            smartContractAddress: currency.smartContractAddress ?? '',
          );
          
          // Get the actual enabled state from TokenProvider
          final isEnabled = tokenProvider.isTokenEnabled(tempToken);
          
          return tempToken.copyWith(isEnabled: isEnabled);
        }).toList();
        // کش را به‌روزرسانی کن
        _cachedTokens = List<CryptoToken>.from(tokens);
        setState(() {
          allTokens = tokens;
          _filterTokens();
          isLoading = false;
        });
        tokenProvider.setAllTokens(tokens);
        
        // ذخیره cache برای synchronization با home screen
        await _saveCacheKey();
        
      } else {
        setState(() {
          errorMessage = _safeTranslate('failed_to_load_tokens', 'Failed to load tokens');
          isLoading = false;
        });
      }
    } catch (e) {
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

  Future<void> _refreshTokens() async {
    setState(() => refreshing = true);
    // کش را پاک کن و درخواست جدید بزن
    _cachedTokens = null;
    await _loadTokens(forceRefresh: true);
    setState(() => refreshing = false);
    
    // ذخیره cache key بعد از refresh
    await _saveCacheKey();
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
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: blockchains.length,
                itemBuilder: (context, index) {
                  final blockchain = blockchains[index];
                  final isSelected = blockchain['name'] == selectedNetwork;
                  
                  return GestureDetector(
                    onTap: () {
                      _onNetworkSelected(blockchain['name']);
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0x1A1AC89E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Image.asset(
                            blockchain['icon'],
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.currency_bitcoin, size: 24, color: Colors.orange);
                            },
                          ),
                          const SizedBox(width: 14),
                          Text(
                            blockchain['name'] == 'All Blockchains' 
                                ? _safeTranslate('all_blockchains', 'All Blockchains')
                                : blockchain['name'],
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
                },
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _toggleToken(CryptoToken token) async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      if (tokenProvider == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('token_provider_not_available', 'Token provider not available')),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final newState = !token.isEnabled;
      print('🔄 Toggle token ${token.symbol}: ${token.isEnabled} -> $newState');
      
      // Toggle the token state
      await tokenProvider.toggleToken(token, newState);
      
      // فوراً local state را به‌روزرسانی کن
      setState(() {
        // Update the token in allTokens
        final tokenIndex = allTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (tokenIndex != -1) {
          allTokens[tokenIndex] = allTokens[tokenIndex].copyWith(isEnabled: newState);
        }
        
        // Update the token in filteredTokens
        final filteredIndex = filteredTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (filteredIndex != -1) {
          filteredTokens[filteredIndex] = filteredTokens[filteredIndex].copyWith(isEnabled: newState);
        }
        
        // Update cache as well
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
      
      // اگر توکن فعال شده، فوراً موجودی و قیمت آن را fetch کن
      if (newState) {
        print('✅ Token ${token.symbol} activated - fetching balance and price immediately');
        
        // موازی: دریافت موجودی و قیمت
        await Future.wait<void>([
          // دریافت موجودی فوری برای توکن جدید
          _fetchSingleTokenBalance(token, tokenProvider),
          // دریافت قیمت فوری برای توکن جدید
          _fetchSingleTokenPrice(token, priceProvider),
        ]);
        
        print('✅ Token ${token.symbol} balance and price fetched successfully');
        
        // Refresh قیمت‌های همه توکن‌های فعال در background
        _refreshAllEnabledTokens(tokenProvider, priceProvider);
      } else {
        // اگر توکن غیرفعال شده، فقط قیمت‌های بقیه را refresh کن
        final enabledSymbols = tokenProvider.enabledTokens
            .map((t) => t.symbol ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        
        if (enabledSymbols.isNotEmpty) {
          print('🔄 Refreshing prices for remaining ${enabledSymbols.length} tokens');
          priceProvider.fetchPrices(enabledSymbols);
        }
      }
      
      print('✅ Token ${token.symbol} toggled successfully');
      
    } catch (e) {
      print('❌ Error toggling token ${token.symbol}: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_safeTranslate('error_changing_token_status', 'Error changing token status') + ': ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
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

