import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/passcode_manager.dart';
import '../services/security_settings_manager.dart';
import 'home_screen.dart';
import 'backup_screen.dart';
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
    
    // 🔧 FIX: Debug current title and language
    print('🔍 PasscodeScreen initialized with title: "${widget.title}"');
    print('🔍 Current locale: ${context.locale}');
    
    // تست ترجمه‌ها
    final chooseTest = _safeTranslate('choose_passcode', 'Choose Passcode');
    final confirmTest = _safeTranslate('confirm_passcode', 'Confirm Passcode');
    final enterTest = _safeTranslate('enter_passcode', 'Enter Passcode');
    
    print('🔍 Translation test:');
    print('🔍   choose_passcode -> "$chooseTest"');
    print('🔍   confirm_passcode -> "$confirmTest"');
    print('🔍   enter_passcode -> "$enterTest"');
    print('🔍 Normalized title will be: "${_getNormalizedTitle(widget.title)}"');
    
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
    final normalizedTitle = _getNormalizedTitle(widget.title);
    if (normalizedTitle == 'choose_passcode' || normalizedTitle == 'confirm_passcode') {
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
    final normalizedTitle = _getNormalizedTitle(widget.title);
    print('🔐 Biometric success - normalized title: $normalizedTitle');
    
    switch (normalizedTitle) {
      case 'choose_passcode':
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
      case 'confirm_passcode':
        // ANDROID FIX: Use direct MaterialPageRoute for better compatibility
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BackupScreen(
              walletName: widget.walletName ?? 'Unknown Wallet',
            ),
          ),
        );
        break;
      case 'enter_passcode':
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          // ANDROID FIX: Use direct MaterialPageRoute for better compatibility
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
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
    
    // Cancel any existing timeout
    _navigationTimeout?.cancel();
    
    // Add a safety reset mechanism (20 seconds fallback for faster recovery)
    _navigationTimeout = Timer(const Duration(seconds: 20), () {
      print('⚠️ Safety reset triggered after 20 seconds');
      if (mounted && isConfirmed) {
        setState(() {
          isConfirmed = false;
          enteredCode = '';
          errorMessage = _safeTranslate('timeout_error', 'Operation timed out. Please try again.');
        });
      }
    });
    
    try {
      // 🔧 FIX: Use normalized title comparison instead of direct string comparison
      // This fixes the issue when phone language is not English
      final normalizedTitle = _getNormalizedTitle(widget.title);
      print('🔐 Normalized title: $normalizedTitle');
      
      switch (normalizedTitle) {
        case 'choose_passcode':
          print('🔐 Navigating to Confirm Passcode');
          // به صفحه تایید برو و پس‌کد را منتقل کن
          if (mounted) {
            // Add small delay to ensure UI is ready
            await Future.delayed(const Duration(milliseconds: 100));
            
            if (!mounted) return;
            
            try {
              _navigationTimeout?.cancel(); // Cancel safety timer on success
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
              print('🔐 Navigation to confirm passcode completed');
            } catch (e) {
              print('❌ Navigation error: $e');
              if (mounted) {
                setState(() {
                  errorMessage = _safeTranslate('navigation_error', 'Navigation error. Please try again.');
                  enteredCode = '';
                  isConfirmed = false;
                });
              }
            }
          }
          break;
          
        case 'confirm_passcode':
          print('🔐 Confirming passcode: ${widget.firstPasscode} == $enteredCode');
          if (widget.firstPasscode == enteredCode) {
            try {
              print('🔐 Setting passcode...');
              // ذخیره پس‌کد
              final success = await PasscodeManager.setPasscode(enteredCode)
                .timeout(const Duration(seconds: 15));
              print('🔐 Passcode set success: $success');
              
              if (success) {
                print('🔐 Passcode saved successfully');
                // موفقیت: رفتن به صفحه بعد
                _navigationTimeout?.cancel(); // Cancel safety timer on success
                if (widget.onSuccess != null) {
                  print('🔐 Calling onSuccess callback');
                  widget.onSuccess!();
                } else {
                                        print('🔐 No callback, navigating to home');
                      
                      if (mounted) {
                        // Add small delay to ensure UI is ready
                        await Future.delayed(const Duration(milliseconds: 200));
                        
                        if (!mounted) return;
                        
                        try {
                          // ANDROID FIX: Use direct MaterialPageRoute instead of named route
                          // This prevents navigation issues in Android
                          print('🔐 Passcode confirmed - navigating to home screen (Android fix)');
                          _navigationTimeout?.cancel(); // Cancel safety timer before navigation
                          
                          await Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeScreen()),
                            (route) => false,
                          );
                          
                          print('🔐 Navigation to home completed successfully');
                        } catch (e) {
                          print('❌ Navigation error: $e');
                          if (mounted) {
                            // Secondary fallback: try named route
                            try {
                              print('🔄 Secondary fallback: trying named route');
                              await Navigator.pushReplacementNamed(context, '/home');
                              print('🔐 Named route navigation successful');
                            } catch (e2) {
                              print('❌ Named route also failed: $e2');
                              // Final fallback: reset the screen state and show error
                              setState(() {
                                errorMessage = _safeTranslate('navigation_error', 'Navigation error. Please restart the app.');
                                enteredCode = '';
                                isConfirmed = false;
                              });
                            }
                          }
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
          
        case 'enter_passcode':
          print('🔐 Verifying passcode...');
          try {
            final isValid = await PasscodeManager.verifyPasscode(enteredCode)
                .timeout(const Duration(seconds: 10));
            print('🔐 Passcode valid: $isValid');
            
            if (isValid) {
              print('🔐 Passcode verification successful');
              
              // 🔄 CRITICAL: Reset activity timer on successful passcode entry (with timeout)
              try {
                await SecuritySettingsManager.instance.resetActivityTimer()
                    .timeout(const Duration(seconds: 3));
                print('🔄 Activity timer reset after successful passcode entry');
              } catch (e) {
                print('❌ Error resetting activity timer: $e (continuing anyway)');
                // Don't block navigation if timer reset fails
              }
              
              // Add small delay to ensure UI is ready
              await Future.delayed(const Duration(milliseconds: 100));
              
              if (!mounted) return;
              
                              try {
                  _navigationTimeout?.cancel(); // Cancel safety timer on success
                  if (widget.onSuccess != null) {
                    print('🔐 Calling onSuccess callback');
                    widget.onSuccess!();
                  } else {
                    print('🔐 Navigating to home');
                    if (mounted) {
                      // ANDROID FIX: Use direct MaterialPageRoute with small delay
                      await Future.delayed(const Duration(milliseconds: 100));
                      
                      if (!mounted) return;
                      
                      await Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                      print('🔐 Navigation to home completed');
                    }
                  }
                } catch (e) {
                  print('❌ Navigation error: $e');
                  if (mounted) {
                    // If navigation fails, try named route as fallback
                    try {
                      print('🔄 Attempting fallback named route...');
                      await Navigator.pushReplacementNamed(context, '/home');
                      print('🔐 Fallback navigation successful');
                    } catch (e2) {
                      print('❌ Fallback navigation also failed: $e2');
                      setState(() {
                        errorMessage = _safeTranslate('navigation_error', 'Navigation error. Please restart the app.');
                        enteredCode = '';
                        isConfirmed = false;
                      });
                    }
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
      // Error handled
      if (mounted) {
        setState(() {
          errorMessage = _safeTranslate('general_error', 'An error occurred. Please try again.');
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

  /// Normalize title to handle different languages
  String _getNormalizedTitle(String title) {
    // 🔧 FIX: بهترین روش - استفاده از translation keys به جای string matching
    
    // اول بررسی کنیم که آیا title یکی از translation keys است
    final choosePasscode = _safeTranslate('choose_passcode', 'Choose Passcode');
    final confirmPasscode = _safeTranslate('confirm_passcode', 'Confirm Passcode');
    final enterPasscode = _safeTranslate('enter_passcode', 'Enter Passcode');
    
    print('🔍 Title normalization - Input: "$title"');
    print('🔍 Translated values: choose="$choosePasscode", confirm="$confirmPasscode", enter="$enterPasscode"');
    
    // بررسی دقیق با هر دو نسخه انگلیسی و ترجمه شده
    if (title == 'Choose Passcode' || title == choosePasscode) {
      print('✅ Detected: choose_passcode');
      return 'choose_passcode';
    } else if (title == 'Confirm Passcode' || title == confirmPasscode) {
      print('✅ Detected: confirm_passcode');
      return 'confirm_passcode';
    } else if (title == 'Enter Passcode' || title == enterPasscode) {
      print('✅ Detected: enter_passcode');
      return 'enter_passcode';
    }
    
    // 🔧 FIX: بهبود keyword detection با کلمات کلیدی بیشتر
    final lowerTitle = title.toLowerCase().trim();
    
    // Choose/Select passcode keywords - بهبود یافته
    if (lowerTitle.contains('choose') ||    // English
        lowerTitle.contains('select') ||    // English alternative
        lowerTitle.contains('انتخاب') ||    // Persian/Farsi
        lowerTitle.contains('رمز') && lowerTitle.contains('انتخاب') ||  // Persian combination
        lowerTitle.contains('seç') ||       // Turkish
        lowerTitle.contains('选择') ||       // Chinese Simplified
        lowerTitle.contains('選擇') ||       // Chinese Traditional
        lowerTitle.contains('elegir') ||    // Spanish
        lowerTitle.contains('choisir') ||   // French
        lowerTitle.contains('wählen') ||    // German
        lowerTitle.contains('選ぶ') ||       // Japanese
        lowerTitle.contains('선택') ||       // Korean
        lowerTitle.contains('выбрать') ||   // Russian
        lowerTitle.contains('scegli') ||    // Italian
        lowerTitle.contains('escolher') ||  // Portuguese
        lowerTitle.contains('اختر') ||       // Arabic
        lowerTitle.contains('בחר')) {       // Hebrew
      print('✅ Detected by keyword: choose_passcode');
      return 'choose_passcode';
    }
    
    // Confirm passcode keywords - بهبود یافته
    else if (lowerTitle.contains('confirm') ||  // English
        lowerTitle.contains('verify') ||        // English alternative
        lowerTitle.contains('تایید') ||         // Persian/Farsi
        lowerTitle.contains('تأیید') ||         // Persian alternative spelling
        lowerTitle.contains('رمز') && lowerTitle.contains('تایید') ||  // Persian combination
        lowerTitle.contains('onayla') ||        // Turkish
        lowerTitle.contains('确认') ||           // Chinese Simplified
        lowerTitle.contains('確認') ||           // Chinese Traditional
        lowerTitle.contains('confirmar') ||     // Spanish
        lowerTitle.contains('confirmer') ||     // French
        lowerTitle.contains('bestätigen') ||    // German
        lowerTitle.contains('確認') ||           // Japanese
        lowerTitle.contains('확인') ||           // Korean
        lowerTitle.contains('подтвердить') ||   // Russian
        lowerTitle.contains('conferma') ||      // Italian
        lowerTitle.contains('تأكيد') ||          // Arabic
        lowerTitle.contains('אשר')) {           // Hebrew
      print('✅ Detected by keyword: confirm_passcode');
      return 'confirm_passcode';
    }
    
    // Enter passcode keywords - بهبود یافته
    else if (lowerTitle.contains('enter') ||   // English
        lowerTitle.contains('input') ||        // English alternative
        lowerTitle.contains('وارد') ||          // Persian/Farsi
        lowerTitle.contains('ورود') ||          // Persian alternative
        lowerTitle.contains('رمز') && (lowerTitle.contains('وارد') || lowerTitle.contains('ورود')) ||  // Persian combination
        lowerTitle.contains('gir') ||           // Turkish
        lowerTitle.contains('输入') ||           // Chinese Simplified
        lowerTitle.contains('輸入') ||           // Chinese Traditional
        lowerTitle.contains('ingresar') ||      // Spanish
        lowerTitle.contains('entrer') ||        // French
        lowerTitle.contains('eingeben') ||      // German
        lowerTitle.contains('入力') ||           // Japanese
        lowerTitle.contains('입력') ||           // Korean
        lowerTitle.contains('ввести') ||        // Russian
        lowerTitle.contains('inserisci') ||     // Italian
        lowerTitle.contains('inserir') ||       // Portuguese
        lowerTitle.contains('أدخل') ||           // Arabic
        lowerTitle.contains('הכנס')) {          // Hebrew
      print('✅ Detected by keyword: enter_passcode');
      return 'enter_passcode';
    }
    
    // 🔧 FIX: بهبود fallback logic
    print('⚠️ Could not detect title type for: "$title"');
    print('⚠️ Using intelligent fallback...');
    
    // اگر هیچ کلمه کلیدی پیدا نشد، بر اساس context تصمیم بگیریم
    if (widget.firstPasscode != null && widget.firstPasscode!.isNotEmpty) {
      // اگر firstPasscode وجود دارد، احتمالاً confirm است
      print('🔄 Fallback: confirm_passcode (firstPasscode exists)');
      return 'confirm_passcode';
    } else {
      // 🔧 FIX: بررسی اضافی برای تشخیص بهتر
      // اگر title شامل کلمات مرتبط با انتخاب باشد
      if (lowerTitle.contains('انتخاب') || lowerTitle.contains('choose') || lowerTitle.contains('select')) {
        print('🔄 Fallback: choose_passcode (contains selection keywords)');
        return 'choose_passcode';
      }
      // اگر title شامل کلمات مرتبط با تایید باشد
      else if (lowerTitle.contains('تایید') || lowerTitle.contains('تأیید') || lowerTitle.contains('confirm')) {
        print('🔄 Fallback: confirm_passcode (contains confirmation keywords)');
        return 'confirm_passcode';
      }
      // در غیر این صورت، enter passcode
      else {
        print('🔄 Fallback: enter_passcode (default)');
        return 'enter_passcode';
      }
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