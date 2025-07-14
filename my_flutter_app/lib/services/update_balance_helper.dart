import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Helper class for update-balance API calls (مطابق با Kotlin MainActivity.kt)
/// 
/// این کلاس دقیقاً مطابق با منطق Kotlin پیاده‌سازی شده:
/// - 3 بار تلاش مجدد در صورت شکست
/// - تأخیر 5 ثانیه قبل از ارسال
/// - timeout 10 ثانیه برای هر درخواست
/// - callback برای اطلاع از نتیجه
class UpdateBalanceHelper {
  static const int maxRetries = 3; // مطابق با Kotlin
  static const Duration initialDelay = Duration(seconds: 5); // مطابق با Kotlin
  static const Duration apiTimeout = Duration(seconds: 10); // مطابق با Kotlin

  /// به‌روزرسانی موجودی با چک و retry logic (مطابق با Kotlin updateBalanceWithCheck)
  /// 
  /// [userId]: شناسه کاربر
  /// [onResult]: callback برای دریافت نتیجه (true = موفق، false = ناموفق)
  static Future<void> updateBalanceWithCheck(
    String userId, 
    Function(bool success) onResult,
  ) async {
    const tag = 'UpdateBalance';
    
    if (kDebugMode) {
      print('$tag: 1. Starting balance update process for UserID: $userId');
    }

    int retryCount = 0;
    Exception? lastError;
    bool success = false;

    // تأخیر اولیه 5 ثانیه مطابق با Kotlin
    if (kDebugMode) {
      print('$tag: 3. Waiting ${initialDelay.inSeconds} seconds before sending update balance request');
    }
    await Future.delayed(initialDelay);
    if (kDebugMode) {
      print('$tag: 4. ${initialDelay.inSeconds}-second wait complete, proceeding with balance update');
    }

    while (retryCount < maxRetries && !success) {
      try {
        if (kDebugMode) {
          print('$tag: 5. Attempt ${retryCount + 1} of $maxRetries to update balance');
        }

        final apiService = ApiService();
        
        // فراخوانی API با timeout
        final response = await apiService.updateBalance(userId).timeout(
          apiTimeout,
          onTimeout: () {
            throw TimeoutException('API timeout after ${apiTimeout.inSeconds} seconds', apiTimeout);
          },
        );

        if (kDebugMode) {
          print('$tag: 8. Received balance update response');
          print('$tag: 9. Response success: ${response.success}');
        }

        if (response.success) {
          if (kDebugMode) {
            print('$tag: 10. ✅ Balance update successful');
          }
          success = true;
        } else {
          final msg = response.message ?? 'Unknown error';
          if (kDebugMode) {
            print('$tag: 11. ❌ Balance update failed: $msg');
          }
          lastError = Exception(msg);
        }
      } catch (e) {
        if (kDebugMode) {
          print('$tag: 14. Error updating balance: ${e.toString()}');
        }
        lastError = e is Exception ? e : Exception(e.toString());
      }

      if (success) {
        if (kDebugMode) {
          print('$tag: 17. Balance update succeeded, exiting retry loop');
        }
        break;
      }

      // در صورت شکست، تلاش مجدد
      retryCount++;
      if (retryCount < maxRetries && !success) {
        final delayTime = Duration(seconds: 2 * retryCount); // افزایش تأخیر در هر تلاش
        if (kDebugMode) {
          print('$tag: 19. Retrying update balance in ${delayTime.inSeconds}s... (Attempt ${retryCount + 1}/$maxRetries)');
        }
        await Future.delayed(delayTime);
      }
    }

    // فراخوانی callback با نتیجه نهایی
    onResult(success);

    if (!success && lastError != null) {
      if (kDebugMode) {
        print('$tag: All update balance attempts failed. Last error: ${lastError.toString()}');
      }
    }
  }

  /// تابع ساده برای به‌روزرسانی موجودی بدون callback (مطابق با Kotlin updateUserBalance)
  /// 
  /// [userId]: شناسه کاربر
  static Future<bool> updateUserBalance(String userId) async {
    const tag = 'UpdateBalance';
    
    if (kDebugMode) {
      print('$tag: Sending balance update request for UserID: $userId');
    }

    final completer = Completer<bool>();

    updateBalanceWithCheck(userId, (success) {
      completer.complete(success);
    });

    return completer.future;
  }
} 