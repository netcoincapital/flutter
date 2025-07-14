import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/secure_storage.dart';
import '../services/lifecycle_manager.dart';
import '../services/permission_manager.dart';
import '../models/crypto_token.dart';
import '../services/api_service.dart';
import 'token_provider.dart';

/// Provider اصلی اپلیکیشن
class AppProvider extends ChangeNotifier {
  // ==================== STATE VARIABLES ====================
  
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
    await _loadAppState();
    await _setupLifecycleManager();
    await _checkPermissions();
    await _loadWallets();
    
    // Initialize TokenProvider for current user
    await _initializeTokenProvider();
    
    print('🚀 AppProvider initialized');
  }
  
  /// مقداردهی اولیه TokenProvider
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
    
    print('🔄 Creating new TokenProvider for user: $userId');
    final tokenProvider = TokenProvider(
      userId: userId,
      apiService: _apiService,
      context: null, // We'll handle context differently
    );
    
    // Wait for TokenProvider to initialize
    await tokenProvider.initialize();
    
    // Listen to TokenProvider changes and propagate to AppProvider
    tokenProvider.addListener(_onTokenProviderChanged);
    
    _tokenProviders[userId] = tokenProvider;
    _currentTokenProvider = tokenProvider;
    
    return tokenProvider;
  }
  
  /// Callback when TokenProvider state changes
  void _onTokenProviderChanged() {
    // Propagate TokenProvider changes to AppProvider listeners
    notifyListeners();
  }
  
  /// بارگذاری وضعیت اپلیکیشن
  Future<void> _loadAppState() async {
    try {
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
      if (_currentWalletName != null) {
        _currentUserId = await SecureStorage.instance.getUserIdForWallet(_currentWalletName!);
      }
      
    } catch (e) {
      print('Error loading app state: $e');
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
  
  /// انتخاب کیف پول (مطابق با Kotlin)
  Future<void> selectWallet(String walletName) async {
    _currentWalletName = walletName;
    _currentUserId = await SecureStorage.instance.getUserIdForWallet(walletName);
    
    if (_currentUserId != null) {
      await SecureStorage.instance.saveSelectedWallet(walletName, _currentUserId!);
      
      // Remove listener from previous TokenProvider
      if (_currentTokenProvider != null) {
        _currentTokenProvider!.removeListener(_onTokenProviderChanged);
      }
      
      // Switch to the appropriate TokenProvider
      await _getOrCreateTokenProvider(_currentUserId!);
      
      // Update other providers that depend on wallet selection
      await _notifyWalletChange(walletName, _currentUserId!);
    }
    notifyListeners();
    
    print('💰 Selected wallet: $walletName with userId: $_currentUserId');
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
    
    // Create TokenProvider for the new wallet
    await _getOrCreateTokenProvider(userId);
    
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
          
      // Initialize TokenProvider for new current wallet
      if (_currentUserId != null) {
        await _getOrCreateTokenProvider(_currentUserId!);
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