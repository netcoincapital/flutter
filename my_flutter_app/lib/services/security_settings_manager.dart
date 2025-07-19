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
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _securityInitializedKey = 'security_initialized';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// مقداردهی اولیه تنظیمات امنیتی
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isInitialized = prefs.getBool(_securityInitializedKey) ?? false;
      
      if (!isInitialized) {
        print('🔒 Initializing security settings for first time...');
        
        // برای همه کاربران (جدید و موجود) پیش‌فرض غیرفعال است
        // کاربر می‌تواند در security screen فعال کند
        await prefs.setBool(_passcodeEnabledKey, false);
        print('🔒 Default passcode state set to disabled - user can enable in security screen');
        
        // سایر تنظیمات پیش‌فرض
        await prefs.setInt(_autoLockDurationKey, AutoLockDuration.immediate.index); // پیش‌فرض: فوری
        await prefs.setInt(_lockMethodKey, LockMethod.passcodeAndBiometric.index); // پیش‌فرض: هر دو
        await prefs.setBool(_securityInitializedKey, true);
        
        print('✅ Security settings initialized with consistent defaults');
      } else {
        print('🔒 Security settings already initialized');
        
        // اگر passcode_enabled key وجود نداشته باشد، پیش‌فرض false قرار بده
        if (!prefs.containsKey(_passcodeEnabledKey)) {
          await prefs.setBool(_passcodeEnabledKey, false);
          print('🔒 Missing passcode_enabled key - set to default false');
        }
      }
      
      // نمایش تنظیمات فعلی
      await _debugCurrentSettings();
    } catch (e) {
      print('❌ Error initializing security settings: $e');
    }
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
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_passcodeEnabledKey, enabled);
      
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

  /// بررسی فعال بودن passcode
  Future<bool> isPasscodeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      print('🔍 DEBUG: Checking passcode enabled state...');
      print('🔍 DEBUG: Key exists in prefs: ${prefs.containsKey(_passcodeEnabledKey)}');
      
      // بررسی اینکه آیا setting صریحاً تنظیم شده یا نه
      if (prefs.containsKey(_passcodeEnabledKey)) {
        // اگر کاربر صریحاً تنظیم کرده، از همان مقدار استفاده کن
        final enabled = prefs.getBool(_passcodeEnabledKey)!;
        print('🔒 Passcode enabled check (explicit from prefs): $enabled');
        return enabled;
      } else {
        // اگر تنظیم نشده، پیش‌فرض غیرفعال است
        // این به کاربر اختیار می‌دهد که خودش تصمیم بگیرد
        final defaultEnabled = false;
        
        print('🔒 Passcode enabled check (default for new setting): $defaultEnabled');
        
        // ذخیره کردن این مقدار پیش‌فرض برای استفاده‌های آینده
        await prefs.setBool(_passcodeEnabledKey, defaultEnabled);
        print('🔒 Saved default passcode enabled state: $defaultEnabled');
        
        return defaultEnabled;
      }
    } catch (e) {
      print('❌ Error checking passcode enabled: $e');
      return false; // پیش‌فرض امن تغییر یافت به false
    }
  }

  // ================ AUTO-LOCK DURATION ================

  /// تنظیم مدت زمان auto-lock
  Future<void> setAutoLockDuration(AutoLockDuration duration) async {
    try {
      print('🔒 Setting auto-lock duration: ${getAutoLockDurationText(duration)}');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_autoLockDurationKey, duration.index);
      
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

  // ================ UTILITY METHODS ================

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