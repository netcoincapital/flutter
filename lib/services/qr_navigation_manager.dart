import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QRNavigationManager {
  static const String _lastScanResultKey = 'last_scan_result';
  static const String _returnScreenKey = 'return_screen';
  
  /// Process QR scan result and determine navigation
  static Future<void> processQRScanResult(
    BuildContext context,
    String scanResult,
    String returnScreen,
  ) async {
    try {
      print('🔍 Processing QR scan result: $scanResult');
      print('📍 Return screen: $returnScreen');
      
      // Save scan result and return screen
      await _saveScanData(scanResult, returnScreen);
      
      // Process the scan result based on its content
      final navigationResult = await _processScanContent(context, scanResult, returnScreen);
      
      if (navigationResult != null) {
        // Navigate based on the result
        await _navigateToScreen(context, navigationResult);
      }
      
    } catch (e) {
      print('❌ Error processing QR scan result: $e');
      _showErrorSnackBar(context, 'Error processing QR code: $e');
    }
  }

  /// Process scan content and determine navigation
  static Future<NavigationResult?> _processScanContent(
    BuildContext context,
    String scanResult,
    String returnScreen,
  ) async {
    try {
      // Check if it's a wallet address (Ethereum-style)
      if (_isWalletAddress(scanResult)) {
        return NavigationResult(
          route: '/send',
          arguments: {'address': scanResult},
          message: 'Wallet address detected',
        );
      }
      
      // Check if it's a seed phrase
      if (_isSeedPhrase(scanResult)) {
        return NavigationResult(
          route: '/import-wallet',
          arguments: {'seedPhrase': scanResult},
          message: 'Seed phrase detected',
        );
      }
      
      // Check if it's a payment URL
      if (_isPaymentURL(scanResult)) {
        return NavigationResult(
          route: '/send',
          arguments: {'paymentUrl': scanResult},
          message: 'Payment URL detected',
        );
      }
      
      // Check if it's a token transfer
      if (_isTokenTransfer(scanResult)) {
        return NavigationResult(
          route: '/send',
          arguments: {'tokenTransfer': scanResult},
          message: 'Token transfer detected',
        );
      }
      
      // Default: treat as plain text
      return NavigationResult(
        route: '/send',
        arguments: {'text': scanResult},
        message: 'Text content detected',
      );
      
    } catch (e) {
      print('❌ Error processing scan content: $e');
      return null;
    }
  }

  /// Navigate to the appropriate screen
  static Future<void> _navigateToScreen(
    BuildContext context,
    NavigationResult result,
  ) async {
    try {
      // Clear saved scan data
      await _clearScanData();
      
      // Show success message
      _showSuccessSnackBar(context, result.message);
      
      // Navigate to the appropriate screen
      if (result.arguments != null) {
        Navigator.pushNamed(context, result.route, arguments: result.arguments);
      } else {
        Navigator.pushNamed(context, result.route);
      }
      
    } catch (e) {
      print('❌ Error navigating to screen: $e');
      _showErrorSnackBar(context, 'Navigation error: $e');
    }
  }

  /// Check if the scanned content is a wallet address
  static bool _isWalletAddress(String content) {
    // Ethereum address pattern (0x followed by 40 hex characters)
    final ethereumPattern = RegExp(r'^0x[a-fA-F0-9]{40}$');
    
    // Bitcoin address pattern (base58, starts with 1, 3, or bc1)
    final bitcoinPattern = RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$|^bc1[a-z0-9]{39,59}$');
    
    return ethereumPattern.hasMatch(content) || bitcoinPattern.hasMatch(content);
  }

  /// Check if the scanned content is a seed phrase
  static bool _isSeedPhrase(String content) {
    // Common seed phrase lengths: 12, 15, 18, 21, 24 words
    final words = content.trim().split(RegExp(r'\s+'));
    return words.length >= 12 && words.length <= 24 && words.length % 3 == 0;
  }

  /// Check if the scanned content is a payment URL
  static bool _isPaymentURL(String content) {
    // Check for common payment URL patterns
    final paymentPatterns = [
      RegExp(r'^bitcoin:', caseSensitive: false),
      RegExp(r'^ethereum:', caseSensitive: false),
      RegExp(r'^litecoin:', caseSensitive: false),
      RegExp(r'^ripple:', caseSensitive: false),
      RegExp(r'^pay:', caseSensitive: false),
    ];
    
    return paymentPatterns.any((pattern) => pattern.hasMatch(content));
  }

  /// Check if the scanned content is a token transfer
  static bool _isTokenTransfer(String content) {
    // Check for ERC-20 transfer patterns or other token transfer formats
    return content.contains('transfer') || 
           content.contains('token') || 
           content.contains('contract');
  }

  /// Save scan data to SharedPreferences
  static Future<void> _saveScanData(String scanResult, String returnScreen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastScanResultKey, scanResult);
      await prefs.setString(_returnScreenKey, returnScreen);
      print('✅ Scan data saved: $scanResult -> $returnScreen');
    } catch (e) {
      print('❌ Error saving scan data: $e');
    }
  }

  /// Clear saved scan data
  static Future<void> _clearScanData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastScanResultKey);
      await prefs.remove(_returnScreenKey);
      print('🗑️ Scan data cleared');
    } catch (e) {
      print('❌ Error clearing scan data: $e');
    }
  }

  /// Get saved scan data
  static Future<Map<String, String?>> getSavedScanData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scanResult = prefs.getString(_lastScanResultKey);
      final returnScreen = prefs.getString(_returnScreenKey);
      
      return {
        'scanResult': scanResult,
        'returnScreen': returnScreen,
      };
    } catch (e) {
      print('❌ Error getting saved scan data: $e');
      return {'scanResult': null, 'returnScreen': null};
    }
  }

  /// Show success snackbar
  static void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF16B369),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show error snackbar
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Handle QR scanner result
  static Future<void> handleQRScannerResult(
    BuildContext context,
    String scanResult,
    String returnScreen,
  ) async {
    if (scanResult.isNotEmpty) {
      await processQRScanResult(context, scanResult, returnScreen);
    } else {
      _showErrorSnackBar(context, 'No QR code content detected');
    }
  }
}

/// Navigation result class
class NavigationResult {
  final String route;
  final Map<String, dynamic>? arguments;
  final String message;

  NavigationResult({
    required this.route,
    this.arguments,
    required this.message,
  });
} 