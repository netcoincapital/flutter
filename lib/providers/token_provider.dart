import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/crypto_token.dart';
import '../models/price_data.dart';
import '../services/api_service.dart';
import '../utils/token_preferences.dart';

class TokenProvider extends ChangeNotifier {
  // فیلدهای وضعیت
  List<CryptoToken> _currencies = [];
  bool _isLoading = false;
  String? _errorMessage;
  List<CryptoToken> _activeTokens = [];
  Map<String, Map<String, PriceData>> _tokenPrices = {};
  Map<String, String> _gasFees = {};
  Map<String, List<CryptoToken>> _userTokens = {};
  Map<String, Map<String, String>> _userBalances = {};
  String _walletName = '';
  String _userId;
  final ApiService apiService;
  late TokenPreferences tokenPreferences;

  // کانستراکتور
  TokenProvider({
    required String userId,
    required this.apiService,
    BuildContext? context,
  }) : _userId = userId {
    tokenPreferences = TokenPreferences(userId: userId);
    // Don't call initialize here, it will be called from AppProvider
  }

  // گترها
  List<CryptoToken> get currencies => _currencies;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<CryptoToken> get activeTokens => _activeTokens;
  Map<String, Map<String, PriceData>> get tokenPrices => _tokenPrices;
  Map<String, String> get gasFees => _gasFees;
  String get walletName => _walletName;
  String get userId => _userId;

  // گترهای سازگاری با کد موجود
  List<CryptoToken> get tokens => _activeTokens;
  List<CryptoToken> get enabledTokens => _activeTokens.where((t) => t.isEnabled).toList();
  
  // Getter to check if TokenProvider is fully initialized
  bool get isInitialized => !_isLoading && _activeTokens.isNotEmpty;

  // متد اولیه‌سازی در background
  Future<void> initializeInBackground() async {
    print('🔄 TokenProvider: Initializing in background for user: $_userId');
    
    try {
      // Initialize TokenPreferences first
      await tokenPreferences.initialize();
      
      // Initialize default tokens immediately
      await _initializeDefaultTokensQuickly();
      
      // Load cached tokens immediately
      await _loadCachedTokensQuickly();
      
      // Background tasks - don't wait for these
      _runBackgroundTasks();
      
      print('✅ TokenProvider: Quick initialization completed for user: $_userId');
    } catch (e) {
      print('❌ TokenProvider: Error in background initialization: $e');
    }
  }
  
  // متد اولیه‌سازی (legacy - برای compatibility)
  Future<void> initialize() async {
    print('🔄 TokenProvider: Initializing for user: $_userId');
    
    // Initialize TokenPreferences first
    await tokenPreferences.initialize();
    
    // Initialize default tokens
    await _initializeDefaultTokens();
    
    // Fetch gas fees in background
    _fetchGasFees();
    
    // Load tokens with smart caching
    await smartLoadTokens(forceRefresh: false);
    
    // Load balances for active tokens مطابق با Kotlin
    print('🔄 TokenProvider: Loading balances for active tokens...');
    await fetchBalancesForActiveTokens();
    
    print('✅ TokenProvider: Initialized successfully for user: $_userId');
  }

  // مقداردهی اولیه سریع توکن‌های پیش‌فرض
  Future<void> _initializeDefaultTokensQuickly() async {
    final defaultTokens = [
      CryptoToken(
        name: 'Bitcoin',
        symbol: 'BTC',
        blockchainName: 'Bitcoin',
        iconUrl: 'https://coinceeper.com/defualtIcons/bitcoin.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      CryptoToken(
        name: 'Ethereum',
        symbol: 'ETH',
        blockchainName: 'Ethereum',
        iconUrl: 'https://coinceeper.com/defualtIcons/ethereum.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      CryptoToken(
        name: 'Tron',
        symbol: 'TRX',
        blockchainName: 'Tron',
        iconUrl: 'https://coinceeper.com/defualtIcons/tron.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
    ];
    
    // Set default tokens immediately
    _currencies = defaultTokens;
    _activeTokens = defaultTokens;
    notifyListeners();
    
    print('✅ TokenProvider: Default tokens set immediately');
  }
  
  // بارگذاری سریع توکن‌های cached
  Future<void> _loadCachedTokensQuickly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cachedUserTokens_$_userId');
      
      if (jsonStr != null) {
        final List<dynamic> list = json.decode(jsonStr);
        final cachedTokens = list.map((e) => CryptoToken.fromJson(e)).toList();
        
        // Override with cached tokens if available
        _currencies = cachedTokens;
        _activeTokens = cachedTokens.where((t) => t.isEnabled).toList();
        
        print('✅ TokenProvider: Cached tokens loaded quickly (${_activeTokens.length} active)');
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ TokenProvider: Could not load cached tokens: $e');
    }
  }
  
  // اجرای tasks در background
  void _runBackgroundTasks() {
    print('🔄 TokenProvider: Starting background tasks...');
    
    // Fetch gas fees
    _fetchGasFees();
    
    // Load fresh tokens from API
    smartLoadTokens(forceRefresh: false).then((_) {
      print('✅ TokenProvider: Fresh tokens loaded from API');
    }).catchError((e) {
      print('❌ TokenProvider: Error loading fresh tokens: $e');
    });
    
    // Load balances
    fetchBalancesForActiveTokens().then((_) {
      print('✅ TokenProvider: Balances loaded in background');
    }).catchError((e) {
      print('❌ TokenProvider: Error loading balances: $e');
    });
  }
  
  // مقداردهی اولیه توکن‌های پیش‌فرض
  Future<void> _initializeDefaultTokens() async {
    final defaultTokens = [
      CryptoToken(
        name: 'Bitcoin',
        symbol: 'BTC',
        blockchainName: 'Bitcoin',
        iconUrl: 'https://coinceeper.com/defualtIcons/bitcoin.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      CryptoToken(
        name: 'Ethereum',
        symbol: 'ETH',
        blockchainName: 'Ethereum',
        iconUrl: 'https://coinceeper.com/defualtIcons/ethereum.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      CryptoToken(
        name: 'Tron',
        symbol: 'TRX',
        blockchainName: 'Tron',
        iconUrl: 'https://coinceeper.com/defualtIcons/tron.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
    ];
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = prefs.getBool('is_first_run_$_userId') ?? true;
    if (isFirstRun) {
      for (final token in defaultTokens) {
        await tokenPreferences.saveTokenState(
          token.symbol ?? '',
          token.blockchainName ?? '',
          token.smartContractAddress,
          true,
        );
      }
      await prefs.setBool('is_first_run_$_userId', false);
      _currencies = defaultTokens;
      _activeTokens = defaultTokens;
      notifyListeners();
    } else {
      // اگر اولین اجرا نیست، فقط مطمئن شو توکن‌های پیش‌فرض فعال باشند
      for (final token in defaultTokens) {
        final enabled = await tokenPreferences.getTokenState(
          token.symbol ?? '',
          token.blockchainName ?? '',
          token.smartContractAddress,
        ) ?? true;
        if (enabled && !_activeTokens.any((t) => t.symbol == token.symbol)) {
          _activeTokens.add(token);
          print('🔄 Added default token to active: ${token.symbol}');
        }
      }
      notifyListeners();
    }
  }

  // متد نمونه برای دریافت گس‌فی
  Future<void> _fetchGasFees() async {
    try {
      final gasFeeResponse = await apiService.getGasFee();
      // تبدیل GasFeeResponse به Map<String, String>
      _gasFees = {
        'Bitcoin': gasFeeResponse.bitcoin?.gasFee ?? '0.0',
        'Ethereum': gasFeeResponse.ethereum?.gasFee ?? '0.0',
        'Tron': gasFeeResponse.tron?.gasFee ?? '0.0',
        'Binance': gasFeeResponse.binance?.gasFee ?? '0.0',
      };
      notifyListeners();
    } catch (_) {
      _gasFees = {'Bitcoin': '0.0', 'Ethereum': '0.0'};
      notifyListeners();
    }
  }

  // متد هوشمند بارگذاری توکن‌ها
  Future<void> smartLoadTokens({bool forceRefresh = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheValid = _isCacheValid(prefs);
      if (forceRefresh || !cacheValid) {
        await _loadFromApi(prefs);
      } else {
        final loaded = await _loadFromCache(prefs);
        if (!loaded) {
          await _loadFromApi(prefs);
        }
      }
      // ذخیره توکن‌های کاربر
      _userTokens[_userId] = _currencies;
    } catch (e) {
      _errorMessage = 'Error: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // بررسی اعتبار کش
  bool _isCacheValid(SharedPreferences prefs) {
    final lastCache = prefs.getInt('cache_timestamp_$_userId') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // اعتبار 24 ساعت
    return (now - lastCache) < (24 * 60 * 60 * 1000);
  }

  // بارگذاری از کش
  Future<bool> _loadFromCache(SharedPreferences prefs) async {
    final jsonStr = prefs.getString('cachedUserTokens_$_userId');
    if (jsonStr == null) return false;
    try {
      final List<dynamic> list = json.decode(jsonStr);
      final tokens = list.map((e) => CryptoToken.fromJson(e)).toList();
      _currencies = tokens;
      _activeTokens = tokens.where((t) => t.isEnabled).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // بارگذاری از API
  Future<void> _loadFromApi(SharedPreferences prefs) async {
    try {
      final response = await apiService.getAllCurrencies();
      if (response.success) {
        final tokens = response.currencies.map<CryptoToken>((token) {
          final isEnabled = tokenPreferences.getTokenStateSync(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          ) ?? false;
          return CryptoToken(
            name: token.currencyName,
            symbol: token.symbol,
            blockchainName: token.blockchainName,
            iconUrl: token.icon ?? 'https://coinceeper.com/defualtIcons/coin.png',
            isEnabled: isEnabled,
            isToken: token.isToken ?? true,
            smartContractAddress: token.smartContractAddress,
          );
        }).toList();
        final ordered = _maintainTokenOrder(tokens);
        await _saveToCache(prefs, ordered);
        _currencies = ordered;
        _activeTokens = ordered.where((t) => t.isEnabled).toList();
        notifyListeners();
      } else {
        _errorMessage = 'Failed to load tokens';
      }
    } catch (e) {
      _errorMessage = 'API error: ${e.toString()}';
    }
  }

  // ذخیره توکن‌ها در کش
  Future<void> _saveToCache(SharedPreferences prefs, List<CryptoToken> tokens) async {
    final jsonStr = json.encode(tokens.map((e) => e.toJson()).toList());
    await prefs.setString('cachedUserTokens_$_userId', jsonStr);
    await prefs.setInt('cache_timestamp_$_userId', DateTime.now().millisecondsSinceEpoch);
  }

  // حفظ ترتیب توکن‌ها بر اساس ذخیره قبلی
  List<CryptoToken> _maintainTokenOrder(List<CryptoToken> tokens) {
    final List<String> savedOrder = (tokenPreferences.getTokenOrderSync() ?? []).map((e) => e ?? '').toList();
    if (savedOrder.isEmpty) return tokens;
    final tokenMap = {for (var t in tokens) '${t.symbol ?? ''}_${t.name ?? ''}': t};
    final orderedTokens = <CryptoToken>[];
    for (final symbol in savedOrder) {
      if (tokenMap.containsKey(symbol)) {
        orderedTokens.add(tokenMap[symbol]!);
      }
    }
    for (final token in tokens) {
      if (!orderedTokens.contains(token)) {
        orderedTokens.add(token);
      }
    }
    return orderedTokens;
  }

  // --- قیمت توکن‌ها ---
  static const int PRICE_CACHE_EXPIRY_TIME = 5 * 60 * 1000; // 5 دقیقه

  Future<void> fetchPrices({List<String>? activeSymbols, List<String>? fiatCurrencies}) async {
    activeSymbols ??= _activeTokens.map((t) => t.symbol).whereType<String>().toList();
    fiatCurrencies ??= ['USD', 'EUR', 'IRR'];
    if (activeSymbols.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_isPriceCacheValid(prefs)) {
      await loadPricesFromCache(prefs);
    }
    try {
      final pricesResponse = await apiService.getPrices(activeSymbols, fiatCurrencies);
      if (pricesResponse.success && pricesResponse.prices != null) {
        // تبدیل PriceData از api_models به models
        final convertedPrices = <String, Map<String, PriceData>>{};
        pricesResponse.prices!.forEach((symbol, currencyMap) {
          convertedPrices[symbol] = currencyMap.map((currency, priceData) => 
            MapEntry(currency, PriceData(
              change24h: priceData.change24h,
              price: priceData.price,
            ))
          );
        });
        _tokenPrices = convertedPrices;
        await savePricesToCache(prefs, _tokenPrices);
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _isPriceCacheValid(SharedPreferences prefs) {
    final lastCache = prefs.getInt('price_cache_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastCache) < PRICE_CACHE_EXPIRY_TIME;
  }

  Future<void> loadPricesFromCache(SharedPreferences prefs) async {
    final jsonStr = prefs.getString('cached_prices');
    if (jsonStr == null) return;
    try {
      final Map<String, dynamic> map = json.decode(jsonStr);
      _tokenPrices = map.map((k, v) => MapEntry(k, (v as Map<String, dynamic>).map((kk, vv) => MapEntry(kk, PriceData.fromJson(vv)))));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> savePricesToCache(SharedPreferences prefs, Map<String, Map<String, PriceData>> prices) async {
    final map = prices.map((k, v) => MapEntry(k, v.map((kk, vv) => MapEntry(kk, vv.toJson()))));
    final jsonStr = json.encode(map);
    await prefs.setString('cached_prices', jsonStr);
    await prefs.setInt('price_cache_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  // --- فعال/غیرفعال کردن توکن ---
  Future<void> toggleToken(CryptoToken token, bool newState) async {
    print('🔄 Toggling token: ${token.symbol} to $newState');
    
    await tokenPreferences.saveTokenState(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress, newState);
    
    // به‌روزرسانی لیست توکن‌ها
    _currencies = _currencies.map((t) {
      if (t.symbol == token.symbol && t.blockchainName == token.blockchainName && t.smartContractAddress == token.smartContractAddress) {
        return t.copyWith(isEnabled: newState);
      }
      return t;
    }).toList();
    
    // به‌روزرسانی توکن‌های فعال
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    
    print('🔄 Active tokens after toggle: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
    
    // فوراً listeners را اطلاع ده
    notifyListeners();
    
    if (newState) {
      await fetchPrices();
    }
  }

  Future<void> updateActiveTokensFromPreferences() async {
    _currencies = _currencies.map((token) {
      final isEnabled = tokenPreferences.getTokenStateSync(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
      return token.copyWith(isEnabled: isEnabled);
    }).toList();
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    notifyListeners();
  }

  // --- متد کمکی برای قیمت توکن ---
  double getTokenPrice(String symbol, String currency) {
    final priceStr = _tokenPrices[symbol]?[currency]?.price;
    if (priceStr != null) {
      return double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }

  // --- مدیریت موجودی ---
  Future<Map<String, String>> fetchBalancesForActiveTokens() async {
    if (_userId.isEmpty || _activeTokens.isEmpty) return {};
    try {
      print('🔄 TokenProvider - Fetching balances for active tokens (matching Kotlin token_view_model.kt)');
      print('🔄 TokenProvider - UserID: $_userId');
      print('🔄 TokenProvider - Active tokens count: ${_activeTokens.length}');
      
      // استفاده از getBalance API مطابق با Kotlin token_view_model.kt
      final response = await apiService.getBalance(
        _userId,
        currencyNames: [], // خالی برای دریافت همه موجودی‌ها مانند Kotlin
        blockchain: {},
      );
      
      print('📥 TokenProvider - API Response:');
      print('   Success: ${response.success}');
      print('   Balances count: ${response.balances?.length ?? 0}');
      
      if (response.success && response.balances != null) {
        final balancesMap = <String, String>{};
        
        print('🔍 TokenProvider - Processing ${response.balances!.length} balance items from getBalance API...');
        
        // پردازش موجودی‌ها و به‌روزرسانی فقط توکن‌های فعال
        for (int i = 0; i < response.balances!.length; i++) {
          final balance = response.balances![i];
          final symbol = balance.symbol ?? '';
          print('   [$i] Processing: Symbol="${symbol}", Balance="${balance.balance}", Blockchain="${balance.blockchain}"');
          
          if (symbol.isNotEmpty) {
            balancesMap[symbol] = balance.balance ?? '0';
            print('   ✅ Added to balancesMap: $symbol = ${balance.balance ?? '0'}');
          } else {
            print('   ❌ Skipped: Symbol is empty');
          }
        }
        
        print('🔍 TokenProvider - Final balancesMap from getBalance: $balancesMap');
        
        // ذخیره موجودی‌ها برای کاربر فعلی
        _userBalances[_userId] = balancesMap;
        
        // به‌روزرسانی موجودی‌ها در توکن‌های فعال
        await _updateTokensWithBalances(balancesMap);
        
        // مرتب‌سازی توکن‌ها بر اساس ارزش دلاری مانند Kotlin
        final sortedTokens = sortTokensByDollarValue(_activeTokens);
        _activeTokens = sortedTokens;
        
        notifyListeners();
        
        print('✅ TokenProvider - Successfully updated ${_activeTokens.length} active tokens');
        return balancesMap;
      }
    } catch (e) {
      _errorMessage = 'Error fetching balances: ${e.toString()}';
      print('❌ TokenProvider - Error fetching balances: $e');
    }
    return {};
  }

  /// به‌روزرسانی موجودی کاربر با استفاده از API update-balance
  Future<bool> updateBalance() async {
    if (_userId.isEmpty) {
      _errorMessage = 'User ID is required for balance update';
      return false;
    }
    
    try {
      print('🔄 TokenProvider - Updating balance using update-balance API for user: $_userId');
      
      // استفاده از update-balance API
      final response = await apiService.updateBalance(_userId);
      
      if (response.success && response.balances != null) {
        print('✅ TokenProvider - Balance updated successfully via update-balance API');
        
        final balancesMap = <String, String>{};
        
        // پردازش موجودی‌ها از پاسخ update-balance API
        print('🔍 TokenProvider - Processing ${response.balances!.length} balance items from update-balance API...');
        for (int i = 0; i < response.balances!.length; i++) {
          final balance = response.balances![i];
          final symbol = balance.symbol ?? '';
          print('   [$i] Processing: Symbol="${symbol}", Balance="${balance.balance}", Blockchain="${balance.blockchain}"');
          
          if (symbol.isNotEmpty) {
            balancesMap[symbol] = balance.balance ?? '0';
            print('   ✅ Added to balancesMap: $symbol = ${balance.balance ?? '0'} (${balance.blockchain ?? 'Unknown'})');
          } else {
            print('   ❌ Skipped: Symbol is empty');
          }
        }
        
        print('🔍 TokenProvider - Final balancesMap: $balancesMap');
        
        // ذخیره موجودی‌ها برای کاربر فعلی
        _userBalances[_userId] = balancesMap;
        
        // به‌روزرسانی موجودی‌ها در توکن‌های فعال و همه توکن‌ها
        await _updateTokensWithBalances(balancesMap);
        
        // مرتب‌سازی توکن‌ها بر اساس ارزش دلاری مانند Kotlin
        final sortedTokens = sortTokensByDollarValue(_activeTokens);
        _activeTokens = sortedTokens;
        
        notifyListeners();
        
        print('✅ TokenProvider - Successfully updated ${_activeTokens.length} active tokens via update-balance');
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to update balance';
        print('❌ TokenProvider - Balance update failed: ${_errorMessage}');
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error updating balance: ${e.toString()}';
      print('❌ TokenProvider - Error updating balance: $e');
      return false;
    }
  }

  /// به‌روزرسانی موجودی فوری برای یک توکن خاص
  Future<bool> updateSingleTokenBalance(CryptoToken token) async {
    if (_userId.isEmpty) {
      _errorMessage = 'User ID is required for balance update';
      return false;
    }
    
    try {
      print('💰 TokenProvider - Updating balance for single token: ${token.symbol}');
      
      // استفاده از getBalance API برای دریافت موجودی توکن خاص
      final response = await apiService.getBalance(
        _userId,
        currencyNames: [token.symbol ?? ''], // فقط این توکن
        blockchain: {},
      );
      
      if (response.success && response.balances != null) {
        print('✅ TokenProvider - Single token balance fetched successfully');
        
        // پیدا کردن موجودی توکن مورد نظر
        for (final balance in response.balances!) {
          final balanceSymbol = balance.symbol ?? '';
          final tokenSymbol = token.symbol ?? '';
          
          if (balanceSymbol.toLowerCase() == tokenSymbol.toLowerCase()) {
            final balanceValue = double.tryParse(balance.balance ?? '0') ?? 0.0;
            
            print('💰 TokenProvider - Found balance for ${token.symbol}: $balanceValue');
            
            // به‌روزرسانی موجودی در activeTokens
            final tokenIndex = _activeTokens.indexWhere((t) => 
              t.symbol == token.symbol && 
              t.blockchainName == token.blockchainName &&
              t.smartContractAddress == token.smartContractAddress
            );
            
            if (tokenIndex != -1) {
              _activeTokens[tokenIndex] = _activeTokens[tokenIndex].copyWith(amount: balanceValue);
              print('✅ TokenProvider - Updated balance in activeTokens for ${token.symbol}');
            }
            
            // به‌روزرسانی در _currencies اگر وجود دارد
            final currencyIndex = _currencies.indexWhere((t) => 
              t.symbol == token.symbol && 
              t.blockchainName == token.blockchainName &&
              t.smartContractAddress == token.smartContractAddress
            );
            
            if (currencyIndex != -1) {
              _currencies[currencyIndex] = _currencies[currencyIndex].copyWith(amount: balanceValue);
              print('✅ TokenProvider - Updated balance in currencies for ${token.symbol}');
            }
            
            // به‌روزرسانی کش موجودی کاربر
            if (!_userBalances.containsKey(_userId)) {
              _userBalances[_userId] = {};
            }
            _userBalances[_userId]![tokenSymbol] = balance.balance ?? '0';
            
            notifyListeners();
            return true;
          }
        }
        
        print('⚠️ TokenProvider - Token ${token.symbol} not found in balance response');
        return false;
      } else {
        _errorMessage = response.message ?? 'Failed to fetch single token balance';
        print('❌ TokenProvider - Single token balance fetch failed: ${_errorMessage}');
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error fetching single token balance: ${e.toString()}';
      print('❌ TokenProvider - Error fetching single token balance: $e');
      return false;
    }
  }

  /// تست API به‌روزرسانی موجودی
  Future<void> testUpdateBalance() async {
    if (_userId.isEmpty) {
      print('❌ Cannot test updateBalance: User ID is empty');
      return;
    }
    
    await apiService.testUpdateBalance(_userId);
  }

  Future<void> _updateTokensWithBalances(Map<String, String> balances) async {
    print('🔍 TokenProvider - _updateTokensWithBalances called with ${balances.length} balances');
    print('🔍 TokenProvider - Available balances: $balances');
    print('🔍 TokenProvider - Current active tokens count: ${_activeTokens.length}');
    print('🔍 TokenProvider - Active tokens symbols: ${_activeTokens.map((t) => t.symbol).toList()}');
    
    // Update currencies
    _currencies = _currencies.map((token) {
      final tokenSymbol = token.symbol ?? '';
      final balance = balances[tokenSymbol] ?? '0.0';
      final balanceDouble = double.tryParse(balance) ?? 0.0;
      print('   Currency: $tokenSymbol -> Balance: $balance (parsed: $balanceDouble)');
      return token.copyWith(amount: balanceDouble);
    }).toList();
    
    // Check for tokens with balance that are not in active tokens yet
    for (final balanceSymbol in balances.keys) {
      final balanceValue = balances[balanceSymbol] ?? '0.0';
      final balanceDouble = double.tryParse(balanceValue) ?? 0.0;
      
      if (balanceDouble > 0.0) {
        // Check if this token exists in active tokens
        final existsInActive = _activeTokens.any((token) => token.symbol == balanceSymbol);
        if (!existsInActive) {
          // Find token in currencies and add to active if enabled
          final currencyToken = _currencies.firstWhere(
            (token) => token.symbol == balanceSymbol,
            orElse: () => CryptoToken(
              name: balanceSymbol,
              symbol: balanceSymbol,
              blockchainName: 'Unknown',
              iconUrl: 'https://coinceeper.com/defualtIcons/coin.png',
              isEnabled: true,
              amount: 0.0,
              isToken: true,
            ),
          );
          
          // Check if token is enabled
          final isEnabled = tokenPreferences.getTokenStateSync(
            currencyToken.symbol ?? '',
            currencyToken.blockchainName ?? '',
            currencyToken.smartContractAddress,
          ) ?? true; // Default to true for tokens with balance
          
          if (isEnabled) {
            print('   🔄 Adding token with balance to active tokens: $balanceSymbol = $balanceDouble');
            _activeTokens.add(currencyToken.copyWith(amount: balanceDouble, isEnabled: true));
            
            // Also save to preferences as enabled
            await tokenPreferences.saveTokenState(
              currencyToken.symbol ?? '',
              currencyToken.blockchainName ?? '',
              currencyToken.smartContractAddress,
              true,
            );
          }
        }
      }
    }
    
    // Update active tokens
    int updatedCount = 0;
    _activeTokens = _activeTokens.map((token) {
      final tokenSymbol = token.symbol ?? '';
      final balance = balances[tokenSymbol] ?? '0.0';
      final balanceDouble = double.tryParse(balance) ?? 0.0;
      
      if (balanceDouble > 0.0) {
        updatedCount++;
        print('   ✅ Active Token Updated: $tokenSymbol -> Balance: $balance (parsed: $balanceDouble)');
      } else {
        print('   ⚪ Active Token Zero Balance: $tokenSymbol -> Balance: $balance (parsed: $balanceDouble)');
      }
      
      return token.copyWith(amount: balanceDouble);
    }).toList();
    
    print('🔍 TokenProvider - Updated $updatedCount active tokens with positive balance');
    print('🔍 TokenProvider - Final active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.amount})').toList()}');
  }

  // --- مرتب‌سازی توکن‌ها بر اساس ارزش دلاری ---
  List<CryptoToken> sortTokensByDollarValue(List<CryptoToken> tokens) {
    return tokens.toList()..sort((a, b) {
      final aValue = (a.amount ?? 0.0) * getTokenPrice(a.symbol ?? '', 'USD');
      final bValue = (b.amount ?? 0.0) * getTokenPrice(b.symbol ?? '', 'USD');
      return bValue.compareTo(aValue); // نزولی
    });
  }

  // --- مدیریت کاربر ---
  Future<void> updateUserId(String newUserId) async {
    if (_userId == newUserId) return;
    _userId = newUserId;
    tokenPreferences = TokenPreferences(userId: newUserId);
    final userTokens = _userTokens[newUserId];
    if (userTokens != null) {
      _currencies = userTokens;
      _activeTokens = userTokens.where((t) => t.isEnabled).toList();
    } else {
      await smartLoadTokens(forceRefresh: true);
    }
    final userBalances = _userBalances[newUserId];
    if (userBalances != null) {
      await _updateTokensWithBalances(userBalances);
    } else {
      await fetchBalancesForActiveTokens();
    }
    notifyListeners();
  }

  // --- همگام‌سازی و force refresh ---
  Future<void> forceRefresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _fetchGasFees();
      await smartLoadTokens(forceRefresh: true);
      await fetchBalancesForActiveTokens();
      await fetchPrices();
      final sortedTokens = sortTokensByDollarValue(_activeTokens);
      _activeTokens = sortedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to refresh data: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> ensureTokensSynchronized() async {
    if (_currencies.isEmpty) {
      final loaded = await _loadFromCache(await SharedPreferences.getInstance());
      if (!loaded) {
        await _loadFromApi(await SharedPreferences.getInstance());
      }
    }
    await updateActiveTokensFromPreferences();
    if (_activeTokens.isEmpty) {
      await _initializeDefaultTokens();
    }
    await fetchPrices();
  }

  // --- متدهای کمکی ---
  String? getAverageChange24h() {
    if (_activeTokens.isEmpty) return null;
    double totalChange = 0.0;
    int validCount = 0;
    for (final token in _activeTokens) {
      final priceData = _tokenPrices[token.symbol]?['USD'];
      if (priceData?.change24h != null) {
        final change = double.tryParse((priceData!.change24h ?? '').replaceAll('%', '')) ?? 0.0;
        totalChange += change;
        validCount++;
      }
    }
    if (validCount > 0) {
      final avg = totalChange / validCount;
      return '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(2)}%';
    }
    return null;
  }

  Future<String> ensureGasFee(String blockchainName) async {
    final currentFee = _gasFees[blockchainName];
    if (currentFee == null || currentFee == '0.0') {
      await _fetchGasFees();
      final updatedFee = _gasFees[blockchainName];
      if (updatedFee == null || updatedFee == '0.0') {
        return _getFallbackGasFee(blockchainName);
      }
      return updatedFee;
    }
    return currentFee;
  }

  String _getFallbackGasFee(String blockchainName) {
    switch (blockchainName) {
      case 'Ethereum': return '0.0012';
      case 'Bitcoin': return '0.0001';
      case 'Tron': return '0.00001';
      case 'Binance': return '0.0005';
      default: return '0.001';
    }
  }

  // --- متدهای باقیمانده ---
  Future<void> resetAllTokenStates() async {
    await tokenPreferences.clearAllTokenStates();
    final defaultTokens = ['Bitcoin', 'Ethereum'];
    for (final tokenName in defaultTokens) {
      await tokenPreferences.saveTokenState(tokenName, tokenName, null, true);
    }
    _currencies = _currencies.map((token) {
      final isDefault = defaultTokens.contains(token.name);
      return token.copyWith(isEnabled: isDefault);
    }).toList();
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    await fetchPrices();
    notifyListeners();
  }

  Future<void> updateTokenOrder(List<CryptoToken> newOrder) async {
    final sortedByValue = sortTokensByDollarValue(newOrder);
    _activeTokens = sortedByValue;
    await tokenPreferences.saveTokenOrder(sortedByValue.map((t) => t.symbol ?? '').toList());
    notifyListeners();
  }

  Future<void> refreshActiveTokens() async {
    final enabledTokens = _currencies.where((t) => t.isEnabled).toList();
    _activeTokens = enabledTokens;
    notifyListeners();
  }



  // --- متدهای debug ---
  void debugBalanceState() {
    print('=== DEBUG BALANCE STATE ===');
    print('User ID: $_userId');
    print('Active tokens count: ${_activeTokens.length}');
    print('Active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.amount})').join(', ')}');
    debugTokenAmounts();
  }

  void debugTokenAmounts() {
    print('=== CURRENT TOKEN AMOUNTS DEBUG ===');
    print('Active Tokens (${_activeTokens.length}):');
    for (int i = 0; i < _activeTokens.length; i++) {
      final token = _activeTokens[i];
      print('  [$i] ${token.symbol} (${token.name}): amount=${token.amount}');
    }
    print('Currencies List (${_currencies.length}):');
    for (int i = 0; i < _currencies.take(10).length; i++) {
      final token = _currencies[i];
      print('  [$i] ${token.symbol} (${token.name}): amount=${token.amount}, enabled=${token.isEnabled}');
    }
  }

  // --- متدهای utility ---
  List<String> getEnabledTokenNames() {
    return tokenPreferences.getAllEnabledTokenNamesSync() ?? [];
  }

  List<String> getEnabledTokenKeys() {
    return tokenPreferences.getAllEnabledTokenKeysSync() ?? [];
  }

  bool isTokenEnabled(CryptoToken token) {
    return tokenPreferences.getTokenStateSync(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
  }

  Future<void> loadTokensWithBalance({bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await smartLoadTokens(forceRefresh: forceRefresh);
      await fetchBalancesForActiveTokens();
      final tokensWithBalance = _activeTokens.where((t) => (t.amount ?? 0.0) > 0).toList();
      final sortedTokens = sortTokensByDollarValue(tokensWithBalance);
      _activeTokens = sortedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error loading tokens with balance: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateActiveTokens(List<CryptoToken> tokens) async {
    _activeTokens = tokens;
    _currencies = _currencies.map((currentToken) {
      final updatedToken = tokens.firstWhere((t) => t.name == currentToken.name, orElse: () => currentToken);
      return currentToken.copyWith(isEnabled: updatedToken.isEnabled);
    }).toList();
    await fetchPrices();
    notifyListeners();
  }

  Future<void> setActiveTokens(List<CryptoToken> newTokens) async {
    _activeTokens = newTokens;
    notifyListeners();
  }

  // --- متدهای کمکی برای مدیریت ترتیب ---
  List<CryptoToken> loadSavedTokenOrder(List<CryptoToken> tokens) {
    final List<String> savedOrder = (tokenPreferences.getTokenOrderSync() ?? []).map((e) => e ?? '').toList();
    if (savedOrder.isEmpty) return tokens;
    final tokenMap = {for (var t in tokens) '${t.symbol ?? ''}_${t.name ?? ''}': t};
    final orderedTokens = <CryptoToken>[];
    for (final symbol in savedOrder) {
      if (tokenMap.containsKey(symbol)) {
        orderedTokens.add(tokenMap[symbol]!);
      }
    }
    for (final token in tokens) {
      if (!orderedTokens.contains(token)) {
        orderedTokens.add(token);
      }
    }
    return orderedTokens;
  }

  Future<void> loadTokens() async {
    try {
      final tokens = await _getTokens();
      final orderedTokens = loadSavedTokenOrder(tokens);
      _activeTokens = orderedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error loading tokens: ${e.toString()}';
    }
  }

  Future<List<CryptoToken>> _getTokens() async {
    try {
      final response = await apiService.getAllCurrencies();
      if (response.success) {
        return response.currencies.map<CryptoToken>((token) {
          final isEnabled = tokenPreferences.getTokenStateSync(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
          return CryptoToken(
            name: token.currencyName,
            symbol: token.symbol,
            blockchainName: token.blockchainName,
            iconUrl: token.icon ?? 'https://coinceeper.com/defualtIcons/coin.png',
            isEnabled: isEnabled,
            isToken: token.isToken ?? true,
            smartContractAddress: token.smartContractAddress,
          );
        }).toList();
      }
    } catch (e) {
      _errorMessage = 'Error getting tokens: ${e.toString()}';
    }
    return [];
  }

  // --- متدهای کمکی برای مدیریت کاربر ---
  void saveUserTokens(String userId, List<CryptoToken> tokens) {
    _userTokens[userId] = tokens;
  }

  void saveUserBalances(String userId, Map<String, String> balances) {
    _userBalances[userId] = balances;
  }

  String getCurrentUserId() => _userId;

  // --- متدهای کمکی برای مدیریت وضعیت توکن ---
  bool getTokenStateForUser(CryptoToken token) {
    return tokenPreferences.getTokenStateSync(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
  }

  Future<void> saveTokenStateForUser(CryptoToken token, bool isEnabled) async {
    await tokenPreferences.saveTokenState(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress, isEnabled);
  }

  void setActiveTokensForUser(List<CryptoToken> tokens) {
    _activeTokens = tokens;
    _userTokens[_userId] = tokens;
  }

  // --- متدهای سازگاری با کد موجود ---
  void setAllTokens(List<CryptoToken> allTokens) {
    _currencies = allTokens;
    _activeTokens = allTokens.where((t) => t.isEnabled).toList();
    notifyListeners();
  }
  
  // متد جدید برای اطمینان از به‌روزرسانی فوری
  Future<void> forceUpdateTokenStates() async {
    print('🔄 Force updating token states...');
    
    // به‌روزرسانی وضعیت توکن‌ها از preferences
    _currencies = _currencies.map((token) {
      final isEnabled = tokenPreferences.getTokenStateSync(
        token.symbol ?? '', 
        token.blockchainName ?? '', 
        token.smartContractAddress
      ) ?? false;
      return token.copyWith(isEnabled: isEnabled);
    }).toList();
    
    // به‌روزرسانی توکن‌های فعال
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    
    print('🔄 Force update - Active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
    
    // اگر توکن‌های فعال وجود دارند، قیمت‌ها را دریافت کن
    if (_activeTokens.isNotEmpty) {
      await fetchPrices();
    }
    
    notifyListeners();
  }
} 