import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/secure_storage.dart';
import '../services/lifecycle_manager.dart';
import '../services/permission_manager.dart';
import '../models/crypto_token.dart';
import '../services/api_service.dart';
import '../services/balance_manager.dart';
import 'token_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wallet_state_manager.dart'; // Added import for WalletStateManager

/// Provider اصلی اپلیکیشن
class AppProvider extends ChangeNotifier {
  // ==================== STATE VARIABLES ====================
  
  // مقداردهی اولیه
  bool _isInitialized = false;
  bool _isInitializing = false;
  
  // کیف پول
  String? _currentWalletName;
  String? _currentUserId;
  List<Map<String, String>> _wallets = [];
  
  // امنیت
  bool _isLocked = false;
  bool _isBiometricEnabled = false;
  int _autoLockTimeout = 5; // دقیقه
  
  // شبکه
  bool _isOnline = true;
  String _connectionType = 'Unknown';
  
  // نوتیفیکیشن
  bool _pushNotificationsEnabled = true;
  String? _deviceToken;
  
  // زبان و تنظیمات
  String _currentLanguage = 'en';
  String _currentCurrency = 'USD';
  
  // API
  final ApiService _apiService = ApiService();
  
  // TokenProvider management
  final Map<String, TokenProvider> _tokenProviders = {};
  TokenProvider? _currentTokenProvider;
  
  // ==================== GETTERS ====================
  
  // مقداردهی اولیه
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  
  String? get currentWalletName => _currentWalletName;
  String? get currentUserId => _currentUserId;
  List<Map<String, String>> get wallets => _wallets;
  bool get isLocked => _isLocked;
  bool get isBiometricEnabled => _isBiometricEnabled;
  int get autoLockTimeout => _autoLockTimeout;
  bool get isOnline => _isOnline;
  String get connectionType => _connectionType;
  bool get pushNotificationsEnabled => _pushNotificationsEnabled;
  String? get deviceToken => _deviceToken;
  String get currentLanguage => _currentLanguage;
  String get currentCurrency => _currentCurrency;
  ApiService get apiService => _apiService;
  
  // TokenProvider getter
  TokenProvider? get tokenProvider => _currentTokenProvider;
  
  // ==================== INITIALIZATION ====================
  
  /// مقداردهی اولیه Provider
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    
    _isInitializing = true;
    notifyListeners();
    
    try {
      await _loadAppState();
      await _setupLifecycleManager();
      await _checkPermissions();
      await _loadWallets();
      
      // Initialize TokenProvider for current user (non-blocking)
      _initializeTokenProviderInBackground();
      
      _isInitialized = true;
      print('🚀 AppProvider initialized (TokenProvider loading in background)');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }
  
  /// مقداردهی اولیه TokenProvider در background - مشابه Kotlin
  void _initializeTokenProviderInBackground() {
    if (_currentUserId != null) {
      print('🔄 AppProvider: Starting TokenProvider initialization for user: $_currentUserId');
      
      // Initialize TokenProvider in background without blocking UI
      _getOrCreateTokenProvider(_currentUserId!).then((tokenProvider) {
        print('✅ AppProvider: TokenProvider initialized in background');
        
        // اطمینان از synchronization فوری
        tokenProvider.ensureTokensSynchronized().then((_) {
          print('✅ AppProvider: TokenProvider synchronization completed');
        }).catchError((error) {
          print('❌ AppProvider: TokenProvider synchronization failed: $error');
        });
        
      }).catchError((error) {
        print('❌ AppProvider: TokenProvider initialization failed: $error');
      });
    }
  }
  
  /// مقداردهی اولیه TokenProvider (deprecated - use background version)
  Future<void> _initializeTokenProvider() async {
    if (_currentUserId != null) {
      await _getOrCreateTokenProvider(_currentUserId!);
    }
  }
  
  /// دریافت یا ایجاد TokenProvider برای کاربر
  Future<TokenProvider> _getOrCreateTokenProvider(String userId) async {
    if (_tokenProviders.containsKey(userId)) {
      _currentTokenProvider = _tokenProviders[userId]!;
      return _currentTokenProvider!;
    }
    
    print('🔄 AppProvider: Creating new TokenProvider for user: $userId');
    final tokenProvider = TokenProvider(
      userId: userId,
      apiService: _apiService,
      context: null, // We'll handle context differently
    );
    
    // Listen to TokenProvider changes and propagate to AppProvider
    tokenProvider.addListener(_onTokenProviderChanged);
    
    _tokenProviders[userId] = tokenProvider;
    _currentTokenProvider = tokenProvider;
    
    // Initialize TokenProvider completely BEFORE making it available
    print('🔄 AppProvider: Initializing TokenProvider synchronously...');
    await tokenProvider.initializeInBackground();
    
    // Additional synchronization to ensure tokens are loaded
    await tokenProvider.ensureTokensSynchronized();

    // 🔁 Restore per-wallet active tokens and cached balances if available (app start case)
    try {
      if (_currentWalletName != null && _currentUserId != null) {
        // Read active tokens directly without requiring mnemonic (iOS can restrict keychain reads)
        final activeTokens = await SecureStorage.instance.getActiveTokens(
          _currentWalletName!, _currentUserId!,
        );
        final balanceCache = await SecureStorage.instance.getWalletBalanceCache(
          _currentWalletName!, _currentUserId!,
        );

        if (activeTokens.isNotEmpty) {
          await _applyActiveTokensToProvider(tokenProvider, activeTokens);
        }
        if (balanceCache.isNotEmpty) {
          print('🔍 AppProvider DEBUG: Applying balance cache: $balanceCache');
          await _applyBalanceCacheToProvider(tokenProvider, balanceCache);
          print('🔍 AppProvider DEBUG: Balance cache applied to TokenProvider');
        } else {
          print('🔍 AppProvider DEBUG: No balance cache found for wallet');
          
          // اگر هیچ موجودی cache شده‌ای نداریم، یک بار API balance فراخوانی کن
          print('💰 AppProvider: No cached balances found, fetching from API once...');
          try {
            final balances = await tokenProvider.fetchBalancesForActiveTokens();
            print('✅ AppProvider: Fresh balances fetched: $balances');
          } catch (e) {
            print('⚠️ AppProvider: Error fetching fresh balances: $e');
          }
        }
      }
    } catch (e) {
      print('❌ AppProvider: Error restoring per-wallet data on init: $e');
    }

    // ⚠️ REMOVED: update-balance دیگر در startup فراخوانی نمی‌شود
    // فقط در ImportWalletScreen بعد از import wallet فراخوانی می‌شود
    print('ℹ️ AppProvider: Skipping startup update-balance - only called after wallet import');
    
    // 🏷️ بلافاصله قیمت‌ها را بارگذاری کن در PriceProvider (تا HomeScreen آن‌ها را ببیند)
    print('💰 AppProvider: Fetching prices immediately for enabled tokens...');
    try {
      final enabledSymbols = tokenProvider.enabledTokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
      if (enabledSymbols.isNotEmpty) {
        print('💰 AppProvider: Fetching prices for symbols: $enabledSymbols');
        
        // فقط TokenProvider را به‌روزرسانی کن - PriceProvider در HomeScreen به‌روزرسانی می‌شود
        await tokenProvider.fetchPrices(activeSymbols: enabledSymbols);
        
        print('✅ AppProvider: Prices fetched successfully in both providers');
      } else {
        print('⚠️ AppProvider: No enabled tokens found for price fetching');
      }
    } catch (e) {
      print('❌ AppProvider: Error fetching prices: $e');
    }
    
    print('✅ AppProvider: TokenProvider fully synchronized for user: $userId');
    print('✅ AppProvider: Enabled tokens count: ${tokenProvider.enabledTokens.length}');
    print('✅ AppProvider: Enabled tokens: ${tokenProvider.enabledTokens.map((t) => t.symbol).join(', ')}');
    
    // NOW notify listeners that TokenProvider is ready
    notifyListeners();
    
    return tokenProvider;
  }

  // ⚠️ REMOVED: _startupUpdateBalanceWithRetry - دیگر در startup استفاده نمی‌شود
  // update-balance فقط در ImportWalletScreen فراخوانی می‌شود
  
  /// Callback when TokenProvider state changes
  void _onTokenProviderChanged() {
    // Propagate TokenProvider changes to AppProvider listeners
    notifyListeners();
  }
  
  /// بارگذاری وضعیت اپلیکیشن
  Future<void> _loadAppState() async {
    try {
      // Debug: Print all keys in SecureStorage
      final allKeys = await SecureStorage.instance.getAllKeys();
      print('🔍 AppProvider: All SecureStorage keys: $allKeys');
      
      // بارگذاری تنظیمات امنیتی
      final securitySettings = await SecureStorage.instance.getSecuritySettings();
      if (securitySettings != null) {
        _isBiometricEnabled = securitySettings['biometricEnabled'] ?? false;
        _autoLockTimeout = securitySettings['autoLockTimeout'] ?? 5;
      }
      
      // بارگذاری تنظیمات نوتیفیکیشن
      _deviceToken = await SecureStorage.instance.getDeviceToken();
      
      // بارگذاری تنظیمات زبان و ارز
      _currentLanguage = await SecureStorage.instance.getSecureData('current_language') ?? 'en';
      _currentCurrency = await SecureStorage.instance.getSecureData('current_currency') ?? 'USD';
      
      // بارگذاری کیف پول انتخاب شده
      _currentWalletName = await SecureStorage.instance.getSelectedWallet();
      print('🔍 AppProvider: Selected wallet name: $_currentWalletName');
      
      if (_currentWalletName != null) {
        _currentUserId = await SecureStorage.instance.getUserIdForWallet(_currentWalletName!);
        print('🔍 AppProvider: User ID for wallet $_currentWalletName: $_currentUserId');
      }
      
      // Alternative: Check selected user ID directly
      final selectedUserId = await SecureStorage.instance.getSelectedUserId();
      print('🔍 AppProvider: Selected user ID directly: $selectedUserId');
      
      // Alternative: Check SharedPreferences UserID (used by ApiService)
      final prefs = await SharedPreferences.getInstance();
      final sharedPrefsUserId = prefs.getString('UserID');
      print('🔍 AppProvider: SharedPreferences UserID: $sharedPrefsUserId');
      
      // If no user ID found, try to find from wallet list
      if (_currentUserId == null || _currentUserId!.isEmpty) {
        print('⚠️ AppProvider: No user ID found, checking wallet list...');
        final wallets = await SecureStorage.instance.getWalletsList();
        print('🔍 AppProvider: Available wallets: $wallets');
        
        if (wallets.isNotEmpty) {
          final firstWallet = wallets.first;
          _currentWalletName = firstWallet['walletName'];
          _currentUserId = firstWallet['userID'];
          print('🔧 AppProvider: Using first wallet: $_currentWalletName, userId: $_currentUserId');
          
          // Save as selected wallet
          if (_currentWalletName != null && _currentUserId != null) {
            await SecureStorage.instance.saveSelectedWallet(_currentWalletName!, _currentUserId!);
            print('💾 AppProvider: Saved $_currentWalletName as selected wallet');
          }
        }
      }
      
      print('✅ AppProvider: Final state - Wallet: $_currentWalletName, User ID: $_currentUserId');
      
    } catch (e) {
      print('❌ AppProvider: Error loading app state: $e');
    }
  }
  
  /// تنظیم LifecycleManager
  Future<void> _setupLifecycleManager() async {
    await LifecycleManager.instance.initialize(
      onLock: () {
        _isLocked = true;
        notifyListeners();
      },
      onUnlock: () {
        _isLocked = false;
        notifyListeners();
      },
      onBackground: () {
        // ذخیره وضعیت
        _saveAppState();
      },
      onForeground: () {
        // بررسی قفل خودکار
        _checkAutoLock();
      },
    );
  }
  
  /// بررسی مجوزها
  Future<void> _checkPermissions() async {
    try {
      final permissions = await PermissionManager.instance.checkAllPermissions();
      print('📱 Permissions status: $permissions');
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }
  
  /// بارگذاری کیف پول‌ها
  Future<void> _loadWallets() async {
    try {
      _wallets = await SecureStorage.instance.getWalletsList();
      notifyListeners();
    } catch (e) {
      print('Error loading wallets: $e');
    }
  }

  /// بارگذاری مجدد کیف پول‌ها (برای استفاده عمومی)
  Future<void> refreshWallets() async {
    await _loadWallets();
  }
  
  // ==================== WALLET MANAGEMENT ====================
  
  /// انتخاب کیف پول - مشابه Kotlin
  Future<void> selectWallet(String walletName) async {
    _currentWalletName = walletName;
    _currentUserId = await SecureStorage.instance.getUserIdForWallet(walletName);
    
    if (_currentUserId != null) {
      print('💰 AppProvider: Selecting wallet: $walletName with userId: $_currentUserId');
      
      await SecureStorage.instance.saveSelectedWallet(walletName, _currentUserId!);
      
      // ✅ Save activeTokens from current TokenProvider before switching
      if (_currentTokenProvider != null) {
        final activeTokens = _currentTokenProvider!.enabledTokens.map((t) => t.symbol ?? '').toList();
        final currentWalletName = _currentWalletName;
        final currentUserId = _currentUserId;
        
        if (currentWalletName != null && currentUserId != null) {
          // Save current wallet's active tokens
          await WalletStateManager.instance.saveActiveTokensForWallet(
            currentWalletName, 
            currentUserId, 
            activeTokens
          );
          
          // Save current wallet's balance cache
          final balanceCache = <String, double>{};
          for (final token in _currentTokenProvider!.enabledTokens) {
            if (token.amount > 0) {
              balanceCache[token.symbol ?? ''] = token.amount;
            }
          }
          if (balanceCache.isNotEmpty) {
            await WalletStateManager.instance.saveBalanceCacheForWallet(
              currentWalletName, 
              currentUserId, 
              balanceCache
            );
          }
          
          print('✅ AppProvider: Saved activeTokens and cache for previous wallet: $currentWalletName');
        }
        
        // Remove listener from previous TokenProvider
        _currentTokenProvider!.removeListener(_onTokenProviderChanged);
      }
      
      // Switch to the appropriate TokenProvider
      final tokenProvider = await _getOrCreateTokenProvider(_currentUserId!);
      
      // ✅ Load activeTokens for new wallet
      final completeWalletInfo = await WalletStateManager.instance.getCompleteWalletInfo(walletName, _currentUserId!);
      if (completeWalletInfo != null) {
        final activeTokens = completeWalletInfo['activeTokens'] as List<String>? ?? [];
        final balanceCache = completeWalletInfo['balanceCache'] as Map<String, double>? ?? {};
        
        print('💾 AppProvider: Loaded for wallet $walletName: ${activeTokens.length} activeTokens, ${balanceCache.length} cached balances');
        
        // Apply activeTokens to TokenProvider
        if (activeTokens.isNotEmpty) {
          await _applyActiveTokensToProvider(tokenProvider, activeTokens);
        }
        
        // Apply balance cache to TokenProvider
        if (balanceCache.isNotEmpty) {
          await _applyBalanceCacheToProvider(tokenProvider, balanceCache);
        }
      }
      
      // اطمینان از synchronization فوری برای کاربر جدید
      await tokenProvider.ensureTokensSynchronized();
      
      // Update BalanceManager with new wallet context
      try {
        if (BalanceManager.instance != null) {
          await BalanceManager.instance.setCurrentUserAndWallet(_currentUserId!, walletName);
          print('✅ AppProvider: Updated BalanceManager with new wallet context');
        }
      } catch (e) {
        print('❌ AppProvider: Error updating BalanceManager: $e');
      }
      
      // Update other providers that depend on wallet selection
      await _notifyWalletChange(walletName, _currentUserId!);
      
      print('✅ AppProvider: Wallet selected and TokenProvider synchronized with per-wallet data');
    }
    
    notifyListeners();
  }

  /// Apply activeTokens to TokenProvider
  Future<void> _applyActiveTokensToProvider(TokenProvider tokenProvider, List<String> activeTokens) async {
    try {
      // Enable tokens that should be active for this wallet
      for (final token in tokenProvider.currencies) {
        final shouldBeEnabled = activeTokens.contains(token.symbol);
        if (token.isEnabled != shouldBeEnabled) {
          await tokenProvider.toggleToken(token, shouldBeEnabled);
          print('🔄 AppProvider: Set token ${token.symbol} to $shouldBeEnabled for current wallet');
        }
      }
      
      print('✅ AppProvider: Applied ${activeTokens.length} activeTokens to TokenProvider');
    } catch (e) {
      print('❌ AppProvider: Error applying activeTokens: $e');
    }
  }

  /// Apply balance cache to TokenProvider
  Future<void> _applyBalanceCacheToProvider(TokenProvider tokenProvider, Map<String, double> balanceCache) async {
    try {
      // Update token balances from cache
      final updatedTokens = tokenProvider.enabledTokens.map((token) {
        final cachedBalance = balanceCache[token.symbol];
        if (cachedBalance != null && cachedBalance > 0) {
          return token.copyWith(amount: cachedBalance);
        }
        return token;
      }).toList();
      
      // Apply updated tokens to provider
      await tokenProvider.setActiveTokens(updatedTokens);
      
      print('✅ AppProvider: Applied balance cache with ${balanceCache.length} entries to TokenProvider');
    } catch (e) {
      print('❌ AppProvider: Error applying balance cache: $e');
    }
  }
  
  /// اطلاع‌رسانی تغییر کیف پول به سایر Provider ها
  Future<void> _notifyWalletChange(String walletName, String userId) async {
    // TokenProvider is now handled internally
    print('🔄 Notifying wallet change: $walletName -> $userId');
  }
  
  /// تنظیم کیف پول فعلی (alias برای selectWallet)
  Future<void> setCurrentWallet(String walletName) async {
    await selectWallet(walletName);
  }
  
  /// اضافه کردن کیف پول جدید
  Future<void> addWallet(String walletName, String userId) async {
    final newWallet = {
      'walletName': walletName,
      'userID': userId,
    };
    
    _wallets.add(newWallet);
    await SecureStorage.instance.saveWalletsList(_wallets);
    await SecureStorage.instance.saveUserId(walletName, userId);
    
    // Create TokenProvider for the new wallet (non-blocking)
    _getOrCreateTokenProvider(userId);
    
    notifyListeners();
    print('➕ Added wallet: $walletName');
  }
  
  /// حذف کیف پول
  Future<void> removeWallet(String walletName) async {
    // Get userId before removing the wallet
    final userId = await SecureStorage.instance.getUserIdForWallet(walletName);
    
    _wallets.removeWhere((wallet) => wallet['walletName'] == walletName);
    await SecureStorage.instance.saveWalletsList(_wallets);
    
    // Remove TokenProvider for this user
    if (userId != null) {
      final tokenProvider = _tokenProviders[userId];
      if (tokenProvider != null) {
        tokenProvider.removeListener(_onTokenProviderChanged);
        tokenProvider.dispose();
      }
      _tokenProviders.remove(userId);
      if (_currentUserId == userId) {
        _currentTokenProvider = null;
      }
    }
    
    if (_currentWalletName == walletName) {
      _currentWalletName = _wallets.isNotEmpty ? _wallets.first['walletName'] : null;
      _currentUserId = _currentWalletName != null 
          ? await SecureStorage.instance.getUserIdForWallet(_currentWalletName!)
          : null;
          
      // Initialize TokenProvider for new current wallet (non-blocking)
      if (_currentUserId != null) {
        _getOrCreateTokenProvider(_currentUserId!);
      }
    }
    
    notifyListeners();
    print('🗑️ Removed wallet: $walletName');
  }
  
  /// ذخیره Mnemonic
  Future<void> saveMnemonic(String walletName, String userId, String mnemonic) async {
    await SecureStorage.instance.saveMnemonic(walletName, userId, mnemonic);
    print('🔐 Saved mnemonic for wallet: $walletName');
  }
  
  /// خواندن Mnemonic
  Future<String?> getMnemonic(String walletName, String userId) async {
    return await SecureStorage.instance.getMnemonic(walletName, userId);
  }
  
  // ==================== SECURITY MANAGEMENT ====================
  
  /// تنظیم قفل خودکار
  Future<void> setAutoLockTimeout(int minutes) async {
    _autoLockTimeout = minutes;
    await LifecycleManager.instance.setAutoLockTimeout(minutes);
    
    final securitySettings = {
      'autoLockTimeout': minutes,
      'biometricEnabled': _isBiometricEnabled,
    };
    await SecureStorage.instance.saveSecuritySettings(securitySettings);
    
    notifyListeners();
    print('🔒 Auto-lock timeout set to ${minutes} minutes');
  }
  
  /// فعال/غیرفعال کردن بیومتریک
  Future<void> setBiometricEnabled(bool enabled) async {
    _isBiometricEnabled = enabled;
    
    final securitySettings = {
      'autoLockTimeout': _autoLockTimeout,
      'biometricEnabled': enabled,
    };
    await SecureStorage.instance.saveSecuritySettings(securitySettings);
    
    notifyListeners();
    print('🔐 Biometric ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// قفل کردن اپلیکیشن
  void lockApp() {
    LifecycleManager.instance.lockApp();
  }
  
  /// باز کردن قفل اپلیکیشن
  void unlockApp() {
    LifecycleManager.instance.unlockApp();
  }
  
  /// بررسی قفل خودکار
  Future<void> _checkAutoLock() async {
    if (await LifecycleManager.instance.shouldAutoLock()) {
      lockApp();
    }
  }
  
  // ==================== NETWORK MANAGEMENT ====================
  
  /// تنظیم وضعیت شبکه
  void setNetworkStatus(bool isOnline, String connectionType) {
    _isOnline = isOnline;
    _connectionType = connectionType;
    notifyListeners();
    
    print('🌐 Network status: ${isOnline ? 'Online' : 'Offline'} ($connectionType)');
  }
  
  // ==================== NOTIFICATION MANAGEMENT ====================
  
  /// تنظیم نوتیفیکیشن‌ها
  Future<void> setPushNotificationsEnabled(bool enabled) async {
    _pushNotificationsEnabled = enabled;
    await SecureStorage.instance.saveSecureData('push_notifications_enabled', enabled.toString());
    notifyListeners();
    
    print('🔔 Push notifications ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// تنظیم توکن دستگاه
  Future<void> setDeviceToken(String token) async {
    _deviceToken = token;
    await SecureStorage.instance.saveDeviceToken(token);
    notifyListeners();
    
    print('📱 Device token updated');
  }
  
  // ==================== SETTINGS MANAGEMENT ====================
  
  /// تنظیم زبان
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    await SecureStorage.instance.saveSecureData('current_language', language);
    notifyListeners();
    
    print('🌍 Language set to: $language');
  }
  
  /// تنظیم ارز
  Future<void> setCurrency(String currency) async {
    _currentCurrency = currency;
    await SecureStorage.instance.saveSecureData('current_currency', currency);
    notifyListeners();
    
    print('💰 Currency set to: $currency');
  }
  
  // ==================== UTILITY METHODS ====================
  
  /// ذخیره وضعیت اپلیکیشن
  Future<void> _saveAppState() async {
    try {
      await LifecycleManager.instance.saveLastBackgroundTime();
    } catch (e) {
      print('Error saving app state: $e');
    }
  }
  
  /// پاک کردن تمام داده‌ها
  Future<void> clearAllData() async {
    try {
      await SecureStorage.instance.clearAllSecureData();
      await LifecycleManager.instance.clearLifecycleData();
      
      _currentWalletName = null;
      _currentUserId = null;
      _wallets.clear();
      _isLocked = false;
      
      // Clear TokenProvider instances
      _tokenProviders.clear();
      _currentTokenProvider = null;
      
      notifyListeners();
      print('🗑️ All data cleared');
    } catch (e) {
      print('Error clearing data: $e');
    }
  }

  /// پاک کردن تمام داده‌ها و بازگشت به حالت اولیه
  Future<void> resetToFreshInstall() async {
    try {
      // Clear all secure storage
      await SecureStorage.instance.clearAllSecureData();
      
      // Clear lifecycle data
      await LifecycleManager.instance.clearLifecycleData();
      
      // Reset all state variables
      _currentWalletName = null;
      _currentUserId = null;
      _wallets.clear();
      _isLocked = false;
      _isBiometricEnabled = false;
      _autoLockTimeout = 5;
      _pushNotificationsEnabled = true;
      _deviceToken = null;
      _currentLanguage = 'en';
      _currentCurrency = 'USD';
      
      // Clear TokenProvider instances
      _tokenProviders.clear();
      _currentTokenProvider = null;
      
      notifyListeners();
      print('🔄 App reset to fresh install state');
    } catch (e) {
      print('Error resetting app: $e');
    }
  }
  
  /// دریافت اطلاعات دستگاه
  Future<Map<String, dynamic>> getDeviceInfo() async {
    return await PermissionManager.instance.getDeviceInfo();
  }
  
  /// بررسی پشتیبانی از بیومتریک
  Future<bool> isBiometricSupported() async {
    return await PermissionManager.instance.isBiometricSupported();
  }
  
  /// بررسی پشتیبانی از Face ID
  Future<bool> isFaceIdSupported() async {
    return await PermissionManager.instance.isFaceIdSupported();
  }
  
  @override
  void dispose() {
    LifecycleManager.instance.dispose();
    super.dispose();
  }
} 