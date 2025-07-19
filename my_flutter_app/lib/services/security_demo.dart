import 'package:flutter/material.dart';
import 'security_settings_manager.dart';

/// نمونه استفاده از SecuritySettingsManager
class SecurityDemo {
  static final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  /// نمایش چگونگی استفاده از تنظیمات امنیتی
  static Future<void> demonstrateSecuritySettings() async {
    print('🔒 Security Settings Demo');
    print('========================');

    // 1. تنظیم passcode
    print('\n1. Setting up passcode...');
    await _securityManager.setPasscodeEnabled(true);
    print('✅ Passcode enabled');

    // 2. تنظیم auto-lock
    print('\n2. Setting up auto-lock...');
    await _securityManager.setAutoLockDuration(AutoLockDuration.fiveMinutes);
    print('✅ Auto-lock set to 5 minutes');

    // 3. تنظیم lock method
    print('\n3. Setting up lock method...');
    final biometricAvailable = await _securityManager.isBiometricAvailable();
    if (biometricAvailable) {
      await _securityManager.setLockMethod(LockMethod.passcodeAndBiometric);
      print('✅ Lock method set to Passcode + Biometric');
    } else {
      await _securityManager.setLockMethod(LockMethod.passcodeOnly);
      print('✅ Lock method set to Passcode Only (biometric not available)');
    }

    // 4. نمایش خلاصه تنظیمات
    print('\n4. Security Settings Summary:');
    final summary = await _securityManager.getSecuritySettingsSummary();
    print('   Passcode Enabled: ${summary['passcodeEnabled']}');
    print('   Auto-lock: ${summary['autoLockDurationText']}');
    print('   Lock Method: ${summary['lockMethodText']}');
    print('   Biometric Available: ${summary['biometricAvailable']}');
    print('   Passcode Set: ${summary['passcodeSet']}');
  }

  /// نمایش چگونگی استفاده از lifecycle
  static Future<void> demonstrateLifecycleHandling() async {
    print('\n🔄 Lifecycle Demo');
    print('==================');

    // شبیه‌سازی رفتن به پس‌زمینه
    print('\n1. App goes to background...');
    await _securityManager.saveLastBackgroundTime();
    print('✅ Background time saved');

    // شبیه‌سازی بازگشت از پس‌زمینه
    print('\n2. App returns from background...');
    await Future.delayed(Duration(seconds: 2)); // شبیه‌سازی مدت زمان در پس‌زمینه
    
    final shouldShowPasscode = await _securityManager.shouldShowPasscodeAfterBackground();
    print('   Should show passcode: $shouldShowPasscode');

    if (shouldShowPasscode) {
      print('🔒 Passcode screen should be shown');
    } else {
      print('🔓 No passcode needed');
    }
  }

  /// نمایش چگونگی احراز هویت
  static Future<void> demonstrateAuthentication() async {
    print('\n🔐 Authentication Demo');
    print('=====================');

    // بررسی روش‌های احراز هویت موجود
    final canUseBiometric = await _securityManager.canUseBiometricInCurrentLockMethod();
    final canUsePasscode = await _securityManager.canUsePasscodeInCurrentLockMethod();
    
    print('   Can use biometric: $canUseBiometric');
    print('   Can use passcode: $canUsePasscode');

    // بررسی نیاز به passcode در startup
    final shouldShowOnStartup = await _securityManager.shouldShowPasscodeOnStartup();
    print('   Should show passcode on startup: $shouldShowOnStartup');

    // تست احراز هویت biometric (اگر موجود باشد)
    if (canUseBiometric) {
      print('\n   Testing biometric authentication...');
      final biometricResult = await _securityManager.authenticateWithBiometric();
      print('   Biometric auth result: $biometricResult');
    }
  }

  /// تست کامل سیستم
  static Future<void> runCompleteDemo() async {
    try {
      await demonstrateSecuritySettings();
      await demonstrateLifecycleHandling();
      await demonstrateAuthentication();
      
      print('\n✅ Security demo completed successfully!');
    } catch (e) {
      print('\n❌ Security demo failed: $e');
    }
  }
}

/// Widget مثال برای نمایش استفاده در UI
class SecurityDemoWidget extends StatefulWidget {
  @override
  _SecurityDemoWidgetState createState() => _SecurityDemoWidgetState();
}

class _SecurityDemoWidgetState extends State<SecurityDemoWidget> {
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  bool _isLoading = false;
  String _status = 'Ready';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Security Demo'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_status),
            SizedBox(height: 20),
            if (_isLoading) CircularProgressIndicator(),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _runDemo,
              child: Text('Run Security Demo'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _testBiometric,
              child: Text('Test Biometric'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _testAutoLock,
              child: Text('Test Auto-Lock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDemo() async {
    setState(() {
      _isLoading = true;
      _status = 'Running demo...';
    });

    try {
      await SecurityDemo.runCompleteDemo();
      setState(() {
        _status = 'Demo completed successfully!';
      });
    } catch (e) {
      setState(() {
        _status = 'Demo failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBiometric() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing biometric...';
    });

    try {
      final isAvailable = await _securityManager.isBiometricAvailable();
      if (isAvailable) {
        final result = await _securityManager.authenticateWithBiometric();
        setState(() {
          _status = 'Biometric test result: $result';
        });
      } else {
        setState(() {
          _status = 'Biometric not available';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Biometric test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testAutoLock() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing auto-lock...';
    });

    try {
      // تنظیم auto-lock روی immediate
      await _securityManager.setAutoLockDuration(AutoLockDuration.immediate);
      
      // شبیه‌سازی background
      await _securityManager.saveLastBackgroundTime();
      
      // بررسی نیاز به passcode
      final shouldShow = await _securityManager.shouldShowPasscodeAfterBackground();
      
      setState(() {
        _status = 'Auto-lock test: Should show passcode = $shouldShow';
      });
    } catch (e) {
      setState(() {
        _status = 'Auto-lock test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
} 