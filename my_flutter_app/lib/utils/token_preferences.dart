import 'package:shared_preferences/shared_preferences.dart';

/// کلاس مدیریت تنظیمات توکن‌ها
class TokenPreferences {
  final String userId;
  static const String _tokenOrderKey = 'token_order';
  static const String _tokenStatePrefix = 'token_state_';
  
  // Cache for token states to support sync operations
  static final Map<String, bool> _tokenStateCache = {};

  TokenPreferences({required this.userId});
  
  /// Initialize the TokenPreferences
  Future<void> initialize() async {
    await _initializeCache();
  }
  
  /// Initialize cache from SharedPreferences
  Future<void> _initializeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix)) {
          final value = prefs.getBool(key);
          if (value != null) {
            _tokenStateCache[key] = value;
          }
        }
      }
      
      // Initialize default tokens if no tokens are configured
      if (_tokenStateCache.isEmpty) {
        await _initializeDefaultTokens();
      }
    } catch (e) {
      // If initialization fails, use default tokens
      await _initializeDefaultTokens();
    }
  }
  
  /// Initialize default tokens
  Future<void> _initializeDefaultTokens() async {
    final defaultTokens = ['BTC', 'ETH'];
    for (final symbol in defaultTokens) {
      await saveTokenState(symbol, symbol, null, true);
    }
  }

  /// ذخیره وضعیت توکن
  Future<void> saveTokenState(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    await prefs.setBool(key, isEnabled);
    
    // Update cache for sync operations
    _tokenStateCache[key] = isEnabled;
  }

  /// دریافت وضعیت توکن
  Future<bool?> getTokenState(String symbol, String blockchainName, String? smartContractAddress) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    final result = prefs.getBool(key);
    
    // Update cache for sync operations
    if (result != null) {
      _tokenStateCache[key] = result;
    }
    
    return result;
  }

  /// دریافت وضعیت توکن (sync)
  bool? getTokenStateSync(String symbol, String blockchainName, String? smartContractAddress) {
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    
    // Check cache first
    if (_tokenStateCache.containsKey(key)) {
      return _tokenStateCache[key];
    }
    
    // If not in cache, check default tokens
    final defaultTokens = ['BTC', 'ETH'];
    if (defaultTokens.contains(symbol?.toUpperCase())) {
      _tokenStateCache[key] = true;
      return true;
    }
    
    // Default to disabled
    _tokenStateCache[key] = false;
    return false;
  }

  /// ذخیره ترتیب توکن‌ها
  Future<void> saveTokenOrder(List<String> tokenSymbols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${_tokenOrderKey}_$userId', tokenSymbols);
  }

  /// دریافت ترتیب توکن‌ها
  Future<List<String>> getTokenOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('${_tokenOrderKey}_$userId') ?? [];
  }

  /// دریافت ترتیب توکن‌ها (sync)
  List<String> getTokenOrderSync() {
    // این متد sync نیست، اما برای سازگاری با کد موجود استفاده می‌شود
    return <String>[]; // همیشه لیست خالی غیرnullable برگردان
  }

  /// دریافت تمام نام‌های توکن‌های فعال
  Future<List<String>> getAllEnabledTokenNames() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final enabledTokens = <String>[];
    
    for (final key in keys) {
      if (key.startsWith(_tokenStatePrefix) && prefs.getBool(key) == true) {
        final tokenName = key.replaceFirst(_tokenStatePrefix, '');
        enabledTokens.add(tokenName);
      }
    }
    
    return enabledTokens;
  }

  /// دریافت تمام کلیدهای توکن‌های فعال
  Future<List<String>> getAllEnabledTokenKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final enabledKeys = <String>[];
    
    for (final key in keys) {
      if (key.startsWith(_tokenStatePrefix) && prefs.getBool(key) == true) {
        enabledKeys.add(key);
      }
    }
    
    return enabledKeys;
  }

  /// دریافت تمام نام‌های توکن‌های فعال (sync)
  List<String> getAllEnabledTokenNamesSync() {
    return <String>[];
  }

  /// دریافت تمام کلیدهای توکن‌های فعال (sync)
  List<String> getAllEnabledTokenKeysSync() {
    return <String>[];
  }

  /// پاک کردن تمام تنظیمات توکن‌ها
  Future<void> clearAllTokenStates() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    for (final key in keys) {
      if (key.startsWith(_tokenStatePrefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// تولید کلید منحصر به فرد برای توکن
  String _getTokenKey(String symbol, String blockchainName, String? smartContractAddress) {
    return '${_tokenStatePrefix}${symbol}_${blockchainName}_${smartContractAddress ?? ''}';
  }
} 