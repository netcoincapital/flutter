import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/crypto_token.dart';
import '../services/secure_storage.dart';
import '../services/api_service.dart';

/// مدیریت پایدار موجودی‌ها با کشینگ و refresh خودکار
/// این کلاس اطمینان می‌دهد که موجودی‌ها همیشه به‌روز و قابل نمایش باشند
class BalanceManager extends ChangeNotifier {
  static BalanceManager? _instance;
  static BalanceManager get instance => _instance ??= BalanceManager._();
  
  BalanceManager._();
  
  // Core components
  late ApiService _apiService;
  
  // Balance state management
  final Map<String, Map<String, double>> _userBalances = {};
  final Map<String, DateTime> _lastBalanceUpdate = {};
  final Map<String, List<String>> _activeTokensPerUser = {};
  
  // Cache configuration
  static const Duration _balanceCacheValidity = Duration(minutes: 3);
  static const Duration _refreshInterval = Duration(seconds: 90);
  static const Duration _persistenceInterval = Duration(seconds: 30);
  
  // Timers and state
  Timer? _refreshTimer;
  Timer? _persistenceTimer;
  bool _isInitialized = false;
  String? _currentUserId;
  String? _currentWalletName;
  bool _isAppStartup = true; // Track if this is app startup
  
  // Thread safety
  final Map<String, Completer<void>> _refreshLocks = {};
  final Map<String, Completer<void>> _initializationLocks = {};
  
  /// مقداردهی اولیه
  Future<void> initialize(ApiService apiService) async {
    if (_isInitialized) return;
    
    _apiService = apiService;
    
    print('🔄 BalanceManager: Initializing...');
    
    try {
      // Load current wallet context
      await _loadCurrentWalletContext();
      
      // Restore cached balances for all users
      await _restoreAllUserBalances();
      
      // Start periodic operations
      _startPeriodicRefresh();
      _startPeriodicPersistence();
      
      _isInitialized = true;
      print('✅ BalanceManager: Initialized successfully');
      
    } catch (e) {
      print('❌ BalanceManager: Error during initialization: $e');
      rethrow;
    }
  }
  
  /// تنظیم کاربر و کیف پول فعلی
  Future<void> setCurrentUserAndWallet(String userId, String walletName) async {
    // Prevent concurrent initialization
    final lockKey = '${userId}_$walletName';
    if (_initializationLocks.containsKey(lockKey)) {
      print('⏳ BalanceManager: Already initializing for $userId/$walletName, waiting...');
      await _initializationLocks[lockKey]!.future;
      return;
    }
    
    if (_currentUserId == userId && _currentWalletName == walletName && !_isAppStartup) {
      return; // No change needed unless this is app startup
    }
    
    print('🔄 BalanceManager: Setting current user: $userId, wallet: $walletName (startup: $_isAppStartup)');
    
    final completer = Completer<void>();
    _initializationLocks[lockKey] = completer;
    
    try {
      // Save current user's state before switching (but not during app startup)
      if (_currentUserId != null && _currentWalletName != null && !_isAppStartup) {
        await _persistUserBalances(_currentUserId!);
      }
      
      _currentUserId = userId;
      _currentWalletName = walletName;
      
      // Load balances for new user/wallet
      await _loadUserBalances(userId, walletName);
      
      // During app startup, wait a bit for other systems to initialize
      if (_isAppStartup) {
        print('🔄 BalanceManager: App startup detected, waiting for stabilization...');
        await Future.delayed(const Duration(milliseconds: 500));
        _isAppStartup = false; // Mark startup complete
      }
      
      // Force immediate refresh only if we don't have recent cached data
      if (!areBalancesUpToDate(userId)) {
        print('🔄 BalanceManager: No recent balances, forcing refresh...');
        await refreshBalancesForUser(userId, force: true);
      } else {
        print('✅ BalanceManager: Using cached balances (still valid)');
      }
      
      notifyListeners();
      
    } finally {
      _initializationLocks.remove(lockKey);
      completer.complete();
    }
  }
  
  /// تنظیم توکن‌های فعال برای کاربر
  void setActiveTokensForUser(String userId, List<String> tokenSymbols) {
    final previousTokens = _activeTokensPerUser[userId] ?? [];
    _activeTokensPerUser[userId] = List.from(tokenSymbols);
    
    // اگر لیست توکن‌ها تغییر کرده، فوراً refresh کن
    if (!_listsEqual(previousTokens, tokenSymbols)) {
      print('🔄 BalanceManager: Active tokens changed for $userId, scheduling refresh');
      Timer(const Duration(milliseconds: 500), () {
        refreshBalancesForUser(userId, force: true);
      });
    }
  }
  
  /// دریافت موجودی توکن خاص
  double getTokenBalance(String userId, String symbol) {
    final balance = _userBalances[userId]?[symbol] ?? 0.0;
    
    // Debug logging for troubleshooting
    if (balance == 0.0) {
      print('🔍 BalanceManager: No balance found for $userId/$symbol');
      print('🔍 BalanceManager: Available balances for $userId: ${_userBalances[userId]?.keys.toList() ?? "none"}');
    }
    
    return balance;
  }
  
  /// دریافت تمام موجودی‌های کاربر
  Map<String, double> getUserBalances(String userId) {
    return Map.from(_userBalances[userId] ?? {});
  }
  
  /// بررسی اینکه آیا موجودی‌ها به‌روز هستند
  bool areBalancesUpToDate(String userId) {
    final lastUpdate = _lastBalanceUpdate[userId];
    if (lastUpdate == null) return false;
    
    final age = DateTime.now().difference(lastUpdate);
    return age < _balanceCacheValidity;
  }
  
  /// refresh موجودی‌ها برای کاربر خاص
  Future<void> refreshBalancesForUser(String userId, {bool force = false}) async {
    // Check if already refreshing
    if (_refreshLocks.containsKey(userId)) {
      print('⏳ BalanceManager: Already refreshing for user $userId, waiting...');
      await _refreshLocks[userId]!.future;
      return;
    }
    
    // During app startup, be more conservative about API calls
    if (_isAppStartup && !force) {
      print('ℹ️ BalanceManager: Skipping API refresh during app startup (use cached data)');
      return;
    }
    
    // Check if refresh is needed
    if (!force && areBalancesUpToDate(userId)) {
      print('ℹ️ BalanceManager: Balances are up to date for user $userId');
      return;
    }
    
    final completer = Completer<void>();
    _refreshLocks[userId] = completer;
    
    try {
      print('💰 BalanceManager: Refreshing balances for user: $userId (force: $force)');
      
      // Get active tokens for this user
      final activeTokens = _activeTokensPerUser[userId] ?? [];
      if (activeTokens.isEmpty) {
        print('⚠️ BalanceManager: No active tokens for user $userId, skipping refresh');
        return;
      }
      
      // Call API to get balances
      final response = await _apiService.getBalance(
        userId,
        currencyNames: [], // Empty to get all balances
        blockchain: {},
      );
      
      if (response.success && response.balances != null) {
        final newBalances = <String, double>{};
        
        // Process API response
        for (final balance in response.balances!) {
          final symbol = balance.symbol ?? '';
          final amount = double.tryParse(balance.balance ?? '0') ?? 0.0;
          
          if (symbol.isNotEmpty) {
            newBalances[symbol] = amount;
          }
        }
        
        // Update internal state with protection against empty responses
        if (newBalances.isNotEmpty && !_shouldPreventZeroBalances(userId, newBalances)) {
          // Backup current balances before updating
          final backup = _backupUserBalances(userId);
          
          _userBalances[userId] = newBalances;
          _lastBalanceUpdate[userId] = DateTime.now();
          
          // Persist immediately
          await _persistUserBalances(userId);
          
          print('✅ BalanceManager: Updated ${newBalances.length} balances for user $userId');
          
          // Notify listeners
          notifyListeners();
        } else {
          print('⚠️ BalanceManager: API returned empty/suspicious balances, keeping cached data');
          // Still update timestamp to avoid too frequent API calls
          _lastBalanceUpdate[userId] = DateTime.now();
        }
        
      } else {
        print('❌ BalanceManager: API failed to fetch balances for user $userId');
      }
      
    } catch (e) {
      print('❌ BalanceManager: Error refreshing balances for user $userId: $e');
    } finally {
      _refreshLocks.remove(userId);
      completer.complete();
    }
  }
  
  /// شروع periodic refresh
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    
    _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
      if (_currentUserId != null) {
        refreshBalancesForUser(_currentUserId!, force: false);
      }
    });
    
    print('🔄 BalanceManager: Started periodic refresh every ${_refreshInterval.inSeconds} seconds');
  }
  
  /// شروع periodic persistence
  void _startPeriodicPersistence() {
    _persistenceTimer?.cancel();
    
    _persistenceTimer = Timer.periodic(_persistenceInterval, (timer) {
      _persistAllUserBalances();
    });
    
    print('💾 BalanceManager: Started periodic persistence every ${_persistenceInterval.inSeconds} seconds');
  }
  
  /// بارگذاری context کیف پول فعلی
  Future<void> _loadCurrentWalletContext() async {
    try {
      final selectedWallet = await SecureStorage.instance.getSelectedWallet();
      final selectedUserId = await SecureStorage.instance.getSelectedUserId();
      
      if (selectedWallet != null && selectedUserId != null) {
        _currentWalletName = selectedWallet;
        _currentUserId = selectedUserId;
        print('✅ BalanceManager: Loaded current context - User: $selectedUserId, Wallet: $selectedWallet');
      }
    } catch (e) {
      print('❌ BalanceManager: Error loading wallet context: $e');
    }
  }
  
  /// بازیابی موجودی‌های cached برای همه کاربران
  Future<void> _restoreAllUserBalances() async {
    try {
      // Get all wallet users from secure storage
      final wallets = await SecureStorage.instance.getWalletsList();
      
      for (final wallet in wallets) {
        final userId = wallet['userID'];
        final walletName = wallet['walletName'];
        
        if (userId != null && walletName != null) {
          await _loadUserBalances(userId, walletName);
        }
      }
      
      print('✅ BalanceManager: Restored balances for ${_userBalances.length} users');
      
    } catch (e) {
      print('❌ BalanceManager: Error restoring user balances: $e');
    }
  }
  
  /// بارگذاری موجودی‌ها برای کاربر خاص
  Future<void> _loadUserBalances(String userId, String walletName) async {
    try {
      // Load from SecureStorage (per-wallet cache)
      final cachedBalances = await SecureStorage.instance.getWalletBalanceCache(walletName, userId);
      
      if (cachedBalances.isNotEmpty) {
        _userBalances[userId] = cachedBalances;
        print('✅ BalanceManager: Loaded ${cachedBalances.length} cached balances for user $userId');
      }
      
      // Load from SharedPreferences (fallback cache)
      final prefs = await SharedPreferences.getInstance();
      final balanceJson = prefs.getString('balance_manager_$userId');
      
      if (balanceJson != null) {
        final balanceData = json.decode(balanceJson) as Map<String, dynamic>;
        
        if (balanceData['balances'] != null) {
          final balances = Map<String, double>.from(
            (balanceData['balances'] as Map).map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            ),
          );
          
          // Use cached balances if they're more recent or if SecureStorage was empty
          if (_userBalances[userId]?.isEmpty ?? true) {
            _userBalances[userId] = balances;
          }
        }
        
        if (balanceData['lastUpdate'] != null) {
          _lastBalanceUpdate[userId] = DateTime.fromMillisecondsSinceEpoch(
            balanceData['lastUpdate'] as int,
          );
        }
      }
      
      // Load active tokens
      final activeTokens = await SecureStorage.instance.getActiveTokens(walletName, userId);
      if (activeTokens.isNotEmpty) {
        _activeTokensPerUser[userId] = activeTokens;
      }
      
    } catch (e) {
      print('❌ BalanceManager: Error loading balances for user $userId: $e');
    }
  }
  
  /// ذخیره موجودی‌ها برای کاربر خاص
  Future<void> _persistUserBalances(String userId) async {
    try {
      final balances = _userBalances[userId] ?? {};
      final lastUpdate = _lastBalanceUpdate[userId] ?? DateTime.now();
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final balanceData = {
        'balances': balances,
        'lastUpdate': lastUpdate.millisecondsSinceEpoch,
      };
      
      await prefs.setString('balance_manager_$userId', json.encode(balanceData));
      
      // Save to SecureStorage (per-wallet)
      if (_currentWalletName != null && userId == _currentUserId) {
        await SecureStorage.instance.saveWalletBalanceCache(
          _currentWalletName!,
          userId,
          balances,
        );
      }
      
      print('💾 BalanceManager: Persisted ${balances.length} balances for user $userId');
      
    } catch (e) {
      print('❌ BalanceManager: Error persisting balances for user $userId: $e');
    }
  }
  
  /// ذخیره موجودی‌های همه کاربران
  Future<void> _persistAllUserBalances() async {
    for (final userId in _userBalances.keys) {
      await _persistUserBalances(userId);
    }
  }
  
  /// متد کمکی برای مقایسه لیست‌ها
  bool _listsEqual<T>(List<T> list1, List<T> list2) {
    if (list1.length != list2.length) return false;
    return list1.every(list2.contains);
  }
  
  /// پاکسازی و تنظیم مجدد
  Future<void> clearAllBalances() async {
    _userBalances.clear();
    _lastBalanceUpdate.clear();
    _activeTokensPerUser.clear();
    
    // Clear from persistent storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys()
          .where((key) => key.startsWith('balance_manager_'))
          .toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      print('🗑️ BalanceManager: Cleared all balance data');
      
    } catch (e) {
      print('❌ BalanceManager: Error clearing balance data: $e');
    }
    
    notifyListeners();
  }
  
  /// backup موجودی‌ها قبل از تغییرات مهم
  Map<String, double> _backupUserBalances(String userId) {
    return Map.from(_userBalances[userId] ?? {});
  }
  
  /// restore موجودی‌ها در صورت مشکل
  void _restoreUserBalances(String userId, Map<String, double> backup) {
    if (backup.isNotEmpty) {
      _userBalances[userId] = backup;
      notifyListeners();
      print('🔄 BalanceManager: Restored ${backup.length} balances from backup for user $userId');
    }
  }
  
  /// بررسی و محافظت از صفر شدن موجودی‌ها
  bool _shouldPreventZeroBalances(String userId, Map<String, double> newBalances) {
    final currentBalances = _userBalances[userId] ?? {};
    
    // If current balances exist and new balances are empty, prevent the update
    if (currentBalances.isNotEmpty && newBalances.isEmpty) {
      print('⚠️ BalanceManager: Preventing zero balance update (current: ${currentBalances.length}, new: 0)');
      return true;
    }
    
    // If we have significant balances and new response has all zeros, be cautious
    final currentNonZero = currentBalances.values.where((v) => v > 0).length;
    final newNonZero = newBalances.values.where((v) => v > 0).length;
    
    if (currentNonZero >= 2 && newNonZero == 0) {
      print('⚠️ BalanceManager: Preventing suspicious zero balance update (current non-zero: $currentNonZero, new non-zero: 0)');
      return true;
    }
    
    return false;
  }
  
  /// اطلاعات debug
  void debugBalanceState() {
    print('=== BalanceManager Debug ===');
    print('Current User ID: $_currentUserId');
    print('Current Wallet: $_currentWalletName');
    print('Is App Startup: $_isAppStartup');
    print('Total Users: ${_userBalances.length}');
    
    for (final userId in _userBalances.keys) {
      final balances = _userBalances[userId] ?? {};
      final lastUpdate = _lastBalanceUpdate[userId];
      final activeTokens = _activeTokensPerUser[userId] ?? [];
      
      print('User $userId:');
      print('  Balances: ${balances.length}');
      print('  Non-zero balances: ${balances.values.where((v) => v > 0).length}');
      print('  Active Tokens: ${activeTokens.length}');
      print('  Last Update: $lastUpdate');
      print('  Up to Date: ${areBalancesUpToDate(userId)}');
    }
    print('==========================');
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _persistenceTimer?.cancel();
    
    // Final persistence
    _persistAllUserBalances();
    
    super.dispose();
  }
}
