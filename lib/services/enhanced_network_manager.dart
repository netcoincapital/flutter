import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Enhanced Network Manager with intelligent handling for weak internet and VPN scenarios
class EnhancedNetworkManager {
  static final EnhancedNetworkManager _instance = EnhancedNetworkManager._internal();
  factory EnhancedNetworkManager() => _instance;
  static EnhancedNetworkManager get instance => _instance;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;
  
  // Connection quality metrics
  ConnectionQuality _currentQuality = ConnectionQuality.unknown;
  bool _isVpnActive = false;
  Duration _lastResponseTime = Duration.zero;
  double _successRate = 1.0;
  
  // Adaptive timeouts based on connection quality
  final Map<ConnectionQuality, NetworkTimeouts> _timeoutConfigs = {
    ConnectionQuality.excellent: NetworkTimeouts(
      connect: Duration(seconds: 10),
      receive: Duration(seconds: 15),
      send: Duration(seconds: 10),
    ),
    ConnectionQuality.good: NetworkTimeouts(
      connect: Duration(seconds: 15),
      receive: Duration(seconds: 25),
      send: Duration(seconds: 15),
    ),
    ConnectionQuality.fair: NetworkTimeouts(
      connect: Duration(seconds: 25),
      receive: Duration(seconds: 40),
      send: Duration(seconds: 25),
    ),
    ConnectionQuality.poor: NetworkTimeouts(
      connect: Duration(seconds: 45),
      receive: Duration(seconds: 60),
      send: Duration(seconds: 45),
    ),
    ConnectionQuality.vpn: NetworkTimeouts(
      connect: Duration(seconds: 30),
      receive: Duration(seconds: 50),
      send: Duration(seconds: 30),
    ),
    ConnectionQuality.unknown: NetworkTimeouts(
      connect: Duration(seconds: 30),
      receive: Duration(seconds: 30),
      send: Duration(seconds: 30),
    ),
  };

  EnhancedNetworkManager._internal() {
    _startNetworkMonitoring();
  }

  /// Start monitoring network changes and quality
  void _startNetworkMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final result = _extractConnectivityResult(results);
      _updateConnectionInfo(result);
    });
    
    // Initial connection check
    _checkInitialConnection();
    
    // Start periodic quality assessment
    _startQualityMonitoring();
  }

  ConnectivityResult _extractConnectivityResult(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.isNotEmpty ? result.first : ConnectivityResult.none;
    } else if (result is ConnectivityResult) {
      return result;
    } else {
      return ConnectivityResult.none;
    }
  }

  Future<void> _checkInitialConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final connectivityResult = _extractConnectivityResult(result);
      _updateConnectionInfo(connectivityResult);
    } catch (e) {
      print('❌ Error checking initial connectivity: $e');
    }
  }

  void _updateConnectionInfo(ConnectivityResult result) {
    _isVpnActive = result == ConnectivityResult.vpn;
    
    if (kDebugMode) {
      print('🌐 Network connection changed: $result');
      print('🔒 VPN Active: $_isVpnActive');
    }
    
    // Trigger immediate quality assessment
    _assessNetworkQuality();
  }

  /// Start periodic network quality monitoring
  void _startQualityMonitoring() {
    Timer.periodic(Duration(minutes: 2), (timer) {
      _assessNetworkQuality();
    });
  }

  /// Assess current network quality through speed test
  Future<void> _assessNetworkQuality() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Perform a lightweight speed test to a reliable endpoint
      final dio = Dio();
      dio.options.connectTimeout = Duration(seconds: 10);
      dio.options.receiveTimeout = Duration(seconds: 10);
      
      await dio.get('https://coinceeper.com/api/ping',
          options: Options(headers: {'Cache-Control': 'no-cache'}));
      
      stopwatch.stop();
      _lastResponseTime = stopwatch.elapsed;
      
      // Update success rate (simplified)
      _successRate = 1.0;
      
      // Determine quality based on response time and VPN status
      _currentQuality = _calculateConnectionQuality(_lastResponseTime, _isVpnActive);
      
      if (kDebugMode) {
        print('📊 Network Quality Assessment:');
        print('   Response Time: ${_lastResponseTime.inMilliseconds}ms');
        print('   Quality: $_currentQuality');
        print('   VPN Active: $_isVpnActive');
        print('   Success Rate: ${(_successRate * 100).toStringAsFixed(1)}%');
      }
      
    } catch (e) {
      // Network test failed - assume poor quality
      _currentQuality = ConnectionQuality.poor;
      _successRate = 0.5;
      
      if (kDebugMode) {
        print('⚠️ Network quality test failed: $e');
        print('📉 Assuming poor connection quality');
      }
    }
  }

  ConnectionQuality _calculateConnectionQuality(Duration responseTime, bool isVpn) {
    if (isVpn) {
      return ConnectionQuality.vpn;
    }
    
    final ms = responseTime.inMilliseconds;
    
    if (ms < 200) return ConnectionQuality.excellent;
    if (ms < 500) return ConnectionQuality.good;
    if (ms < 1500) return ConnectionQuality.fair;
    return ConnectionQuality.poor;
  }

  /// Get adaptive timeouts based on current connection quality
  NetworkTimeouts getCurrentTimeouts() {
    return _timeoutConfigs[_currentQuality] ?? _timeoutConfigs[ConnectionQuality.unknown]!;
  }

  /// Get retry configuration based on connection quality
  RetryConfig getRetryConfig() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
      case ConnectionQuality.good:
        return RetryConfig(maxRetries: 3, baseDelay: Duration(seconds: 1));
        
      case ConnectionQuality.fair:
        return RetryConfig(maxRetries: 4, baseDelay: Duration(seconds: 2));
        
      case ConnectionQuality.poor:
      case ConnectionQuality.vpn:
        return RetryConfig(maxRetries: 5, baseDelay: Duration(seconds: 3));
        
      case ConnectionQuality.unknown:
      default:
        return RetryConfig(maxRetries: 3, baseDelay: Duration(seconds: 2));
    }
  }

  /// Enhanced request method with intelligent retry and timeout handling
  Future<T> executeRequest<T>(
    Future<T> Function() request, {
    String? operationName,
    bool enableRetry = true,
  }) async {
    final timeouts = getCurrentTimeouts();
    final retryConfig = getRetryConfig();
    
    if (kDebugMode && operationName != null) {
      print('🚀 Executing $operationName with quality: $_currentQuality');
      print('⏱️ Timeouts: ${timeouts.connect.inSeconds}s/${timeouts.receive.inSeconds}s/${timeouts.send.inSeconds}s');
      print('🔄 Retry config: ${retryConfig.maxRetries} attempts with ${retryConfig.baseDelay.inSeconds}s base delay');
    }

    Exception? lastException;
    
    for (int attempt = 1; attempt <= retryConfig.maxRetries; attempt++) {
      try {
        if (kDebugMode && operationName != null && attempt > 1) {
          print('🔄 Retry attempt $attempt/${retryConfig.maxRetries} for $operationName');
        }
        
        final result = await request();
        
        // Success - update success rate
        _updateSuccessRate(true);
        
        if (kDebugMode && operationName != null) {
          print('✅ $operationName completed successfully on attempt $attempt');
        }
        
        return result;
        
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
        // Update success rate
        _updateSuccessRate(false);
        
        if (kDebugMode && operationName != null) {
          print('❌ $operationName failed on attempt $attempt: $e');
        }
        
        // Don't retry on final attempt
        if (attempt >= retryConfig.maxRetries || !enableRetry) {
          break;
        }
        
        // Calculate delay with exponential backoff for poor connections
        final delay = _calculateRetryDelay(attempt, retryConfig.baseDelay);
        
        if (kDebugMode && operationName != null) {
          print('⏳ Waiting ${delay.inSeconds}s before retry...');
        }
        
        await Future.delayed(delay);
        
        // Re-assess network quality after failures
        if (attempt >= 2) {
          await _assessNetworkQuality();
        }
      }
    }
    
    // All retries failed
    if (kDebugMode && operationName != null) {
      print('💥 $operationName failed after all ${retryConfig.maxRetries} attempts');
    }
    
    throw lastException ?? Exception('Request failed after ${retryConfig.maxRetries} attempts');
  }

  Duration _calculateRetryDelay(int attempt, Duration baseDelay) {
    // For poor/VPN connections, use exponential backoff
    if (_currentQuality == ConnectionQuality.poor || _currentQuality == ConnectionQuality.vpn) {
      return Duration(seconds: baseDelay.inSeconds * (attempt * attempt));
    }
    
    // For better connections, use linear backoff
    return Duration(seconds: baseDelay.inSeconds * attempt);
  }

  void _updateSuccessRate(bool success) {
    // Simple moving average for success rate
    const alpha = 0.1; // Smoothing factor
    _successRate = alpha * (success ? 1.0 : 0.0) + (1 - alpha) * _successRate;
  }

  /// Create Dio instance with adaptive configuration
  Dio createAdaptiveDio({String? baseUrl}) {
    final timeouts = getCurrentTimeouts();
    
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? 'https://coinceeper.com/api/',
      connectTimeout: timeouts.connect,
      receiveTimeout: timeouts.receive,
      sendTimeout: timeouts.send,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Flutter-App/1.0',
      },
    ));

    // Add logging interceptor
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => print('🌐 $obj'),
      ));
    }

    return dio;
  }

  /// Get current connection status summary
  Map<String, dynamic> getConnectionStatus() {
    return {
      'quality': _currentQuality.toString().split('.').last,
      'isVpnActive': _isVpnActive,
      'lastResponseTime': _lastResponseTime.inMilliseconds,
      'successRate': (_successRate * 100).toStringAsFixed(1),
      'timeouts': {
        'connect': getCurrentTimeouts().connect.inSeconds,
        'receive': getCurrentTimeouts().receive.inSeconds,
        'send': getCurrentTimeouts().send.inSeconds,
      },
      'retryConfig': {
        'maxRetries': getRetryConfig().maxRetries,
        'baseDelay': getRetryConfig().baseDelay.inSeconds,
      },
    };
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}

/// Connection quality levels
enum ConnectionQuality {
  excellent,  // < 200ms response
  good,       // 200-500ms response  
  fair,       // 500-1500ms response
  poor,       // > 1500ms response
  vpn,        // VPN detected
  unknown,    // Unable to determine
}

/// Network timeout configuration
class NetworkTimeouts {
  final Duration connect;
  final Duration receive;
  final Duration send;

  NetworkTimeouts({
    required this.connect,
    required this.receive,
    required this.send,
  });
}

/// Retry configuration
class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;

  RetryConfig({
    required this.maxRetries,
    required this.baseDelay,
  });
}
