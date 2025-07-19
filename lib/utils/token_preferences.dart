import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../services/secure_storage.dart';

/// کلاس مدیریت تنظیمات توکن‌ها
class TokenPreferences {
  final String userId;
  static const String _tokenOrderKey = 'token_order';
  static const String _tokenStatePrefix = 'token_state_';
  
  // Cache for token states to support sync operations - per user instance
  final Map<String, bool> _tokenStateCache = {};
  bool _cacheInitialized = false;

  TokenPreferences({required this.userId});
  
  /// Initialize the TokenPreferences
  Future<void> initialize() async {
    if (!_cacheInitialized) {
      await _initializeCache();
      _cacheInitialized = true;
    }
  }
  
  /// Initialize cache from SharedPreferences
  Future<void> _initializeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // Clear existing cache
      _tokenStateCache.clear();
      
      // Only load keys for this user
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix) && key.contains(userId)) {
          final value = prefs.getBool(key);
          if (value != null) {
            _tokenStateCache[key] = value;
          }
        }
      }
      
      print('🔄 TokenPreferences: Initialized cache for user $userId with ${_tokenStateCache.length} token states from SharedPreferences');
      
      // iOS: Also try to load from SecureStorage and merge
      if (Platform.isIOS) {
        await _loadFromSecureStorageOnIOS(prefs);
      }
      
      // Initialize default tokens if no tokens are configured for this user
      if (_tokenStateCache.isEmpty) {
        await _initializeDefaultTokens();
      }
    } catch (e) {
      print('❌ TokenPreferences: Error initializing cache for user $userId: $e');
      // If initialization fails, use default tokens
      await _initializeDefaultTokens();
    }
  }

  /// iOS-specific: Load token states from SecureStorage and merge with SharedPreferences
  Future<void> _loadFromSecureStorageOnIOS(SharedPreferences prefs) async {
    try {
      // Get all keys from SecureStorage (this is a simplified approach)
      // In reality, we need to iterate through possible keys since SecureStorage doesn't provide getAllKeys()
      final defaultTokens = ['BTC', 'ETH', 'TRX'];
      final blockchains = ['Bitcoin', 'Ethereum', 'Tron'];
      
      for (int i = 0; i < defaultTokens.length; i++) {
        final symbol = defaultTokens[i];
        final blockchain = blockchains[i];
        final key = _getTokenKey(symbol, blockchain, null);
        
        // Check if we already have this from SharedPreferences
        if (!_tokenStateCache.containsKey(key)) {
          final secureValue = await SecureStorage.instance.getSecureData(key);
          if (secureValue != null) {
            final boolValue = secureValue.toLowerCase() == 'true';
            _tokenStateCache[key] = boolValue;
            
            // Sync back to SharedPreferences
            await prefs.setBool(key, boolValue);
            
            print('🍎 TokenPreferences: Recovered from SecureStorage (iOS): $key = $boolValue');
          }
        }
      }
      
      print('🍎 TokenPreferences: iOS SecureStorage recovery completed. Total cache: ${_tokenStateCache.length}');
    } catch (e) {
      print('❌ TokenPreferences: Error loading from SecureStorage on iOS: $e');
    }
  }
  
  /// Initialize default tokens for this user
  Future<void> _initializeDefaultTokens() async {
    try {
      final defaultTokens = {
        'BTC': {'name': 'Bitcoin', 'blockchain': 'Bitcoin'},
        'ETH': {'name': 'Ethereum', 'blockchain': 'Ethereum'},
        'TRX': {'name': 'Tron', 'blockchain': 'Tron'},
      };
      
      for (final entry in defaultTokens.entries) {
        final symbol = entry.key;
        final tokenInfo = entry.value;
        
        await saveTokenState(
          symbol, 
          tokenInfo['blockchain']!, 
          null, 
          true
        );
        
        print('✅ TokenPreferences: Initialized default token for user $userId: $symbol');
      }
      
      print('✅ TokenPreferences: All default tokens initialized for user $userId');
    } catch (e) {
      print('❌ TokenPreferences: Error initializing default tokens for user $userId: $e');
    }
  }

  /// Save token state with iOS dual storage support
  Future<void> saveTokenState(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) async {
    try {
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      
      // Always save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, isEnabled);
      
      // iOS: Also save to SecureStorage for better persistence
      if (Platform.isIOS) {
        await SecureStorage.instance.saveSecureData(key, isEnabled.toString());
        print('🍎 TokenPreferences: Saved to both SharedPreferences and SecureStorage (iOS): $key = $isEnabled');
      }
      
      // Update cache
      _tokenStateCache[key] = isEnabled;
      
      print('✅ TokenPreferences: Token state saved for user $userId: ${symbol}_${blockchainName} = $isEnabled');
    } catch (e) {
      print('❌ TokenPreferences: Error saving token state for user $userId: $e');
      rethrow;
    }
  }

  /// Get token state with iOS dual storage support
  Future<bool> getTokenState(String symbol, String blockchainName, String? smartContractAddress) async {
    try {
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      
      // First try SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      bool? sharedPrefsValue = prefs.getBool(key);
      
      // iOS: If SharedPreferences fails, try SecureStorage
      if (Platform.isIOS && sharedPrefsValue == null) {
        final secureValue = await SecureStorage.instance.getSecureData(key);
        if (secureValue != null) {
          final boolValue = secureValue.toLowerCase() == 'true';
          print('🍎 TokenPreferences: Retrieved from SecureStorage (iOS): $key = $boolValue');
          
          // Sync back to SharedPreferences
          await prefs.setBool(key, boolValue);
          sharedPrefsValue = boolValue;
        }
      }
      
      // Update cache
      if (sharedPrefsValue != null) {
        _tokenStateCache[key] = sharedPrefsValue;
      }
      
      return sharedPrefsValue ?? false;
    } catch (e) {
      print('❌ TokenPreferences: Error getting token state for user $userId: $e');
      return false;
    }
  }

  /// دریافت وضعیت توکن (sync) - بهبود یافته
  bool? getTokenStateSync(String symbol, String blockchainName, String? smartContractAddress) {
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    
    // Check cache first
    if (_tokenStateCache.containsKey(key)) {
      return _tokenStateCache[key];
    }
    
    // If not in cache and cache is initialized, check default tokens
    if (_cacheInitialized) {
      final defaultTokens = ['BTC', 'ETH', 'TRX'];
      if (defaultTokens.contains(symbol?.toUpperCase())) {
        _tokenStateCache[key] = true;
        // Also save to SharedPreferences for persistence
        _saveTokenStateInBackground(symbol, blockchainName, smartContractAddress, true);
        return true;
      }
      
      // Default to disabled for non-default tokens
      _tokenStateCache[key] = false;
      return false;
    }
    
    // If cache not initialized, return null to indicate uncertainty
    return null;
  }

  /// ذخیره وضعیت توکن در background (برای sync methods)
  void _saveTokenStateInBackground(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) {
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
        await prefs.setBool(key, isEnabled);
      } catch (e) {
        print('❌ TokenPreferences: Error saving token state in background for $symbol: $e');
      }
    });
  }

  /// ذخیره ترتیب توکن‌ها
  Future<void> saveTokenOrder(List<String> tokenSymbols) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('${_tokenOrderKey}_$userId', tokenSymbols);
      print('✅ TokenPreferences: Saved token order with ${tokenSymbols.length} tokens');
    } catch (e) {
      print('❌ TokenPreferences: Error saving token order: $e');
    }
  }

  /// دریافت ترتیب توکن‌ها
  Future<List<String>> getTokenOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('${_tokenOrderKey}_$userId') ?? [];
    } catch (e) {
      print('❌ TokenPreferences: Error getting token order: $e');
      return [];
    }
  }

  /// دریافت ترتیب توکن‌ها (sync) - بهبود یافته
  List<String>? getTokenOrderSync() {
    // We can't do sync SharedPreferences operations, so return null
    // This indicates that async method should be used
    return null;
  }

  /// دریافت تمام نام‌های توکن‌های فعال
  Future<List<String>> getAllEnabledTokenNames() async {
    try {
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
    } catch (e) {
      print('❌ TokenPreferences: Error getting enabled token names: $e');
      return [];
    }
  }

  /// دریافت تمام کلیدهای توکن‌های فعال
  Future<List<String>> getAllEnabledTokenKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final enabledKeys = <String>[];
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix) && prefs.getBool(key) == true) {
          enabledKeys.add(key);
        }
      }
      
      return enabledKeys;
    } catch (e) {
      print('❌ TokenPreferences: Error getting enabled token keys: $e');
      return [];
    }
  }

  /// دریافت تمام نام‌های توکن‌های فعال (sync) - بهبود یافته
  List<String>? getAllEnabledTokenNamesSync() {
    if (!_cacheInitialized) return null;
    
    final enabledTokens = <String>[];
    
    for (final entry in _tokenStateCache.entries) {
      if (entry.value == true) {
        // Extract token name from key
        final tokenName = entry.key.replaceFirst(_tokenStatePrefix, '');
        enabledTokens.add(tokenName);
      }
    }
    
    return enabledTokens;
  }

  /// دریافت تمام کلیدهای توکن‌های فعال (sync) - بهبود یافته
  List<String>? getAllEnabledTokenKeysSync() {
    if (!_cacheInitialized) return null;
    
    final enabledKeys = <String>[];
    
    for (final entry in _tokenStateCache.entries) {
      if (entry.value == true) {
        enabledKeys.add(entry.key);
      }
    }
    
    return enabledKeys;
  }

  /// پاک کردن تمام تنظیمات توکن‌ها
  Future<void> clearAllTokenStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix)) {
          await prefs.remove(key);
        }
      }
      
      // Clear cache
      _tokenStateCache.clear();
      
      print('✅ TokenPreferences: Cleared all token states');
    } catch (e) {
      print('❌ TokenPreferences: Error clearing token states: $e');
    }
  }

  /// بازنشانی cache (برای debug یا refresh)
  Future<void> refreshCache() async {
    _cacheInitialized = false;
    await _initializeCache();
    _cacheInitialized = true;
  }

  /// تولید کلید منحصر به فرد برای توکن
  String _getTokenKey(String symbol, String blockchainName, String? smartContractAddress) {
    return '${_tokenStatePrefix}${userId}_${symbol}_${blockchainName}_${smartContractAddress ?? ''}';
  }
  
  /// بررسی اینکه آیا cache مقداردهی اولیه شده است
  bool get isCacheInitialized => _cacheInitialized;
} 