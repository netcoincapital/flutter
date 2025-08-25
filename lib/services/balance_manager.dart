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
  
  // Thread safety
  final Map<String, Completer<void>> _refreshLocks = {};
  
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
    if (_currentUserId == userId && _currentWalletName == walletName) {
      return; // No change needed
    }
    
    print('🔄 BalanceManager: Setting current user: $userId, wallet: $walletName');
    
    // Save current user's state before switching
    if (_currentUserId != null && _currentWalletName != null) {
      await _persistUserBalances(_currentUserId!);
    }
    
    _currentUserId = userId;
    _currentWalletName = walletName;
    
    // Load balances for new user/wallet
    await _loadUserBalances(userId, walletName);
    
    // Force immediate refresh for new context
    await refreshBalancesForUser(userId, force: true);
    
    notifyListeners();
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
    return _userBalances[userId]?[symbol] ?? 0.0;
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
        
        // Update internal state
        _userBalances[userId] = newBalances;
        _lastBalanceUpdate[userId] = DateTime.now();
        
        // Persist immediately
        await _persistUserBalances(userId);
        
        print('✅ BalanceManager: Updated ${newBalances.length} balances for user $userId');
        
        // Notify listeners
        notifyListeners();
        
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
  
  /// اطلاعات debug
  void debugBalanceState() {
    print('=== BalanceManager Debug ===');
    print('Current User ID: $_currentUserId');
    print('Current Wallet: $_currentWalletName');
    print('Total Users: ${_userBalances.length}');
    
    for (final userId in _userBalances.keys) {
      final balances = _userBalances[userId] ?? {};
      final lastUpdate = _lastBalanceUpdate[userId];
      final activeTokens = _activeTokensPerUser[userId] ?? [];
      
      print('User $userId:');
      print('  Balances: ${balances.length}');
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
