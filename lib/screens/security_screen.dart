import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/security_settings_manager.dart';
import '../services/passcode_manager.dart';
import 'passcode_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({Key? key}) : super(key: key);

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  bool _isLoading = true;
  bool _passcodeEnabled = true;
  AutoLockDuration _autoLockDuration = AutoLockDuration.immediate;
  LockMethod _lockMethod = LockMethod.passcodeAndBiometric;
  bool _biometricAvailable = false;
  bool _passcodeSet = false;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeAndLoadSettings();
  }

  /// مقداردهی و بارگذاری تنظیمات
  Future<void> _initializeAndLoadSettings() async {
    try {
      // مقداردهی SecuritySettingsManager
      await _securityManager.initialize();
      
      // بارگذاری تنظیمات
      await _loadSecuritySettings();
    } catch (e) {
      print('❌ Error initializing security screen: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// بارگذاری تنظیمات امنیتی
  Future<void> _loadSecuritySettings() async {
    try {
      final settings = await _securityManager.getSecuritySettingsSummary();
      
      setState(() {
        _passcodeEnabled = settings['passcodeEnabled'] ?? true;
        _autoLockDuration = settings['autoLockDuration'] ?? AutoLockDuration.immediate;
        _lockMethod = settings['lockMethod'] ?? LockMethod.passcodeAndBiometric;
        _biometricAvailable = settings['biometricAvailable'] ?? false;
        _passcodeSet = settings['passcodeSet'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading security settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// تغییر وضعیت passcode
  Future<void> _togglePasscode(bool enabled) async {
    try {
      if (enabled && !_passcodeSet) {
        // اگر passcode تنظیم نشده، به صفحه تنظیم passcode هدایت کن
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PasscodeScreen(
              title: _safeTranslate('choose_passcode', 'Choose Passcode'),
              onSuccess: () async {
                await _securityManager.setPasscodeEnabled(true);
                await _loadSecuritySettings();
                Navigator.pop(context);
              },
            ),
          ),
        );
        return;
      }

      final success = await _securityManager.setPasscodeEnabled(enabled);
      if (success) {
        await _loadSecuritySettings();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                ? _safeTranslate('passcode_enabled', 'Passcode enabled successfully')
                : _safeTranslate('passcode_disabled', 'Passcode disabled successfully')
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled 
                ? _safeTranslate('passcode_enable_failed', 'Failed to enable passcode')
                : _safeTranslate('passcode_disable_failed', 'Failed to disable passcode. Biometric authentication not available.')
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error toggling passcode: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_safeTranslate('error_occurred', 'An error occurred: {error}').replaceAll('{error}', e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// نمایش dialog انتخاب auto-lock duration
  Future<void> _showAutoLockDialog() async {
    final autoLockOptions = [
      AutoLockDuration.immediate,
      AutoLockDuration.oneMinute,
      AutoLockDuration.fiveMinutes,
      AutoLockDuration.tenMinutes,
      AutoLockDuration.fifteenMinutes,
    ];

    final result = await showModalBottomSheet<AutoLockDuration>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6F3),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _safeTranslate('select_auto_lock_time', 'Select Auto-lock Time'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...autoLockOptions.map((duration) => InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, duration),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
                  child: Row(
                    children: [
                      Radio<AutoLockDuration>(
                        value: duration,
                        groupValue: _autoLockDuration,
                        onChanged: (value) => Navigator.pop(context, value),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _securityManager.getAutoLockDurationText(duration),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
        );
      },
    );

    if (result != null) {
      await _securityManager.setAutoLockDuration(result);
      await _loadSecuritySettings();
    }
  }

  /// نمایش dialog انتخاب lock method
  Future<void> _showLockMethodDialog() async {
    final lockMethodOptions = <LockMethod, String>{
      LockMethod.passcodeAndBiometric: _safeTranslate('passcode_biometric_recommended', 'Passcode / Biometric (Recommended)'),
      LockMethod.passcodeOnly: _safeTranslate('passcode_only', 'Passcode Only'),
      LockMethod.biometricOnly: _safeTranslate('biometric_only', 'Biometric Only'),
    };

    final result = await showModalBottomSheet<LockMethod>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6F3),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _safeTranslate('select_lock_method', 'Select Lock Method'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ...lockMethodOptions.entries.map((entry) {
                final method = entry.key;
                final label = entry.value;
                
                // بررسی در دسترس بودن روش
                bool isAvailable = true;
                String disabledReason = '';
                
                if (method == LockMethod.biometricOnly || method == LockMethod.passcodeAndBiometric) {
                  if (!_biometricAvailable) {
                    isAvailable = false;
                    disabledReason = _safeTranslate('biometric_not_available', 'Biometric not available');
                  }
                }
                
                if (method == LockMethod.passcodeOnly || method == LockMethod.passcodeAndBiometric) {
                  if (!_passcodeSet) {
                    isAvailable = false;
                    disabledReason = _safeTranslate('passcode_not_set', 'Passcode not set');
                  }
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isAvailable ? () => Navigator.pop(context, method) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
                    child: Row(
                      children: [
                        Radio<LockMethod>(
                          value: method,
                          groupValue: _lockMethod,
                          onChanged: isAvailable ? (value) => Navigator.pop(context, value) : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isAvailable ? Colors.black : Colors.grey,
                                ),
                              ),
                              if (!isAvailable && disabledReason.isNotEmpty)
                                Text(
                                  disabledReason,
                                  style: const TextStyle(fontSize: 12, color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                        if (method == LockMethod.passcodeAndBiometric)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _safeTranslate('recommended', 'Recommended'),
                              style: const TextStyle(fontSize: 10, color: Colors.green),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );

    if (result != null) {
      final success = await _securityManager.setLockMethod(result);
      if (success) {
        await _loadSecuritySettings();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _safeTranslate('lock_method_updated', 'Lock method updated successfully')
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _safeTranslate('lock_method_update_failed', 'Failed to update lock method')
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('security', 'Security'), style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_safeTranslate('security', 'Security'), style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            
            // گزینه اول: Passcode Toggle
            _SettingItemWithSwitch(
              title: _safeTranslate('passcode', 'Passcode'),
              subtitle: _passcodeEnabled && _passcodeSet
                  ? _safeTranslate('passcode_enabled_description', 'App will require passcode to unlock')
                  : _safeTranslate('passcode_disabled_description', 'App will open without passcode'),
              value: _passcodeEnabled,
              onChanged: _togglePasscode,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه دوم: Auto-lock Duration
            _SettingItem(
              title: _safeTranslate('auto_lock', 'Auto-lock'),
              subtitle: _securityManager.getAutoLockDurationText(_autoLockDuration),
              onTap: _passcodeEnabled ? _showAutoLockDialog : null,
              isDisabled: !_passcodeEnabled,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه سوم: Lock Method
            _SettingItem(
              title: _safeTranslate('lock_method', 'Lock method'),
              subtitle: _securityManager.getLockMethodText(_lockMethod),
              onTap: _passcodeEnabled ? _showLockMethodDialog : null,
              isDisabled: !_passcodeEnabled,
            ),
            
            const SizedBox(height: 24),
            
            // اطلاعات اضافی
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _safeTranslate('security_info', 'Security Information'),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _safeTranslate('security_description', 'Configure security settings to protect your wallet. Passcode and biometric authentication help keep your assets safe.'),
                    style: const TextStyle(fontSize: 14, color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _biometricAvailable ? Icons.check_circle : Icons.error,
                        color: _biometricAvailable ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _biometricAvailable 
                          ? _safeTranslate('biometric_available', 'Biometric authentication available')
                          : _safeTranslate('biometric_not_available', 'Biometric authentication not available'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _biometricAvailable ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SettingItemWithSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  
  const _SettingItemWithSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF0BAB9B),
          ),
        ],
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDisabled;
  
  const _SettingItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isDisabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDisabled ? Colors.grey : Colors.black,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDisabled ? Colors.grey.withOpacity(0.7) : Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDisabled ? Colors.grey.withOpacity(0.5) : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 