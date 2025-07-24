import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// Firebase Messaging Service for device registration and push notifications
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  
  factory FirebaseMessagingService() {
    return _instance;
  }
  
  FirebaseMessagingService._internal();
  
  static FirebaseMessagingService get instance => _instance;
  
  FirebaseMessaging? _messaging;
  bool _isInitialized = false;
  String? _cachedToken;
  
  /// Initialize Firebase and Firebase Messaging
  Future<void> initialize() async {
    try {
      print('📱 FirebaseMessagingService: Starting initialization...');
      
      // Check if Firebase is already initialized
      if (Firebase.apps.isEmpty) {
        print('🔥 Initializing Firebase...');
        await Firebase.initializeApp();
        print('✅ Firebase initialized successfully');
      } else {
        print('🔥 Firebase already initialized');
      }
      
      // Initialize Firebase Messaging
      _messaging = FirebaseMessaging.instance;
      
      // Request notification permissions
      await _requestPermissions();
      
      // Setup message handlers
      _setupMessageHandlers();
      
      _isInitialized = true;
      print('✅ FirebaseMessagingService: Initialization completed successfully');
      
    } catch (e) {
      print('❌ FirebaseMessagingService: Error during initialization: $e');
      _isInitialized = false;
      // Don't rethrow - allow app to continue without Firebase
    }
  }
  
  /// Request notification permissions
  Future<void> _requestPermissions() async {
    if (_messaging == null) return;
    
    try {
      final settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('📱 Notification permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permissions granted');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ Provisional notification permissions granted');
      } else {
        print('❌ Notification permissions denied');
      }
    } catch (e) {
      print('❌ Error requesting notification permissions: $e');
    }
  }
  
  /// Setup Firebase message handlers
  void _setupMessageHandlers() {
    if (_messaging == null) return;
    
    try {
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📱 Received foreground message: ${message.messageId}');
        _handleMessage(message);
      });
      
      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 Message clicked (background): ${message.messageId}');
        _handleMessage(message);
      });
      
      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      
      print('✅ Firebase message handlers setup completed');
    } catch (e) {
      print('❌ Error setting up message handlers: $e');
    }
  }
  
  /// Get FCM token for device registration
  Future<String?> getToken() async {
    try {
      if (!_isInitialized || _messaging == null) {
        print('⚠️ Firebase not initialized, attempting initialization...');
        await initialize();
        
        if (!_isInitialized || _messaging == null) {
          print('❌ Firebase initialization failed, cannot get token');
          return null;
        }
      }
      
      // Return cached token if available and recent
      if (_cachedToken != null) {
        print('📱 Returning cached FCM token');
        return _cachedToken;
      }
      
      print('📱 Getting FCM token...');
      final token = await _messaging!.getToken();
      
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        print('✅ FCM token retrieved successfully');
        print('🔑 Token length: ${token.length}');
        return token;
      } else {
        print('❌ Failed to get FCM token - token is null or empty');
        return null;
      }
      
    } catch (e) {
      print('❌ Error getting FCM token: $e');
      return null;
    }
  }
  
  /// Generate fallback device token if Firebase fails
  Future<String> generateFallbackToken() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String platform = 'unknown';
      
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }
      
      final fallbackToken = 'fallback_${platform}_$timestamp';
      print('⚠️ Generated fallback token: $fallbackToken');
      return fallbackToken;
    } catch (e) {
      print('❌ Error generating fallback token: $e');
      return 'fallback_unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  /// Get token with fallback
  Future<String> getTokenWithFallback() async {
    try {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }
      
      print('⚠️ FCM token not available, using fallback');
      return await generateFallbackToken();
    } catch (e) {
      print('❌ Error getting token with fallback: $e');
      return await generateFallbackToken();
    }
  }
  
  /// Handle incoming Firebase messages
  void _handleMessage(RemoteMessage message) {
    try {
      print('📱 Handling Firebase message:');
      print('   Message ID: ${message.messageId}');
      print('   Title: ${message.notification?.title}');
      print('   Body: ${message.notification?.body}');
      print('   Data: ${message.data}');
      
      // Handle different message types based on data
      final messageType = message.data['type'];
      switch (messageType) {
        case 'transaction':
          _handleTransactionMessage(message);
          break;
        case 'security':
          _handleSecurityMessage(message);
          break;
        case 'price_alert':
          _handlePriceAlertMessage(message);
          break;
        default:
          print('📱 Unknown message type: $messageType');
      }
    } catch (e) {
      print('❌ Error handling Firebase message: $e');
    }
  }
  
  /// Handle transaction-related messages
  void _handleTransactionMessage(RemoteMessage message) {
    print('💰 Transaction message received');
    // Implement transaction notification handling
  }
  
  /// Handle security-related messages
  void _handleSecurityMessage(RemoteMessage message) {
    print('🔒 Security message received');
    // Implement security notification handling
  }
  
  /// Handle price alert messages
  void _handlePriceAlertMessage(RemoteMessage message) {
    print('📈 Price alert message received');
    // Implement price alert notification handling
  }
  
  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    if (!_isInitialized || _messaging == null) {
      print('❌ Cannot subscribe to topic - Firebase not initialized');
      return;
    }
    
    try {
      await _messaging!.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Error subscribing to topic $topic: $e');
    }
  }
  
  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_isInitialized || _messaging == null) {
      print('❌ Cannot unsubscribe from topic - Firebase not initialized');
      return;
    }
    
    try {
      await _messaging!.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Error unsubscribing from topic $topic: $e');
    }
  }
  
  /// Clear cached token (force refresh on next call)
  void clearCachedToken() {
    _cachedToken = null;
    print('🔄 Cached FCM token cleared');
  }
  
  /// Check if Firebase is properly initialized
  bool get isInitialized => _isInitialized;
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Initialize Firebase if not already done
    await Firebase.initializeApp();
    
    print('📱 Background message received:');
    print('   Message ID: ${message.messageId}');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
    print('   Data: ${message.data}');
    
    // Handle background message processing here
    // Note: Don't call UI-related code from here
    
  } catch (e) {
    print('❌ Error in background message handler: $e');
  }
} 