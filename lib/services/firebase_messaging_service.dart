/// Stub Firebase Messaging Service for compatibility
/// This is a placeholder implementation that doesn't use Firebase
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance = FirebaseMessagingService._internal();
  
  factory FirebaseMessagingService() {
    return _instance;
  }
  
  FirebaseMessagingService._internal();
  
  static FirebaseMessagingService get instance => _instance;
  
  /// Initialize Firebase messaging (stub implementation)
  Future<void> initialize() async {
    try {
      print('📱 FirebaseMessagingService: Stub initialization (Firebase not available)');
      // This is a stub - no actual Firebase initialization
      print('✅ FirebaseMessagingService: Stub initialization completed');
    } catch (e) {
      print('❌ FirebaseMessagingService: Error in stub initialization: $e');
    }
  }
  
  /// Get FCM token (stub implementation)
  Future<String?> getToken() async {
    try {
      print('📱 FirebaseMessagingService: Getting FCM token (stub)');
      // Return null since Firebase is not available
      return null;
    } catch (e) {
      print('❌ FirebaseMessagingService: Error getting token: $e');
      return null;
    }
  }
  
  /// Handle background messages (stub implementation)
  void handleBackgroundMessage() {
    print('📱 FirebaseMessagingService: Background message handler (stub)');
    // Stub implementation - no actual Firebase handling
  }
}

/// Background message handler (stub function)
Future<void> firebaseMessagingBackgroundHandler(dynamic message) async {
  print('📱 Firebase background message handler (stub): $message');
  // Stub implementation - no actual Firebase handling
} 