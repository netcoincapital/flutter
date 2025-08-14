import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/passcode_manager.dart';
import '../services/wallet_state_manager.dart';
import '../services/security_settings_manager.dart';
import 'dart:async'; // Added for Timer

class PasscodeScreen extends StatefulWidget {
  final String title;
  final String? walletName;
  final String? firstPasscode; // برای تایید
  final String? savedPasscode; // برای ورود
  final VoidCallback? onSuccess; // تابعی که بعد از موفقیت اجرا می‌شود
  final bool isFromBackground; // آیا از بازگشت از پس‌زمینه است
  
  const PasscodeScreen({
    Key? key,
    required this.title,
    this.walletName,
    this.firstPasscode,
    this.savedPasscode,
    this.onSuccess,
    this.isFromBackground = false,
  }) : super(key: key);

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> with WidgetsBindingObserver {
  String enteredCode = '';
  String errorMessage = '';
  bool isConfirmed = false;
  bool isBiometricAvailable = false;
  bool isLocked = false;
  int remainingAttempts = 5;
  int lockoutRemainingTime = 0;
  
  final LocalAuthentication auth = LocalAuthentication();
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  LockMethod _lockMethod = LockMethod.passcodeAndBiometric;
  bool _canUseBiometric = false;
  bool _canUsePasscode = true;

  final borderColors = const [
    Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
    Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb)
  ];

  Timer? _lockoutTimer;
  Timer? _navigationTimeout;

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
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _securityManager.initialize(); // مقداردهی SecuritySettingsManager
    await _checkBiometric();
    await _checkLockStatus();
    await _loadSecuritySettings();
    _redirectIfPasscodeExists();
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final lockMethod = await _securityManager.getLockMethod();
      final canUseBiometric = await _securityManager.canUseBiometricInCurrentLockMethod();
      final canUsePasscode = await _securityManager.canUsePasscodeInCurrentLockMethod();
      
      setState(() {
        _lockMethod = lockMethod;
        _canUseBiometric = canUseBiometric && isBiometricAvailable;
        _canUsePasscode = canUsePasscode;
      });
    } catch (e) {
      print('❌ Error loading security settings: $e');
    }
  }

  Future<void> _redirectIfPasscodeExists() async {
    // Prevent showing choose/confirm passcode if passcode already exists
    if (widget.title == _safeTranslate('choose_passcode', 'Choose Passcode') || 
        widget.title == _safeTranslate('confirm_passcode', 'Confirm Passcode')) {
      final isSet = await PasscodeManager.isPasscodeSet();
      if (isSet) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/enter-passcode');
        }
      }
    }
  }

  Future<void> _checkBiometric() async {
    final canCheck = await auth.canCheckBiometrics;
    final available = await auth.isDeviceSupported();
    setState(() {
      isBiometricAvailable = canCheck && available;
    });
  }

  Future<void> _checkLockStatus() async {
    final locked = await PasscodeManager.isLocked();
    final attempts = await PasscodeManager.getRemainingAttempts();
    final lockoutTime = await PasscodeManager.getLockoutRemainingTime();
    
    setState(() {
      isLocked = locked;
      remainingAttempts = attempts;
      lockoutRemainingTime = lockoutTime;
    });
    
    if (locked) {
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    // Cancel existing timer
    _lockoutTimer?.cancel();
    
    // Use Timer.periodic instead of recursive Future.delayed
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final remaining = await PasscodeManager.getLockoutRemainingTime();
      setState(() {
        lockoutRemainingTime = remaining;
      });
      
      if (remaining <= 0) {
        timer.cancel();
        await _checkLockStatus();
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _onNumberTap(String number) {
    if (isLocked || isConfirmed) return; // جلوگیری از ورودی اضافی
    
    if (enteredCode.length < 6) {
      setState(() {
        enteredCode += number;
        HapticFeedback.lightImpact();
        
        // پاک کردن پیام خطا هنگام تایپ جدید
        if (errorMessage.isNotEmpty) {
          errorMessage = '';
        }
      });
    }
  }

  void _onDelete() {
    if (enteredCode.isNotEmpty) {
      setState(() {
        enteredCode = enteredCode.substring(0, enteredCode.length - 1);
        HapticFeedback.lightImpact();
      });
    }
  }

  void _onBiometric() async {
    HapticFeedback.lightImpact();
    try {
      // بررسی در دسترس بودن biometric
      if (!_canUseBiometric) {
        setState(() {
          errorMessage = _safeTranslate('biometric_not_available', 'Biometric authentication is not available');
        });
        return;
      }
      
      // بررسی دقیق‌تر وضعیت بیومتریک
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.isDeviceSupported();
      final availableBiometrics = await auth.getAvailableBiometrics();
      
      if (!canCheck || !available || availableBiometrics.isEmpty) {
        setState(() {
          errorMessage = _safeTranslate('biometric_not_available', 'Biometric authentication is not available on this device');
        });
        return;
      }
      
      final didAuth = await auth.authenticate(
        localizedReason: _safeTranslate('authenticate_to_continue', 'Authenticate to continue'),
        options: const AuthenticationOptions(
          biometricOnly: false, // اجازه PIN/Pattern نیز داده شود
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      
      if (didAuth) {
        _handleSuccessfulAuthentication();
      } else {
        setState(() {
          errorMessage = _safeTranslate('authentication_cancelled', 'Authentication was cancelled or failed');
        });
      }
    } catch (e) {
      print('Biometric error: $e');
      setState(() {
        errorMessage = _safeTranslate('biometric_authentication_error', 'Biometric authentication error: {error}').replaceAll('{error}', e.toString());
      });
    }
  }

  void _handleSuccessfulAuthentication() {
    switch (widget.title) {
      case 'Choose Passcode':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PasscodeScreen(
              title: _safeTranslate('confirm_passcode', 'Confirm Passcode'),
              walletName: widget.walletName,
              firstPasscode: enteredCode,
              onSuccess: widget.onSuccess,
            ),
          ),
        );
        break;
      case 'Confirm Passcode':
        Navigator.pushReplacementNamed(context, '/backup', arguments: {'walletName': widget.walletName});
        break;
      case 'Enter Passcode':
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
        break;
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _navigationTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PasscodeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر عنوان یا پس‌کد اولیه تغییر کرد، ورودی را ریست کن
    if (widget.title != oldWidget.title || widget.firstPasscode != oldWidget.firstPasscode) {
      setState(() {
        enteredCode = '';
        errorMessage = '';
      });
    }
  }

  void _handlePasscodeComplete() async {
    if (isConfirmed || isLocked) return; // جلوگیری از اجرای مجدد
    
    setState(() {
      isConfirmed = true; // فلگ برای جلوگیری از تکرار
    });

    print('🔐 Passcode complete: ${widget.title}');
    
    // Timeout fallback - reset state if navigation doesn't complete
    _navigationTimeout?.cancel();
    _navigationTimeout = Timer(const Duration(seconds: 10), () {
      print('⚠️ Navigation timeout - resetting state');
      if (mounted && isConfirmed) {
        setState(() {
          isConfirmed = false;
          errorMessage = 'Navigation failed. Please try again.';
          enteredCode = '';
        });
      }
    });
    
    try {
      switch (widget.title) {
        case 'Choose Passcode':
          print('🔐 Navigating to Confirm Passcode');
          // به صفحه تایید برو و پس‌کد را منتقل کن
          if (mounted) {
            _navigationTimeout?.cancel(); // Cancel timeout on successful navigation
            await Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PasscodeScreen(
                  title: _safeTranslate('confirm_passcode', 'Confirm Passcode'),
                  walletName: widget.walletName,
                  firstPasscode: enteredCode,
                  onSuccess: widget.onSuccess,
                ),
              ),
            );
          }
          break;
          
        case 'Confirm Passcode':
          print('🔐 Confirming passcode: ${widget.firstPasscode} == $enteredCode');
          if (widget.firstPasscode == enteredCode) {
            try {
              print('🔐 Setting passcode...');
              // ذخیره پس‌کد
              final success = await PasscodeManager.setPasscode(enteredCode);
              print('🔐 Passcode set success: $success');
              
              if (success) {
                print('🔐 Passcode saved successfully');
                // موفقیت: رفتن به صفحه بعد
                _navigationTimeout?.cancel(); // Cancel timeout on successful navigation
                if (widget.onSuccess != null) {
                  print('🔐 Calling onSuccess callback');
                  widget.onSuccess!();
                } else {
                  print('🔐 No callback, checking wallet state');
                  // Check if we have wallet data to go to backup, otherwise go to home
                  final hasWallet = await WalletStateManager.instance.hasWallet();
                  print('🔐 Has wallet: $hasWallet, walletName: ${widget.walletName}');
                  
                  if (mounted) {
                    if (hasWallet && widget.walletName != null) {
                      print('🔐 Navigating to backup screen');
                      Navigator.pushReplacementNamed(context, '/backup', arguments: {'walletName': widget.walletName});
                    } else {
                      print('🔐 Navigating to home screen');
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  }
                }
              } else {
                print('❌ Failed to set passcode');
                if (mounted) {
                  setState(() {
                    errorMessage = _safeTranslate('failed_to_set_passcode', 'Failed to set passcode. Please try again.');
                    enteredCode = '';
                    isConfirmed = false;
                  });
                }
              }
            } catch (e) {
              print('❌ Error setting passcode: $e');
              if (mounted) {
                setState(() {
                  errorMessage = _safeTranslate('error_setting_passcode', 'Error setting passcode: {error}').replaceAll('{error}', e.toString());
                  enteredCode = '';
                  isConfirmed = false;
                });
              }
            }
          } else {
            print('❌ Passcode mismatch');
            if (mounted) {
              setState(() {
                errorMessage = _safeTranslate('passcode_mismatch', 'The passcode entered is not the same');
                enteredCode = '';
                isConfirmed = false;
              });
            }
          }
          break;
          
        case 'Enter Passcode':
          print('🔐 Verifying passcode...');
          try {
            final isValid = await PasscodeManager.verifyPasscode(enteredCode);
            print('🔐 Passcode valid: $isValid');
            
            if (isValid) {
              print('🔐 Passcode verification successful');
              
              // 🔄 CRITICAL: Reset activity timer on successful passcode entry
              try {
                await SecuritySettingsManager.instance.resetActivityTimer();
                print('🔄 Activity timer reset after successful passcode entry');
              } catch (e) {
                print('❌ Error resetting activity timer: $e');
              }
              
              _navigationTimeout?.cancel(); // Cancel timeout on successful navigation
              if (widget.onSuccess != null) {
                print('🔐 Calling onSuccess callback');
                widget.onSuccess!();
              } else {
                print('🔐 Navigating to home');
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              }
            } else {
              print('❌ Invalid passcode');
              await _checkLockStatus();
              final attemptsRemaining = remainingAttempts > 0 
                ? _safeTranslate('attempts_remaining', '{count} attempts remaining').replaceAll('{count}', remainingAttempts.toString())
                : _safeTranslate('wallet_locked', 'Wallet is locked');
              
              if (mounted) {
                setState(() {
                  errorMessage = _safeTranslate('incorrect_passcode', 'Incorrect passcode. {attemptsRemaining}').replaceAll('{attemptsRemaining}', attemptsRemaining);
                  enteredCode = '';
                  isConfirmed = false;
                });
              }
            }
          } catch (e) {
            print('❌ Error verifying passcode: $e');
            await _checkLockStatus();
            if (mounted) {
              setState(() {
                errorMessage = e.toString();
                enteredCode = '';
                isConfirmed = false;
              });
            }
          }
          break;
      }
    } catch (e) {
      print('❌ General error in _handlePasscodeComplete: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'An error occurred. Please try again.';
          enteredCode = '';
          isConfirmed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // منطق بررسی پس‌کد - فقط یک بار اجرا شود
    if (enteredCode.length == 6 && !isConfirmed && !isLocked) {
      // استفاده از WidgetsBinding برای اجرای محفوظ
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isConfirmed) {
          _handlePasscodeComplete();
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Text(
              _getTranslatedTitle(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Debug info (only in debug mode)
            if (kDebugMode)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text('Debug: ${widget.title}', style: const TextStyle(fontSize: 10)),
                    Text('Length: ${enteredCode.length}/6', style: const TextStyle(fontSize: 10)),
                    Text('Confirmed: $isConfirmed', style: const TextStyle(fontSize: 10)),
                    Text('Locked: $isLocked', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            if (errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: borderColors[index % borderColors.length],
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      if (index < enteredCode.length)
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: borderColors[index % borderColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            if (isLocked)
              Column(
                children: [
                  const Icon(Icons.lock, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    _safeTranslate('wallet_is_locked', 'Wallet is locked'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _safeTranslate('try_again_in', 'Try again in {time}').replaceAll('{time}', _formatTime(lockoutRemainingTime)),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Text(
                    _safeTranslate('passcode_adds_security', 'Passcode adds an extra layer of security\nwhen using the app'),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  // نمایش روش‌های احراز هویت در دسترس
                  if (_lockMethod != LockMethod.passcodeOnly && _canUseBiometric)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fingerprint, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            _safeTranslate('biometric_available', 'Biometric authentication available'),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 40),
            _NumberPad(
              onNumberTap: _onNumberTap,
              onDelete: _onDelete,
              onBiometric: _onBiometric,
              showBiometric: _canUseBiometric && !isLocked,
              isLocked: isLocked,
            ),
          ],
        ),
      ),
    );
  }

  String _getTranslatedTitle() {
    switch (widget.title) {
      case 'Choose Passcode':
        return _safeTranslate('choose_passcode', 'Choose Passcode');
      case 'Confirm Passcode':
        return _safeTranslate('confirm_passcode', 'Confirm Passcode');
      case 'Enter Passcode':
        return _safeTranslate('enter_passcode', 'Enter Passcode');
      default:
        return widget.title;
    }
  }
}

class _NumberPad extends StatelessWidget {
  final void Function(String) onNumberTap;
  final VoidCallback onDelete;
  final VoidCallback onBiometric;
  final bool showBiometric;
  final bool isLocked;
  const _NumberPad({required this.onNumberTap, required this.onDelete, required this.onBiometric, this.showBiometric = true, this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('1', onNumberTap, isLocked: isLocked),
            _NumButton('2', onNumberTap, isLocked: isLocked),
            _NumButton('3', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('4', onNumberTap, isLocked: isLocked),
            _NumButton('5', onNumberTap, isLocked: isLocked),
            _NumButton('6', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('7', onNumberTap, isLocked: isLocked),
            _NumButton('8', onNumberTap, isLocked: isLocked),
            _NumButton('9', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            showBiometric
                ? _CircleIconButton(
                    icon: Icons.fingerprint,
                    onTap: onBiometric,
                    isLocked: isLocked,
                  )
                : _CircleIconButton(
                    icon: null,
                    onTap: () {}, // دکمه غیر فعال
                    isLocked: isLocked,
                  ),
            _NumButton('0', onNumberTap, isLocked: isLocked),
            _CircleIconButton(
              icon: Icons.backspace,
              onTap: isLocked ? () {} : onDelete,
              isLocked: isLocked,
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback onTap;
  final bool isLocked;
  const _CircleIconButton({required this.icon, required this.onTap, this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: isLocked ? null : onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isLocked ? Colors.grey.withOpacity(0.3) : const Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, size: 28, color: isLocked ? Colors.grey.withOpacity(0.5) : Colors.grey) : null,
        ),
      ),
    );
  }
}

class _NumButton extends StatelessWidget {
  final String number;
  final void Function(String) onTap;
  final bool isLocked;
  const _NumButton(this.number, this.onTap, {this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: isLocked ? null : () => onTap(number),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isLocked ? Colors.grey.withOpacity(0.3) : const Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 28, 
              fontWeight: FontWeight.bold, 
              color: isLocked ? Colors.grey : Colors.black
            ),
          ),
        ),
      ),
    );
  }
} 