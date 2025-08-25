import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'secure_storage.dart';
import 'passcode_manager.dart';

enum LockMethod {
  passcodeAndBiometric,
  passcodeOnly,
  biometricOnly,
}

enum AutoLockDuration {
  immediate,
  oneMinute,
  fiveMinutes,
  tenMinutes,
  fifteenMinutes,
}

class SecuritySettingsManager {
  static SecuritySettingsManager? _instance;
  static SecuritySettingsManager get instance => _instance ??= SecuritySettingsManager._();
  
  SecuritySettingsManager._();

  static const String _passcodeEnabledKey = 'passcode_enabled';
  static const String _autoLockDurationKey = 'auto_lock_duration';
  static const String _lockMethodKey = 'lock_method';
  static const String _lastBackgroundTimeKey = 'last_background_time';
  static const String _lastActivityTimeKey = 'last_activity_time';
  static const String _lastActivityElapsedKey = 'last_activity_elapsed';
  static const String _lastBootCountKey = 'last_boot_count';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _securityInitializedKey = 'security_initialized';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// TRUST WALLET STANDARD: Security-first initialization
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 🔒 TRUST WALLET STANDARD: Always default to TRUE (security first)
      // Only becomes false when user explicitly disables it
      if (!prefs.containsKey(_passcodeEnabledKey)) {
        await prefs.setBool(_passcodeEnabledKey, true);
        print('🔒 TRUST WALLET STANDARD: Set default passcode_enabled = TRUE (security first)');
      } else {
        // 🔧 TRUST WALLET FIX: If passcode exists but toggle is OFF, reset to ON
        final hasPasscode = await PasscodeManager.isPasscodeSet();
        final currentToggle = prefs.getBool(_passcodeEnabledKey) ?? true;
        
        if (hasPasscode && !currentToggle) {
          await prefs.setBool(_passcodeEnabledKey, true);
          print('🔧 TRUST WALLET FIX: Passcode exists but toggle was OFF - reset to ON');
        }
      }
      
      if (!prefs.containsKey(_autoLockDurationKey)) {
        await prefs.setInt(_autoLockDurationKey, AutoLockDuration.immediate.index);
        print('🔒 Set default auto_lock_duration: immediate');
      }
      
      if (!prefs.containsKey(_lockMethodKey)) {
        await prefs.setInt(_lockMethodKey, LockMethod.passcodeAndBiometric.index);
        print('🔒 Set default lock_method: passcodeAndBiometric');
      }
      
      print('✅ SecuritySettingsManager initialize completed - TRUST WALLET STANDARD');
    } catch (e) {
      print('❌ Error in SecuritySettingsManager.initialize: $e');
    }
  }

  /// 🔧 FORCE RE-INITIALIZATION (for debugging only)
  static void forceReinitialization() {
    print('🔧 FORCED re-initialization - this method is now simplified');
  }

  /// Reset security settings to default values
  Future<void> resetSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // حذف تمام کلیدهای امنیتی
      await prefs.remove(_passcodeEnabledKey);
      await prefs.remove(_autoLockDurationKey);
      await prefs.remove(_lockMethodKey);
      await prefs.remove(_lastBackgroundTimeKey);
      await prefs.remove(_biometricEnabledKey);
      await prefs.remove(_securityInitializedKey);
      
      print('🔒 Security settings reset to defaults');
      
      // مجدداً initialize کن
      await initialize();
    } catch (e) {
      print('❌ Error resetting security settings: $e');
    }
  }

  /// نمایش تنظیمات فعلی برای debugging
  Future<void> _debugCurrentSettings() async {
    try {
      final summary = await getSecuritySettingsSummary();
      print('🔒 Current Security Settings:');
      print('   Passcode Enabled: ${summary['passcodeEnabled']}');
      print('   Auto-lock: ${summary['autoLockDurationText']}');
      print('   Lock Method: ${summary['lockMethodText']}');
      print('   Biometric Available: ${summary['biometricAvailable']}');
      print('   Passcode Set: ${summary['passcodeSet']}');
    } catch (e) {
      print('❌ Error debugging settings: $e');
    }
  }

  /// Debug method to check current security settings state
  Future<void> debugSecurityState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      print('🔍 === SECURITY SETTINGS DEBUG ===');
      print('🔍 _passcodeEnabledKey exists: ${prefs.containsKey(_passcodeEnabledKey)}');
      print('🔍 _passcodeEnabledKey value: ${prefs.getBool(_passcodeEnabledKey)}');
      print('🔍 _securityInitializedKey: ${prefs.getBool(_securityInitializedKey)}');
      print('🔍 PasscodeManager.isPasscodeSet(): ${await PasscodeManager.isPasscodeSet()}');
      
      final isEnabled = await isPasscodeEnabled();
      print('🔍 Final isPasscodeEnabled(): $isEnabled');
      print('🔍 ================================');
    } catch (e) {
      print('❌ Error in debugSecurityState: $e');
    }
  }

  // ================ PASSCODE TOGGLE ================
  
  /// فعال/غیرفعال کردن passcode
  Future<bool> setPasscodeEnabled(bool enabled) async {
    try {
      print('🔒 Setting passcode enabled: $enabled');
      
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      
      // 🔍 DEBUG: Check before saving
      final oldValue = prefs.getBool(_passcodeEnabledKey);
      print('🔍 Old passcode enabled value: $oldValue');
      
      // 🔒 CRITICAL: Force immediate write to disk with retry mechanism
      try {
        await prefs.setBool(_passcodeEnabledKey, enabled).timeout(const Duration(seconds: 3));
        print('🔍 setBool completed - automatically persisted');
      } catch (e) {
        print('❌ First setBool attempt failed: $e - retrying...');
        await Future.delayed(const Duration(milliseconds: 100));
        await prefs.setBool(_passcodeEnabledKey, enabled).timeout(const Duration(seconds: 3));
        print('🔍 setBool retry successful');
      }
      
      // 🔍 DEBUG: Verify after saving
      final newValue = prefs.getBool(_passcodeEnabledKey);
      print('🔍 New passcode enabled value: $newValue (expected: $enabled)');
      
      // 🔍 DEBUG: Ensure it's actually written
      await prefs.reload();
      final reloadedValue = prefs.getBool(_passcodeEnabledKey);
      print('🔍 Reloaded passcode enabled value: $reloadedValue');
      
      // 🔍 EXTREME DEBUG: Check all keys
      final allKeys = prefs.getKeys();
      print('🔍 All SharedPreferences keys: $allKeys');
      print('🔍 Contains $_passcodeEnabledKey: ${allKeys.contains(_passcodeEnabledKey)}');
      
      // اگر passcode غیرفعال شد، lock method را مدیریت کن
      if (!enabled) {
        final lockMethod = await getLockMethod();
        final biometricAvailable = await isBiometricAvailable();
        
        if (lockMethod == LockMethod.passcodeOnly) {
          if (biometricAvailable) {
            // اگر biometric در دسترس است، به biometric only تغییر بده
            await setLockMethod(LockMethod.biometricOnly);
            print('🔒 Changed lock method to biometric only');
          } else {
            // اگر biometric در دسترس نیست، همچنان passcode را غیرفعال کن
            // در این حالت، اپلیکیشن بدون احراز هویت کار می‌کند
            print('🔓 Passcode disabled - app will work without authentication');
          }
        } else if (lockMethod == LockMethod.passcodeAndBiometric) {
          if (biometricAvailable) {
            // تغییر به biometric only
            await setLockMethod(LockMethod.biometricOnly);
            print('🔒 Changed lock method to biometric only');
          } else {
            // اگر biometric در دسترس نیست، همچنان passcode را غیرفعال کن
            print('🔓 Passcode disabled - app will work without authentication');
          }
        }
        // در هر حالت، passcode غیرفعال می‌ماند
      }
      
      print('✅ Passcode enabled setting saved: $enabled');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
      return true;
    } catch (e) {
      print('❌ Error setting passcode enabled: $e');
      return false;
    }
  }

  /// TRUST WALLET STANDARD: Check if passcode toggle is enabled
  Future<bool> isPasscodeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 🔒 TRUST WALLET STANDARD: Always show toggle state (default: TRUE)
      // The toggle controls whether passcode protection is active or not
      final enabled = prefs.getBool(_passcodeEnabledKey) ?? true;
      
      print('🔒 TRUST WALLET: Passcode toggle state: $enabled (default: true for security)');
      return enabled;
      
    } catch (e) {
      print('❌ Error checking passcode enabled: $e');
      return true; // TRUST WALLET STANDARD: Default to secure (true)
    }
  }

  // ================ AUTO-LOCK DURATION ================

  /// تنظیم مدت زمان auto-lock
  Future<void> setAutoLockDuration(AutoLockDuration duration) async {
    try {
      print('🔒 Setting auto-lock duration: ${getAutoLockDurationText(duration)}');
      
      final prefs = await SharedPreferences.getInstance();
      
      // 🔍 DEBUG: Check before saving
      final oldValue = prefs.getInt(_autoLockDurationKey);
      print('🔍 Old auto-lock value: $oldValue');
      
      // 🔒 CRITICAL: Force immediate write to disk
      await prefs.setInt(_autoLockDurationKey, duration.index);
      // Note: commit() is deprecated in newer Flutter versions - setInt already persists immediately
      print('🔍 setInt completed - automatically persisted');
      
      // 🔍 DEBUG: Verify after saving
      final newValue = prefs.getInt(_autoLockDurationKey);
      print('🔍 New auto-lock value: $newValue (expected: ${duration.index})');
      
      // 🔍 DEBUG: Ensure it's actually written
      await prefs.reload();
      final reloadedValue = prefs.getInt(_autoLockDurationKey);
      print('🔍 Reloaded auto-lock value: $reloadedValue');
      
      // 🔍 EXTREME DEBUG: Check all keys
      final allKeys = prefs.getKeys();
      print('🔍 All SharedPreferences keys: $allKeys');
      print('🔍 Contains $_autoLockDurationKey: ${allKeys.contains(_autoLockDurationKey)}');
      
      print('✅ Auto-lock duration saved: ${getAutoLockDurationText(duration)}');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
    } catch (e) {
      print('❌ Error setting auto-lock duration: $e');
    }
  }

  /// دریافت مدت زمان auto-lock
  Future<AutoLockDuration> getAutoLockDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_autoLockDurationKey) ?? AutoLockDuration.immediate.index;
      final duration = AutoLockDuration.values[index];
      print('🔒 Auto-lock duration check: ${getAutoLockDurationText(duration)}');
      return duration;
    } catch (e) {
      print('❌ Error getting auto-lock duration: $e');
      return AutoLockDuration.immediate;
    }
  }

  /// تبدیل AutoLockDuration به میلی‌ثانیه
  int getAutoLockDurationInMilliseconds(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 0;
      case AutoLockDuration.oneMinute:
        return 60 * 1000;
      case AutoLockDuration.fiveMinutes:
        return 5 * 60 * 1000;
      case AutoLockDuration.tenMinutes:
        return 10 * 60 * 1000;
      case AutoLockDuration.fifteenMinutes:
        return 15 * 60 * 1000;
    }
  }

  /// تبدیل AutoLockDuration به متن قابل نمایش
  String getAutoLockDurationText(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 'Immediate';
      case AutoLockDuration.oneMinute:
        return '1 Min';
      case AutoLockDuration.fiveMinutes:
        return '5 Min';
      case AutoLockDuration.tenMinutes:
        return '10 Min';
      case AutoLockDuration.fifteenMinutes:
        return '15 Min';
    }
  }

  // ================ LOCK METHOD ================

  /// تنظیم روش قفل
  Future<bool> setLockMethod(LockMethod method) async {
    try {
      print('🔒 Setting lock method: ${getLockMethodText(method)}');
      
      // بررسی در دسترس بودن biometric برای روش‌های مربوطه
      if (method == LockMethod.biometricOnly || method == LockMethod.passcodeAndBiometric) {
        final biometricAvailable = await isBiometricAvailable();
        if (!biometricAvailable) {
          print('❌ Biometric not available, cannot set lock method to: $method');
          return false;
        }
      }

      // بررسی وجود passcode برای روش‌های مربوطه
      if (method == LockMethod.passcodeOnly || method == LockMethod.passcodeAndBiometric) {
        final passcodeSet = await PasscodeManager.isPasscodeSet();
        if (!passcodeSet) {
          print('❌ Passcode not set, cannot set lock method to: $method');
          return false;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lockMethodKey, method.index);
      
      print('✅ Lock method saved: ${getLockMethodText(method)}');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
      return true;
    } catch (e) {
      print('❌ Error setting lock method: $e');
      return false;
    }
  }

  /// دریافت روش قفل
  Future<LockMethod> getLockMethod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_lockMethodKey) ?? LockMethod.passcodeAndBiometric.index;
      final method = LockMethod.values[index];
      print('🔒 Lock method check: ${getLockMethodText(method)}');
      return method;
    } catch (e) {
      print('❌ Error getting lock method: $e');
      return LockMethod.passcodeAndBiometric;
    }
  }

  /// تبدیل LockMethod به متن قابل نمایش
  String getLockMethodText(LockMethod method) {
    switch (method) {
      case LockMethod.passcodeAndBiometric:
        return 'Passcode / Biometric';
      case LockMethod.passcodeOnly:
        return 'Passcode Only';
      case LockMethod.biometricOnly:
        return 'Biometric Only';
    }
  }

  // ================ BIOMETRIC MANAGEMENT ================

  /// بررسی در دسترس بودن biometric
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      final available = canCheck && isDeviceSupported && availableBiometrics.isNotEmpty;
      print('🔒 Biometric availability check: $available');
      return available;
    } catch (e) {
      print('❌ Error checking biometric availability: $e');
      return false;
    }
  }

  /// دریافت نوع‌های biometric موجود
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('❌ Error getting available biometrics: $e');
      return [];
    }
  }

  /// احراز هویت biometric
  Future<bool> authenticateWithBiometric({String? reason}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        print('❌ Biometric authentication not available');
        return false;
      }

      print('🔒 Starting biometric authentication...');
      final result = await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to access your wallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      
      print('🔒 Biometric authentication result: $result');
      return result;
    } catch (e) {
      print('❌ Error authenticating with biometric: $e');
      return false;
    }
  }

  // ================ AUTO-LOCK LOGIC ================

  /// ذخیره زمان رفتن به پس‌زمینه
  Future<void> saveLastBackgroundTime() async {
    try {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastBackgroundTimeKey, currentTime);
      print('📱 Background time saved: ${DateTime.now()}');
    } catch (e) {
      print('❌ Error saving last background time: $e');
    }
  }

  /// بررسی نیاز به نمایش passcode بعد از بازگشت از پس‌زمینه
  Future<bool> shouldShowPasscodeAfterBackground() async {
    try {
      print('🔒 Checking if should show passcode after background...');
      
      // بررسی فعال بودن passcode
      final passcodeEnabled = await isPasscodeEnabled();
      if (!passcodeEnabled) {
        print('🔒 Passcode disabled, no need to show');
        return false;
      }

      // دریافت مدت زمان auto-lock
      final autoLockDuration = await getAutoLockDuration();
      final autoLockMs = getAutoLockDurationInMilliseconds(autoLockDuration);
      
      print('🔒 Auto-lock setting: ${getAutoLockDurationText(autoLockDuration)} ($autoLockMs ms)');
      
      // اگر immediate است، همیشه passcode را نمایش بده
      if (autoLockDuration == AutoLockDuration.immediate) {
        print('🔒 Immediate lock - should show passcode');
        return true;
      }

      // بررسی زمان آخرین رفتن به پس‌زمینه
      final prefs = await SharedPreferences.getInstance();
      final lastBackgroundTime = prefs.getInt(_lastBackgroundTimeKey);
      
      if (lastBackgroundTime == null) {
        print('🔒 No background time recorded, no need to show passcode');
        return false; // اگر زمان ذخیره نشده، passcode نمایش نده
      }

      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final timeDiff = currentTime - lastBackgroundTime;
      
      print('🔒 Time in background: ${timeDiff}ms, threshold: ${autoLockMs}ms');
      
      final shouldShow = timeDiff >= autoLockMs;
      print('🔒 Should show passcode: $shouldShow');
      
      return shouldShow;
    } catch (e) {
      print('❌ Error checking should show passcode: $e');
      return false;
    }
  }

  /// بررسی نیاز به نمایش passcode در startup
  Future<bool> shouldShowPasscodeOnStartup() async {
    try {
      final passcodeEnabled = await isPasscodeEnabled();
      print('🔒 Should show passcode on startup: $passcodeEnabled');
      
      if (!passcodeEnabled) {
        return false;
      }

      // اگر passcode فعال است، همیشه در startup نمایش بده
      return true;
    } catch (e) {
      print('❌ Error checking should show passcode on startup: $e');
      return true; // پیش‌فرض امن
    }
  }

  // ================ AUTHENTICATION LOGIC ================

  /// احراز هویت بر اساس lock method انتخاب شده
  Future<bool> authenticate({String? reason}) async {
    try {
      final lockMethod = await getLockMethod();
      final passcodeEnabled = await isPasscodeEnabled();

      print('🔒 Authentication requested - passcode enabled: $passcodeEnabled, method: ${getLockMethodText(lockMethod)}');

      // اگر passcode غیرفعال است، هیچ احراز هویتی نیاز نیست
      if (!passcodeEnabled) {
        print('🔒 Passcode disabled - authentication not required');
        return true;
      }

      switch (lockMethod) {
        case LockMethod.passcodeAndBiometric:
          // کاربر می‌تواند با هر دو روش احراز هویت کند
          // اینجا فقط true برمی‌گردانیم تا UI مناسب نمایش داده شود
          print('🔒 Passcode + Biometric method - UI should handle both');
          return true;
          
        case LockMethod.passcodeOnly:
          // فقط passcode screen نمایش داده می‌شود
          print('🔒 Passcode only method - UI should show passcode');
          return true;
          
        case LockMethod.biometricOnly:
          // فقط biometric احراز هویت
          print('🔒 Biometric only method - attempting biometric auth');
          return await authenticateWithBiometric(reason: reason);
      }
    } catch (e) {
      print('❌ Error in authenticate: $e');
      return false;
    }
  }

  /// بررسی امکان استفاده از biometric در lock method فعلی
  Future<bool> canUseBiometricInCurrentLockMethod() async {
    try {
      final lockMethod = await getLockMethod();
      final canUse = lockMethod == LockMethod.biometricOnly || 
             lockMethod == LockMethod.passcodeAndBiometric;
      print('🔒 Can use biometric in current method: $canUse');
      return canUse;
    } catch (e) {
      print('❌ Error checking can use biometric: $e');
      return false;
    }
  }

  /// بررسی امکان استفاده از passcode در lock method فعلی
  Future<bool> canUsePasscodeInCurrentLockMethod() async {
    try {
      final lockMethod = await getLockMethod();
      final canUse = lockMethod == LockMethod.passcodeOnly || 
             lockMethod == LockMethod.passcodeAndBiometric;
      print('🔒 Can use passcode in current method: $canUse');
      return canUse;
    } catch (e) {
      print('❌ Error checking can use passcode: $e');
      return false;
    }
  }

  // ================ ACTIVITY TIMER METHODS ================

  /// Reset activity timer - call this on real user interactions
  Future<void> resetActivityTimer() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      final now = DateTime.now();
      final nowMillis = now.millisecondsSinceEpoch;
      
      // Save both wall clock and elapsed time for robust tracking
      await prefs.setInt(_lastActivityTimeKey, nowMillis)
          .timeout(const Duration(seconds: 2));
      
      print('🔄 Activity timer reset at: $now');
      print('🔄 Timestamp saved: $nowMillis');
    } catch (e) {
      print('❌ Error resetting activity timer: $e');
      // Don't rethrow - let the app continue
    }
  }

  /// Get time since last activity in milliseconds
  Future<int> getTimeSinceLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActivityTime = prefs.getInt(_lastActivityTimeKey);
      
      if (lastActivityTime == null) {
        print('🔍 No last activity time found - treating as expired');
        return Duration.millisecondsPerDay; // Force timeout
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSince = now - lastActivityTime;
      
      print('🔍 Time since last activity: ${Duration(milliseconds: timeSince).inMinutes} minutes');
      return timeSince;
    } catch (e) {
      print('❌ Error getting time since last activity: $e');
      return Duration.millisecondsPerDay; // Safe fallback - force timeout
    }
  }

  /// Get time since last background in milliseconds
  Future<int> getTimeSinceLastBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackgroundTime = prefs.getInt(_lastBackgroundTimeKey);
      
      if (lastBackgroundTime == null) {
        print('🔍 No last background time found');
        return 0; // No background event recorded
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSince = now - lastBackgroundTime;
      
      print('🔍 Time since last background: ${Duration(milliseconds: timeSince).inMinutes} minutes');
      return timeSince;
    } catch (e) {
      print('❌ Error getting time since last background: $e');
      return 0;
    }
  }

  /// TRUST WALLET STANDARD: Check if passcode should be shown
  Future<bool> shouldShowPasscodeNow() async {
    try {
      final isPasscodeEnabled = await this.isPasscodeEnabled();
      final hasPasscode = await PasscodeManager.isPasscodeSet();
      
      print('🔍 TRUST WALLET: shouldShowPasscodeNow - enabled=$isPasscodeEnabled, hasPasscode=$hasPasscode');
      
      // TRUST WALLET LOGIC: Both conditions must be true
      if (!isPasscodeEnabled) {
        print('🔓 TRUST WALLET: Passcode disabled by user - skip protection');
        return false;
      }
      
      if (!hasPasscode) {
        print('⚠️ TRUST WALLET: No passcode set - cannot protect');
        return false;
      }
      
      // TRUST WALLET: Show passcode when both enabled and set
      print('🔒 TRUST WALLET: Show passcode protection');
      return true;
      
    } catch (e) {
      print('❌ Error in shouldShowPasscodeNow: $e');
      return false; // TRUST WALLET: Safe fallback (no protection)
    }
  }

  /// Convert AutoLockDuration to milliseconds
  int _getAutoLockTimeoutMs(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 0; // Immediate
      case AutoLockDuration.oneMinute:
        return 60 * 1000; // 1 minute
      case AutoLockDuration.fiveMinutes:
        return 5 * 60 * 1000; // 5 minutes
      case AutoLockDuration.tenMinutes:
        return 10 * 60 * 1000; // 10 minutes
      case AutoLockDuration.fifteenMinutes:
        return 15 * 60 * 1000; // 15 minutes
    }
  }

  // ================ UTILITY METHODS ================

  /// 🧪 COMPREHENSIVE PERSISTENCE TEST
  Future<void> comprehensivePersistenceTest() async {
    try {
      print('🧪 === COMPREHENSIVE PERSISTENCE TEST ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Step 1: Show current values
      print('🧪 STEP 1: Current values');
      print('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      print('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      print('  lock_method: ${prefs.getInt(_lockMethodKey)}');
      
      // Step 2: Modify values to test values
      print('🧪 STEP 2: Setting test values');
      await prefs.setBool(_passcodeEnabledKey, false);
      await prefs.setInt(_autoLockDurationKey, AutoLockDuration.fiveMinutes.index);
      await prefs.setInt(_lockMethodKey, LockMethod.biometricOnly.index);
      
      // Step 3: Verify immediate read
      print('🧪 STEP 3: Verify immediate read');
      print('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)} (expected: false)');
      print('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)} (expected: ${AutoLockDuration.fiveMinutes.index})');
      print('  lock_method: ${prefs.getInt(_lockMethodKey)} (expected: ${LockMethod.biometricOnly.index})');
      
      // Step 4: Force reload from disk
      print('🧪 STEP 4: Force reload from disk');
      await prefs.reload();
      print('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)} (after reload)');
      print('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)} (after reload)');
      print('  lock_method: ${prefs.getInt(_lockMethodKey)} (after reload)');
      
      // Step 5: Test multiple initialize() calls
      print('🧪 STEP 5: Test multiple initialize() calls');
      SecuritySettingsManager.forceReinitialization();
      await initialize();
      print('  First init done');
      await initialize();
      print('  Second init done (should be skipped)');
      await initialize();
      print('  Third init done (should be skipped)');
      
      // Step 6: Final values check
      print('🧪 STEP 6: Final values check');
      print('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      print('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      print('  lock_method: ${prefs.getInt(_lockMethodKey)}');
      
      print('🧪 === COMPREHENSIVE TEST COMPLETED ===');
      
    } catch (e) {
      print('❌ Error in comprehensive persistence test: $e');
    }
  }

  /// Advanced debugging for Android storage behavior
  Future<void> debugAndroidStorageBehavior() async {
    try {
      print('🤖 === ANDROID STORAGE DEBUG ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Create a persistent test value
      const testKey = 'android_persistence_test';
      final testValue = 'test_${DateTime.now().millisecondsSinceEpoch}';
      
      print('🤖 Setting test value: $testValue');
      await prefs.setString(testKey, testValue);
      // Note: commit() is deprecated - setString already persists
      
      // Verify immediate read
      final immediateRead = prefs.getString(testKey);
      print('🤖 Immediate read: $immediateRead');
      
      // Force reload from disk
      await prefs.reload();
      final reloadRead = prefs.getString(testKey);
      print('🤖 After reload: $reloadRead');
      
      // Check SharedPreferences file path (Android specific)
      print('🤖 NOTE: Kill app now and restart to test persistence!');
      print('🤖 Expected value after restart: $testValue');
      
      // Check all security values
      print('🤖 Current security values:');
      print('  - passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      print('  - auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      print('  - lock_method: ${prefs.getInt(_lockMethodKey)}');
      print('  - security_initialized: ${prefs.getBool(_securityInitializedKey)}');
      
      print('🤖 === END ANDROID DEBUG ===');
    } catch (e) {
      print('❌ Error in Android storage debug: $e');
    }
  }

  /// Test SharedPreferences persistence for debugging
  Future<void> testSharedPreferencesPersistence() async {
    try {
      print('🧪 === TESTING SHARED PREFERENCES PERSISTENCE ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Test writing and reading a test value
      const testKey = 'test_persistence_key';
      const testValue = 'test_persistence_value';
      
      print('🧪 Writing test value...');
      await prefs.setString(testKey, testValue);
      // Note: commit() is deprecated - setString already persists
      
      print('🧪 Reading test value...');
      final readValue = prefs.getString(testKey);
      print('🧪 Read value: $readValue (expected: $testValue)');
      
      // Test reload
      print('🧪 Testing reload...');
      await prefs.reload();
      final reloadedValue = prefs.getString(testKey);
      print('🧪 Reloaded value: $reloadedValue');
      
      // Show all security keys
      print('🧪 All security keys:');
      print('   $_passcodeEnabledKey: ${prefs.getBool(_passcodeEnabledKey)}');
      print('   $_autoLockDurationKey: ${prefs.getInt(_autoLockDurationKey)}');
      print('   $_lockMethodKey: ${prefs.getInt(_lockMethodKey)}');
      print('   $_securityInitializedKey: ${prefs.getBool(_securityInitializedKey)}');
      
      // Show ALL keys (to see if there's interference)
      final allKeys = prefs.getKeys();
      print('🧪 ALL SharedPreferences keys (${allKeys.length}): $allKeys');
      
      // Test immediate write stress test
      print('🧪 === STRESS TEST: Write multiple values ===');
      const stressTestKey = 'stress_test_';
      for (int i = 0; i < 5; i++) {
        final key = '$stressTestKey$i';
        final value = 'value_$i';
        await prefs.setString(key, value);
        // Note: commit() is deprecated - setString already persists
        final readBack = prefs.getString(key);
        print('🧪 Stress[$i]: wrote=$value, read=$readBack, match=${value == readBack}');
      }
      
      // Clean up
      for (int i = 0; i < 5; i++) {
        await prefs.remove('$stressTestKey$i');
      }
      await prefs.remove(testKey);
      // Note: commit() is deprecated - remove already persists
      
      print('🧪 === END SHARED PREFERENCES TEST ===');
      
    } catch (e) {
      print('❌ Error testing SharedPreferences persistence: $e');
    }
  }

  /// پاک کردن تمام تنظیمات امنیتی
  Future<void> clearSecuritySettings() async {
    try {
      print('🔒 Clearing all security settings...');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_passcodeEnabledKey);
      await prefs.remove(_autoLockDurationKey);
      await prefs.remove(_lockMethodKey);
      await prefs.remove(_lastBackgroundTimeKey);
      await prefs.remove(_biometricEnabledKey);
      await prefs.remove(_securityInitializedKey);
      
      // پاک کردن passcode
      await PasscodeManager.clearPasscode();
      
      print('✅ All security settings cleared');
    } catch (e) {
      print('❌ Error clearing security settings: $e');
    }
  }

  /// دریافت خلاصه تنظیمات امنیتی
  Future<Map<String, dynamic>> getSecuritySettingsSummary() async {
    try {
      final passcodeEnabled = await isPasscodeEnabled();
      final autoLockDuration = await getAutoLockDuration();
      final lockMethod = await getLockMethod();
      final biometricAvailable = await isBiometricAvailable();
      final passcodeSet = await PasscodeManager.isPasscodeSet();

      return {
        'passcodeEnabled': passcodeEnabled,
        'autoLockDuration': autoLockDuration,
        'autoLockDurationText': getAutoLockDurationText(autoLockDuration),
        'lockMethod': lockMethod,
        'lockMethodText': getLockMethodText(lockMethod),
        'biometricAvailable': biometricAvailable,
        'passcodeSet': passcodeSet,
      };
    } catch (e) {
      print('❌ Error getting security settings summary: $e');
      return {};
    }
  }
} 