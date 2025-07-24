import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/security_settings_manager.dart';
import '../services/passcode_manager.dart';
import 'passcode_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Added for kDebugMode
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Added for SecureStorage

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({Key? key}) : super(key: key);

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> with WidgetsBindingObserver {
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  bool _isLoading = true;
  bool _passcodeEnabled = true;
  AutoLockDuration _autoLockDuration = AutoLockDuration.immediate;
  LockMethod _lockMethod = LockMethod.passcodeAndBiometric;
  bool _biometricAvailable = false;
  bool _passcodeSet = false;
  
  // Auto-lock variables
  DateTime? _backgroundTime;
  bool _isInBackground = false;

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
    WidgetsBinding.instance.addObserver(this);
    _initializeAndLoadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App lifecycle handler for auto-lock
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _handleAppGoingToBackground();
        break;
      case AppLifecycleState.resumed:
        _handleAppComingToForeground();
        break;
      default:
        break;
    }
  }

  /// Handle app going to background
  void _handleAppGoingToBackground() {
    if (_passcodeEnabled && _passcodeSet) {
      _backgroundTime = DateTime.now();
      _isInBackground = true;
      print('🔒 App went to background at: $_backgroundTime');
    }
  }

  /// Handle app coming to foreground
  void _handleAppComingToForeground() {
    if (_isInBackground && _backgroundTime != null && _passcodeEnabled && _passcodeSet) {
      _isInBackground = false;
      final currentTime = DateTime.now();
      final elapsedTime = currentTime.difference(_backgroundTime!);
      
      print('🔓 App came to foreground. Elapsed time: ${elapsedTime.inSeconds}s');
      
      // Check if auto-lock should be triggered
      if (_shouldLockApp(elapsedTime)) {
        _triggerAutoLock();
      }
      
      _backgroundTime = null;
    }
  }

  /// Determine if app should be locked based on elapsed time
  bool _shouldLockApp(Duration elapsedTime) {
    switch (_autoLockDuration) {
      case AutoLockDuration.immediate:
        return true; // Always lock immediately
      case AutoLockDuration.oneMinute:
        return elapsedTime.inMinutes >= 1;
      case AutoLockDuration.fiveMinutes:
        return elapsedTime.inMinutes >= 5;
      case AutoLockDuration.tenMinutes:
        return elapsedTime.inMinutes >= 10;
      case AutoLockDuration.fifteenMinutes:
        return elapsedTime.inMinutes >= 15;
      default:
        return false;
    }
  }

  /// Trigger auto-lock by showing passcode screen
  void _triggerAutoLock() {
    if (!mounted) return;
    
    print('🔒 Triggering auto-lock...');
    
    // Show passcode screen as modal that cannot be dismissed
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WillPopScope(
          onWillPop: () async => false, // Prevent back button
          child: PasscodeScreen(
            title: _safeTranslate('enter_passcode', 'Enter Passcode'),
            onSuccess: () {
              Navigator.pop(context);
              print('🔓 Auto-lock passcode entered successfully');
            },
            isFromBackground: true,
          ),
        ),
        settings: const RouteSettings(name: '/auto_lock'),
      ),
    );
  }

  /// مقداردهی و بارگذاری تنظیمات
  Future<void> _initializeAndLoadSettings() async {
    try {
      // مقداردهی SecuritySettingsManager
      await _securityManager.initialize();
      
      // بارگذاری تنظیمات
      await _loadSecuritySettings();
      
      // Check if this is the first time accessing security screen
      // We want passcode to be enabled by default (user requirement)
      final prefs = await SharedPreferences.getInstance();
      const securityScreenAccessedKey = 'security_screen_accessed';
      
      // If this is the first time accessing security screen
      final hasAccessedBefore = prefs.getBool(securityScreenAccessedKey) ?? false;
      if (!hasAccessedBefore) {
        // Check if passcode is already set
        final passcodeAlreadySet = await PasscodeManager.isPasscodeSet();
        
        if (passcodeAlreadySet) {
          // If passcode is already set, just enable it
          await _securityManager.setPasscodeEnabled(true);
          await prefs.setBool(securityScreenAccessedKey, true);
          print('🔒 Passcode already set - enabled by default');
        } else {
          // If passcode is not set, show setup dialog
          _showInitialPasscodeSetupDialog();
        }
        
        // Reload settings after potential changes
        await _loadSecuritySettings();
      }
    } catch (e) {
      print('❌ Error initializing security screen: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// نمایش dialog اولیه برای تنظیم passcode
  void _showInitialPasscodeSetupDialog() {
    // Remove dialog - initial passcode setup dialog removed
  }

  /// بارگذاری تنظیمات امنیتی
  Future<void> _loadSecuritySettings() async {
    try {
      final settings = await _securityManager.getSecuritySettingsSummary();
      
      if (mounted) {
        setState(() {
          _passcodeEnabled = settings['passcodeEnabled'] ?? true; // Default to true
          _autoLockDuration = settings['autoLockDuration'] ?? AutoLockDuration.immediate;
          _lockMethod = settings['lockMethod'] ?? LockMethod.passcodeAndBiometric;
          _biometricAvailable = settings['biometricAvailable'] ?? false;
          _passcodeSet = settings['passcodeSet'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading security settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                // بعد از تنظیم موفقیت‌آمیز passcode، آن را فعال کن
                await _securityManager.setPasscodeEnabled(true);
                await _loadSecuritySettings();
                
                if (mounted) {
                  Navigator.pop(context);
                  
                  // Show success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _safeTranslate('passcode_set_successfully', 'Passcode set and enabled successfully')
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
          ),
        );
        
        // اگر کاربر از passcode screen بازگشت بدون تنظیم passcode، toggle را غیرفعال کن
        if (result == null) {
          await _loadSecuritySettings(); // Reload to reset the toggle
        }
        
        return;
      }
      
      if (!enabled) {
        // اگر کاربر می‌خواهد passcode را غیرفعال کند
        final confirmDisable = await _showConfirmDisableDialog();
        if (!confirmDisable) {
          await _loadSecuritySettings(); // Reset toggle to previous state
          return;
        }
      }

      final success = await _securityManager.setPasscodeEnabled(enabled);
      if (success) {
        await _loadSecuritySettings();
        
        // Reset auto-lock tracking when passcode is disabled
        if (!enabled) {
          _backgroundTime = null;
          _isInBackground = false;
        }
        
        if (mounted) {
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
        }
      } else {
        if (mounted) {
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
        
        // Reset toggle to previous state on failure
        await _loadSecuritySettings();
      }
    } catch (e) {
      print('❌ Error toggling passcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('error_occurred', 'An error occurred: {error}').replaceAll('{error}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      // Reset toggle to previous state on error
      await _loadSecuritySettings();
    }
  }

  /// نمایش تأیید غیرفعال کردن passcode
  Future<bool> _showConfirmDisableDialog() async {
    // Remove dialog - confirm disable dialog removed
    return true; // Always return true to allow disabling
  }

  /// نمایش dialog انتخاب auto-lock duration
  Future<void> _showAutoLockDialog() async {
    // Remove modal bottom sheet - auto lock dialog removed
  }

  /// نمایش dialog انتخاب lock method
  Future<void> _showLockMethodDialog() async {
    // Remove modal bottom sheet - lock method dialog removed
  }

  /// Get description for auto-lock duration
  String _getAutoLockDescription(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return _safeTranslate('lock_immediately_desc', 'Lock as soon as app goes to background');
      case AutoLockDuration.oneMinute:
        return _safeTranslate('lock_after_1min_desc', 'Lock after 1 minute in background');
      case AutoLockDuration.fiveMinutes:
        return _safeTranslate('lock_after_5min_desc', 'Lock after 5 minutes in background');
      case AutoLockDuration.tenMinutes:
        return _safeTranslate('lock_after_10min_desc', 'Lock after 10 minutes in background');
      case AutoLockDuration.fifteenMinutes:
        return _safeTranslate('lock_after_15min_desc', 'Lock after 15 minutes in background');
      default:
        return '';
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
              subtitle: _getPasscodeStatusText(),
              value: _passcodeEnabled,
              onChanged: _togglePasscode,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه دوم: Auto-lock Duration
            _SettingItem(
              title: _safeTranslate('auto_lock', 'Auto-lock'),
              subtitle: _getAutoLockStatusText(),
              onTap: _passcodeEnabled ? _showAutoLockDialog : null,
              isDisabled: !_passcodeEnabled,
              trailing: _passcodeEnabled ? _buildAutoLockIndicator() : null,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه سوم: Lock Method
            _SettingItem(
              title: _safeTranslate('lock_method', 'Lock method'),
              subtitle: _getLockMethodStatusText(),
              onTap: _passcodeEnabled ? _showLockMethodDialog : null,
              isDisabled: !_passcodeEnabled,
              trailing: _passcodeEnabled ? _buildLockMethodIndicator() : null,
            ),
            
            const SizedBox(height: 24),
            
            // Auto-lock Status Card (only show when passcode is enabled)
            if (_passcodeEnabled && _passcodeSet)
              _buildAutoLockStatusCard(),
            
            const SizedBox(height: 16),
            
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
            
            // Debug button for testing passcode persistence
            if (kDebugMode) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bug_report, color: Colors.purple),
                  title: Text(_safeTranslate('debug_passcode_state', 'Debug Passcode State')),
                  subtitle: Text(_safeTranslate('debug_passcode_subtitle', 'Test passcode persistence')),
                  onTap: _debugPasscodeState,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Debug method to test passcode state
  Future<void> _debugPasscodeState() async {
    try {
      print('🔍 === MANUAL PASSCODE DEBUG ===');
      
      // Check SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      final passcodeSalt = prefs.getString('passcode_salt');
      print('🔑 SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SharedPreferences passcode_salt = ${passcodeSalt != null ? "EXISTS" : "NULL"}');
      
      // Check SecureStorage backup
      const secureStorage = FlutterSecureStorage();
      final secureHash = await secureStorage.read(key: 'passcode_hash_secure');
      final secureSalt = await secureStorage.read(key: 'passcode_salt_secure');
      print('🔑 SecureStorage passcode_hash_secure = ${secureHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SecureStorage passcode_salt_secure = ${secureSalt != null ? "EXISTS" : "NULL"}');
      
      // Use PasscodeManager to check
      final isPasscodeSet = await PasscodeManager.isPasscodeSet();
      print('🔑 PasscodeManager.isPasscodeSet() = $isPasscodeSet');
      
      // Check if enabled in settings
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      print('🔑 SecuritySettingsManager.isPasscodeEnabled() = $isPasscodeEnabled');
      
      print('🔍 === END MANUAL DEBUG ===');
      
      // Show dialog with results
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Passcode Debug Results'),
            content: Text(
              'SharedPreferences:\n'
              'passcode_hash: ${passcodeHash != null ? "EXISTS" : "NULL"}\n'
              'passcode_salt: ${passcodeSalt != null ? "EXISTS" : "NULL"}\n\n'
              'SecureStorage:\n'
              'passcode_hash_secure: ${secureHash != null ? "EXISTS" : "NULL"}\n'
              'passcode_salt_secure: ${secureSalt != null ? "EXISTS" : "NULL"}\n\n'
              'PasscodeManager.isPasscodeSet(): $isPasscodeSet\n'
              'SecurityManager.isPasscodeEnabled(): $isPasscodeEnabled',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Error in debug: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debug error: $e')),
        );
      }
    }
  }

  /// Get passcode status text
  String _getPasscodeStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('passcode_disabled_description', 'App will open without passcode');
    }
    
    if (_passcodeSet) {
      return _safeTranslate('passcode_enabled_description', 'App will require passcode to unlock');
    }
    
    return _safeTranslate('passcode_not_set_description', 'Passcode not configured yet');
  }

  /// Get auto-lock status text
  String _getAutoLockStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('auto_lock_disabled_description', 'Enable passcode to use auto-lock');
    }
    
    final durationText = _securityManager.getAutoLockDurationText(_autoLockDuration);
    return _safeTranslate('auto_lock_enabled_description', 'Lock after: {duration}').replaceAll('{duration}', durationText);
  }

  /// Get lock method status text
  String _getLockMethodStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('lock_method_disabled_description', 'Enable passcode to select lock method');
    }
    
    return _securityManager.getLockMethodText(_lockMethod);
  }

  /// Build auto-lock indicator
  Widget _buildAutoLockIndicator() {
    Color color;
    switch (_autoLockDuration) {
      case AutoLockDuration.immediate:
        color = Colors.green;
        break;
      case AutoLockDuration.oneMinute:
        color = Colors.orange;
        break;
      default:
        color = Colors.red;
    }
    
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  /// Build lock method indicator
  Widget _buildLockMethodIndicator() {
    IconData icon;
    Color color;
    
    switch (_lockMethod) {
      case LockMethod.passcodeAndBiometric:
        icon = Icons.security;
        color = Colors.green;
        break;
      case LockMethod.passcodeOnly:
        icon = Icons.lock;
        color = Colors.orange;
        break;
      case LockMethod.biometricOnly:
        icon = Icons.fingerprint;
        color = Colors.blue;
        break;
    }
    
    return Icon(icon, color: color, size: 16);
  }

  /// Build auto-lock status card
  Widget _buildAutoLockStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isInBackground ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isInBackground ? Colors.orange.withOpacity(0.3) : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isInBackground ? Icons.pause_circle : Icons.play_circle,
                color: _isInBackground ? Colors.orange : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _safeTranslate('auto_lock_status', 'Auto-lock Status'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isInBackground ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isInBackground 
              ? _safeTranslate('app_in_background', 'App is in background - auto-lock timer is running')
              : _safeTranslate('app_in_foreground', 'App is active - auto-lock timer is paused'),
            style: TextStyle(
              fontSize: 14,
              color: _isInBackground ? Colors.orange : Colors.green,
            ),
          ),
          if (_backgroundTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _safeTranslate('background_since', 'Background since: {time}').replaceAll(
                  '{time}', 
                  DateFormat('HH:mm:ss').format(_backgroundTime!),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
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
  final Widget? trailing; // Added trailing widget
  
  const _SettingItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDisabled = false,
    this.trailing, // Initialize trailing
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
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
                const SizedBox(width: 8),
              ],
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