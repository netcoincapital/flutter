import 'package:flutter/foundation.dart';
import '../services/web3_service.dart';
import '../services/dex_service.dart';

class Web3Provider extends ChangeNotifier {
  final Web3Service _web3Service = Web3Service.instance;
  final DexService _dexService = DexService.instance;
  
  bool _isConnected = false;
  String? _walletAddress;
  double _nativeBalance = 0.0;
  double _laxceBalance = 0.0;
  bool _isLoading = false;
  String? _error;
  
  // Getters
  bool get isConnected => _isConnected;
  String? get walletAddress => _walletAddress;
  double get nativeBalance => _nativeBalance;
  double get laxceBalance => _laxceBalance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  /// Initialize provider
  Future<void> initialize() async {
    try {
      _setLoading(true);
      
      // Check if wallet is already connected
      if (_web3Service.isWalletConnected) {
        _walletAddress = _web3Service.walletAddress;
        _isConnected = true;
        await _loadBalances();
      }
      
      _clearError();
    } catch (e) {
      _setError('Initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Create new wallet
  Future<Map<String, String>?> createWallet() async {
    try {
      _setLoading(true);
      _clearError();
      
      final walletInfo = await _web3Service.createWallet();
      _walletAddress = walletInfo['address'];
      _isConnected = true;
      
      await _loadBalances();
      
      return walletInfo;
    } catch (e) {
      _setError('Failed to create wallet: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }
  
  /// Import wallet from mnemonic
  Future<bool> importWallet(String mnemonic) async {
    try {
      _setLoading(true);
      _clearError();
      
      final address = await _web3Service.importWalletFromMnemonic(mnemonic);
      _walletAddress = address;
      _isConnected = true;
      
      await _loadBalances();
      
      return true;
    } catch (e) {
      _setError('Failed to import wallet: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  /// Disconnect wallet
  Future<void> disconnectWallet() async {
    try {
      await _web3Service.clearWallet();
      _walletAddress = null;
      _isConnected = false;
      _nativeBalance = 0.0;
      _laxceBalance = 0.0;
      _clearError();
      notifyListeners();
    } catch (e) {
      _setError('Failed to disconnect wallet: $e');
    }
  }
  
  /// Load balances
  Future<void> loadBalances() async {
    if (!_isConnected) return;
    
    try {
      _setLoading(true);
      await _loadBalances();
    } catch (e) {
      _setError('Failed to load balances: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Private method to load balances
  Future<void> _loadBalances() async {
    if (!_isConnected) return;
    
    try {
      // Load native balance (MATIC)
      _nativeBalance = await _web3Service.getNativeBalance();
      
      // Load LAXCE balance (if contract is deployed)
      try {
        _laxceBalance = await _dexService.getLaxceBalance();
      } catch (e) {
        print('⚠️ LAXCE balance loading failed (contract may not be deployed): $e');
        _laxceBalance = 0.0;
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ Error loading balances: $e');
      rethrow;
    }
  }
  
  /// Get fee discount for user
  Future<double> getFeeDiscount() async {
    if (!_isConnected) return 0.0;
    
    try {
      return await _dexService.getUserFeeDiscount();
    } catch (e) {
      print('⚠️ Fee discount loading failed: $e');
      return 0.0;
    }
  }
  
  /// Lock LAXCE tokens
  Future<bool> lockLaxceTokens({
    required double amount,
    required Duration duration,
    bool autoExtend = false,
  }) async {
    if (!_isConnected) {
      _setError('Wallet not connected');
      return false;
    }
    
    try {
      _setLoading(true);
      _clearError();
      
      final txHash = await _dexService.lockLaxceTokens(
        amount: amount,
        duration: duration,
        autoExtend: autoExtend,
      );
      
      print('✅ LAXCE tokens locked. Tx: $txHash');
      
      // Reload balances after locking
      await _loadBalances();
      
      return true;
    } catch (e) {
      _setError('Failed to lock tokens: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  /// Execute swap
  Future<String?> executeSwap({
    required String tokenIn,
    required String tokenOut,
    required double amountIn,
    required double amountOutMin,
    double slippageTolerance = 0.005,
  }) async {
    if (!_isConnected) {
      _setError('Wallet not connected');
      return null;
    }
    
    try {
      _setLoading(true);
      _clearError();
      
      final txHash = await _dexService.executeSwap(
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
        amountOutMin: amountOutMin,
        slippageTolerance: slippageTolerance,
      );
      
      print('✅ Swap executed. Tx: $txHash');
      
      // Reload balances after swap
      await _loadBalances();
      
      return txHash;
    } catch (e) {
      _setError('Swap failed: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }
  
  /// Get swap quote
  Future<SwapQuote?> getSwapQuote({
    required String tokenIn,
    required String tokenOut,
    required double amountIn,
  }) async {
    try {
      return await _dexService.getSwapQuote(
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        amountIn: amountIn,
      );
    } catch (e) {
      print('⚠️ Failed to get swap quote: $e');
      return null;
    }
  }
  
  /// Set contract addresses (for when contracts are deployed)
  void setContractAddresses({
    required String laxceToken,
    required String poolFactory,
    required String router,
    required String quoter,
  }) {
    _dexService.setContractAddresses(
      laxceToken: laxceToken,
      poolFactory: poolFactory,
      router: router,
      quoter: quoter,
    );
  }
  
  /// Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }
  
  void _clearError() {
    _error = null;
    notifyListeners();
  }
} 