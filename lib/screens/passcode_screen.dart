import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/passcode_manager.dart';
import '../services/wallet_state_manager.dart';

class PasscodeScreen extends StatefulWidget {
  final String title;
  final String? walletName;
  final String? firstPasscode; // برای تایید
  final String? savedPasscode; // برای ورود
  final VoidCallback? onSuccess; // تابعی که بعد از موفقیت اجرا می‌شود
  const PasscodeScreen({Key? key, required this.title, this.walletName, this.firstPasscode, this.savedPasscode, this.onSuccess}) : super(key: key);

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  String enteredCode = '';
  String errorMessage = '';
  bool isConfirmed = false;
  bool isBiometricAvailable = false;
  bool isLocked = false;
  int remainingAttempts = 5;
  int lockoutRemainingTime = 0;
  final LocalAuthentication auth = LocalAuthentication();

  final borderColors = const [
    Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
    Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb)
  ];

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
    _checkBiometric();
    _checkLockStatus();
    _redirectIfPasscodeExists();
  }

  Future<void> _redirectIfPasscodeExists() async {
    // Prevent showing choose/confirm passcode if passcode already exists
    if (widget.title == _safeTranslate('choose_passcode', 'Choose Passcode') || widget.title == _safeTranslate('confirm_passcode', 'Confirm Passcode')) {
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
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        final remaining = await PasscodeManager.getLockoutRemainingTime();
        setState(() {
          lockoutRemainingTime = remaining;
        });
        
        if (remaining > 0) {
          _startLockoutTimer();
        } else {
          await _checkLockStatus();
        }
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _onNumberTap(String number) {
    if (isLocked) return;
    
    if (enteredCode.length < 6) {
      setState(() {
        enteredCode += number;
        HapticFeedback.lightImpact();
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
        // موفقیت: رفتن به صفحه بعد (مثل وارد کردن پس‌کد صحیح)
        switch (widget.title) {
          case 'Choose Passcode':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PasscodeScreen(
                  title: _safeTranslate('confirm_passcode', 'Confirm Passcode'),
                  walletName: widget.walletName,
                  firstPasscode: enteredCode,
                ),
              ),
            );
            break;
          case 'Confirm Passcode':
            Navigator.pushReplacementNamed(context, '/backup', arguments: {'walletName': widget.walletName});
            break;
          case 'Enter Passcode':
            // Use a smoother navigation approach to prevent black screen
            Navigator.pushReplacementNamed(context, '/home');
            break;
        }
      } else {
        setState(() {
          errorMessage = _safeTranslate('authentication_cancelled', 'Authentication was cancelled or failed');
        });
      }
    } catch (e) {
      print('Biometric error: $e'); // برای دیباگ
      setState(() {
        errorMessage = _safeTranslate('biometric_authentication_error', 'Biometric authentication error: {error}').replaceAll('{error}', e.toString());
      });
    }
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

  @override
  Widget build(BuildContext context) {
    // منطق بررسی پس‌کد
    if (enteredCode.length == 6 && !isConfirmed && !isLocked) {
      Future.microtask(() async {
        switch (widget.title) {
          case 'Choose Passcode':
            // به صفحه تایید برو و پس‌کد را منتقل کن
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
            if (enteredCode == widget.firstPasscode) {
              try {
                // ذخیره پس‌کد
                final success = await PasscodeManager.setPasscode(enteredCode);
                if (success) {
                  // موفقیت: رفتن به صفحه بعد
                  if (widget.onSuccess != null) {
                    widget.onSuccess!();
                  } else {
                    // Check if we have wallet data to go to backup, otherwise go to home
                    final hasWallet = await WalletStateManager.instance.hasWallet();
                    if (hasWallet && widget.walletName != null) {
                      Navigator.pushReplacementNamed(context, '/backup', arguments: {'walletName': widget.walletName});
                    } else {
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  }
                } else {
                  setState(() {
                    errorMessage = _safeTranslate('failed_to_set_passcode', 'Failed to set passcode. Please try again.');
                    enteredCode = '';
                  });
                }
              } catch (e) {
                setState(() {
                  errorMessage = _safeTranslate('error_setting_passcode', 'Error setting passcode: {error}').replaceAll('{error}', e.toString());
                  enteredCode = '';
                });
              }
            } else {
              setState(() {
                errorMessage = _safeTranslate('passcode_mismatch', 'The passcode entered is not the same');
                enteredCode = '';
              });
            }
            break;
          case 'Enter Passcode':
            try {
              final isValid = await PasscodeManager.verifyPasscode(enteredCode);
              if (isValid) {
                if (widget.onSuccess != null) {
                  widget.onSuccess!();
                } else {
                  // Use a smoother navigation approach to prevent black screen
                  // Navigate with proper transition and clear stack
                  Navigator.pushReplacementNamed(context, '/home');
                }
              } else {
                await _checkLockStatus();
                final attemptsRemaining = remainingAttempts > 0 
                  ? _safeTranslate('attempts_remaining', '{count} attempts remaining').replaceAll('{count}', remainingAttempts.toString())
                  : _safeTranslate('wallet_locked', 'Wallet is locked');
                setState(() {
                  errorMessage = _safeTranslate('incorrect_passcode', 'Incorrect passcode. {attemptsRemaining}').replaceAll('{attemptsRemaining}', attemptsRemaining);
                  enteredCode = '';
                });
              }
            } catch (e) {
              await _checkLockStatus();
              setState(() {
                errorMessage = e.toString();
                enteredCode = '';
              });
            }
            break;
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
              Text(
                _safeTranslate('passcode_adds_security', 'Passcode adds an extra layer of security\nwhen using the app'),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 40),
            _NumberPad(
              onNumberTap: _onNumberTap,
              onDelete: _onDelete,
              onBiometric: _onBiometric,
              showBiometric: isBiometricAvailable && !isLocked,
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