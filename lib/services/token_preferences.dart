import 'package:shared_preferences/shared_preferences.dart';
import '../models/crypto_token.dart';

/// مدیریت تنظیمات توکن‌ها (معادل TokenPreferences.kt در اندروید)
class TokenPreferences {
  final String userId;
  late SharedPreferences _prefs;
  static const String _tokenOrderKey = 'token_order';
  static const String _prefsPrefix = 'token_preferences_';

  // کش داخلی برای کاهش فراخوانی‌های SharedPreferences
  Map<String, bool>? _enabledTokensCache;
  int _lastCacheTime = 0;
  static const int _cacheValidityPeriod = 5 * 60 * 1000; // 5 دقیقه

  TokenPreferences({required this.userId});

  /// مقداردهی اولیه
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _initializeDefaultTokens();
    _loadEnabledTokensCache();
  }

  /// مقداردهی توکن‌های پیش‌فرض
  void _initializeDefaultTokens() {
    final defaultTokens = ['Bitcoin', 'Ethereum', 'Netcoincapital'];
    bool needsCommit = false;

    for (final token in defaultTokens) {
      if (!_prefs.containsKey(token)) {
        _prefs.setBool(token, true);
        needsCommit = true;
      }
    }

    if (needsCommit) {
      _prefs.commit();
    }
  }

  /// بارگذاری کش داخلی از SharedPreferences
  void _loadEnabledTokensCache() {
    final allKeys = _prefs.getKeys();
    _enabledTokensCache = <String, bool>{};
    
    for (final key in allKeys) {
      if (key != _tokenOrderKey && !key.startsWith('last_')) {
        _enabledTokensCache![key] = _prefs.getBool(key) ?? false;
      }
    }
    
    _lastCacheTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// بررسی اعتبار کش داخلی
  bool _isCacheValid() {
    return _enabledTokensCache != null && 
           (DateTime.now().millisecondsSinceEpoch - _lastCacheTime) < _cacheValidityPeriod;
  }

  /// تولید کلید منحصر به فرد برای هر توکن (شامل SmartContractAddress)
  String getTokenKey(CryptoToken token) {
    return "${token.symbol}_${token.blockchainName ?? 'Unknown'}_${token.smartContractAddress ?? ""}";
  }

  /// تولید کلید منحصر به فرد با پارامترهای جداگانه
  String getTokenKeyFromParams(String symbol, String blockchainName, String? contract) {
    return "${symbol}_${blockchainName}_${contract ?? ""}";
  }

  /// ذخیره ترتیب توکن‌ها
  Future<void> saveTokenOrder(List<String> tokenOrder) async {
    final orderString = tokenOrder.join(",");
    await _prefs.setString(_tokenOrderKey, orderString);
  }

  /// دریافت ترتیب توکن‌ها
  List<String> getTokenOrder() {
    final orderString = _prefs.getString(_tokenOrderKey) ?? "";
    if (orderString.isEmpty) {
      return [];
    }
    return orderString.split(",");
  }

  /// ذخیره وضعیت توکن با کلید کامل
  Future<void> saveTokenState(String tokenKey, bool isEnabled) async {
    await _prefs.setBool(tokenKey, isEnabled);
    _enabledTokensCache?[tokenKey] = isEnabled;
  }

  /// ذخیره وضعیت توکن با پارامترهای جداگانه
  Future<void> saveTokenStateFromParams(String symbol, String blockchainName, String? contract, bool isEnabled) async {
    final key = getTokenKeyFromParams(symbol, blockchainName, contract);
    await _prefs.setBool(key, isEnabled);
    _enabledTokensCache?[key] = isEnabled;
  }

  /// ذخیره وضعیت توکن با استفاده از CryptoToken
  Future<void> saveTokenStateFromToken(CryptoToken token, bool isEnabled) async {
    final key = getTokenKey(token);
    await _prefs.setBool(key, isEnabled);
    _enabledTokensCache?[key] = isEnabled;
  }

  /// دریافت وضعیت توکن با کلید کامل
  bool getTokenState(String tokenKey) {
    // استفاده از کش داخلی اگر معتبر است
    if (_isCacheValid() && _enabledTokensCache?.containsKey(tokenKey) == true) {
      return _enabledTokensCache![tokenKey] ?? false;
    }
    final isEnabled = _prefs.getBool(tokenKey) ?? false;
    if (_enabledTokensCache == null) {
      _loadEnabledTokensCache();
    } else {
      _enabledTokensCache![tokenKey] = isEnabled;
    }
    return isEnabled;
  }

  /// دریافت وضعیت توکن با پارامترهای جداگانه
  bool getTokenStateFromParams(String symbol, String blockchainName, String? contract) {
    final key = getTokenKeyFromParams(symbol, blockchainName, contract);
    return getTokenState(key);
  }

  /// دریافت وضعیت توکن با استفاده از CryptoToken
  bool getTokenStateFromToken(CryptoToken token) {
    final key = getTokenKey(token);
    return getTokenState(key);
  }

  /// دریافت تمام کلیدهای توکن‌های فعال
  List<String> getAllEnabledTokenKeys() {
    // اگر کش معتبر نیست، آن را بارگذاری کنیم
    if (!_isCacheValid()) {
      _loadEnabledTokensCache();
    }
    
    // استفاده از کش داخلی برای بهینه‌سازی
    return _enabledTokensCache?.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList() ?? [];
  }

  /// دریافت تمام نام‌های توکن‌های فعال
  List<String> getAllEnabledTokenNames() {
    return getAllEnabledTokenKeys();
  }

  /// دریافت تمام توکن‌های فعال از لیست کامل
  List<CryptoToken> getAllEnabledTokens(List<CryptoToken> allTokens) {
    // ابتدا لیست کلیدهای توکن‌های فعال را بگیریم
    final enabledKeys = getAllEnabledTokenKeys();
    // فیلتر کردن توکن‌ها بر اساس فعال بودن با کلید ترکیبی
    return allTokens.map((token) {
      final key = getTokenKey(token);
      return token.copyWith(isEnabled: enabledKeys.contains(key));
    }).where((token) => token.isEnabled).toList();
  }

  /// فعال کردن توکن
  Future<void> enableToken(CryptoToken token) async {
    await saveTokenStateFromToken(token, true);
  }

  /// غیرفعال کردن توکن
  Future<void> disableToken(CryptoToken token) async {
    await saveTokenStateFromToken(token, false);
  }

  /// تغییر وضعیت توکن (toggle)
  Future<void> toggleTokenState(CryptoToken token) async {
    final currentState = getTokenStateFromToken(token);
    await saveTokenStateFromToken(token, !currentState);
  }

  /// بررسی اینکه آیا توکن فعال است یا نه
  bool isTokenEnabled(CryptoToken token) {
    return getTokenStateFromToken(token);
  }

  /// دریافت تعداد توکن‌های فعال
  int getEnabledTokenCount() {
    return getAllEnabledTokenKeys().length;
  }

  /// پاک کردن تمام تنظیمات توکن‌ها
  Future<void> clearAllTokenPreferences() async {
    final allKeys = _prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('token_') || key == _tokenOrderKey) {
        await _prefs.remove(key);
      }
    }
    _enabledTokensCache?.clear();
  }

  /// دریافت توکن‌های فعال بر اساس بلاکچین
  List<CryptoToken> getEnabledTokensByBlockchain(List<CryptoToken> allTokens, String blockchainName) {
    final enabledTokens = getAllEnabledTokens(allTokens);
    return enabledTokens.where((token) => (token.blockchainName ?? 'Unknown') == blockchainName).toList();
  }

  /// ذخیره ترتیب توکن‌ها بر اساس لیست CryptoToken
  Future<void> saveTokenOrderFromTokens(List<CryptoToken> tokens) async {
    final tokenKeys = tokens.map((token) => getTokenKey(token)).toList();
    await saveTokenOrder(tokenKeys);
  }

  /// دریافت ترتیب توکن‌ها به صورت CryptoToken
  List<CryptoToken> getTokenOrderAsTokens(List<CryptoToken> allTokens) {
    final orderKeys = getTokenOrder();
    final orderedTokens = <CryptoToken>[];
    
    for (final key in orderKeys) {
      final token = allTokens.firstWhere(
        (token) => getTokenKey(token) == key,
        orElse: () => allTokens.first, // fallback
      );
      orderedTokens.add(token);
    }
    
    return orderedTokens;
  }

  /// به‌روزرسانی وضعیت چندین توکن همزمان
  Future<void> updateMultipleTokenStates(Map<CryptoToken, bool> tokenStates) async {
    for (final entry in tokenStates.entries) {
      await saveTokenStateFromToken(entry.key, entry.value);
    }
  }

  /// دریافت آمار توکن‌ها
  Map<String, dynamic> getTokenStatistics(List<CryptoToken> allTokens) {
    final enabledTokens = getAllEnabledTokens(allTokens);
    final totalTokens = allTokens.length;
    final enabledCount = enabledTokens.length;
    
    // گروه‌بندی بر اساس بلاکچین
    final blockchainGroups = <String, int>{};
    for (final token in enabledTokens) {
      final blockchainName = token.blockchainName ?? 'Unknown';
      blockchainGroups[blockchainName] = (blockchainGroups[blockchainName] ?? 0) + 1;
    }
    
    return {
      'totalTokens': totalTokens,
      'enabledTokens': enabledCount,
      'disabledTokens': totalTokens - enabledCount,
      'blockchainDistribution': blockchainGroups,
      'enabledPercentage': totalTokens > 0 ? (enabledCount / totalTokens * 100).roundToDouble() : 0.0,
    };
  }

  /// بررسی تغییرات در تنظیمات توکن‌ها
  Future<bool> hasTokenPreferencesChanged() async {
    final lastUpdate = _prefs.getInt('last_token_preferences_update') ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return (currentTime - lastUpdate) > 300000; // 5 دقیقه
  }

  /// ذخیره زمان آخرین به‌روزرسانی
  Future<void> updateLastPreferencesTime() async {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt('last_token_preferences_update', currentTime);
  }

  /// تبدیل ApiCurrency به CryptoToken (مشابه Helper.kt)
  CryptoToken toCryptoToken(Map<String, dynamic> apiCurrency) {
    final symbol = apiCurrency['Symbol'] ?? '';
    final blockchainName = apiCurrency['BlockchainName'] ?? '';
    final smartContractAddress = apiCurrency['SmartContractAddress'];
    final isEnabled = getTokenStateFromParams(symbol, blockchainName, smartContractAddress);
    
    return CryptoToken(
      name: apiCurrency['CurrencyName'] ?? '',
      symbol: symbol,
      blockchainName: blockchainName,
      iconUrl: apiCurrency['Icon'] ?? 'https://coinceeper.com/defualtIcons/coin.png',
      isEnabled: isEnabled,
      amount: 0.0,
      isToken: apiCurrency['IsToken'] ?? true,
      smartContractAddress: smartContractAddress,
    );
  }
}

/// Extension function برای تبدیل ApiCurrency به CryptoToken (مشابه Helper.kt)
extension ApiCurrencyExtension on Map<String, dynamic> {
  CryptoToken toCryptoToken() {
    return CryptoToken(
      name: this['CurrencyName'] ?? '',
      symbol: this['Symbol'] ?? '',
      blockchainName: this['BlockchainName'] ?? '',
      iconUrl: this['Icon'] ?? 'https://coinceeper.com/defualtIcons/coin.png',
      isEnabled: false,
      amount: 0.0,
      isToken: this['IsToken'] ?? true,
      smartContractAddress: this['SmartContractAddress'],
    );
  }
} 