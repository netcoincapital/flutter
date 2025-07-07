import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class PasscodeScreen extends StatefulWidget {
  final String title;
  final String? walletName;
  final String? firstPasscode; // برای تایید
  final String? savedPasscode; // برای ورود
  const PasscodeScreen({Key? key, required this.title, this.walletName, this.firstPasscode, this.savedPasscode}) : super(key: key);

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  String enteredCode = '';
  String errorMessage = '';
  bool isConfirmed = false;
  bool isBiometricAvailable = false; // برای نمایش آیکون اثر انگشت
  final LocalAuthentication auth = LocalAuthentication();

  final borderColors = const [
    Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
    Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb)
  ];

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final canCheck = await auth.canCheckBiometrics;
    final available = await auth.isDeviceSupported();
    setState(() {
      isBiometricAvailable = canCheck && available;
    });
  }

  void _onNumberTap(String number) {
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
          errorMessage = 'Biometric authentication is not available on this device';
        });
        return;
      }
      
      final didAuth = await auth.authenticate(
        localizedReason: 'Authenticate to continue',
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
                  title: 'Confirm Passcode',
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
            Navigator.pushReplacementNamed(context, '/home');
            break;
        }
      } else {
        setState(() {
          errorMessage = 'Authentication was cancelled or failed';
        });
      }
    } catch (e) {
      print('Biometric error: $e'); // برای دیباگ
      setState(() {
        errorMessage = 'Biometric authentication error: ${e.toString()}';
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
    if (enteredCode.length == 6 && !isConfirmed) {
      Future.microtask(() {
        switch (widget.title) {
          case 'Choose Passcode':
            // به صفحه تایید برو و پس‌کد را منتقل کن
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PasscodeScreen(
                  title: 'Confirm Passcode',
                  walletName: widget.walletName,
                  firstPasscode: enteredCode,
                ),
              ),
            );
            break;
          case 'Confirm Passcode':
            if (enteredCode == widget.firstPasscode) {
              // موفقیت: ذخیره پس‌کد و رفتن به صفحه بعد
              Navigator.pushReplacementNamed(context, '/backup', arguments: {'walletName': widget.walletName});
            } else {
              setState(() {
                errorMessage = 'The passcode entered is not the same';
                enteredCode = '';
              });
            }
            break;
          case 'Enter Passcode':
            if (enteredCode == widget.savedPasscode) {
              Navigator.pushReplacementNamed(context, '/home');
            } else {
              setState(() {
                errorMessage = 'The passcode entered is not correct';
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
              widget.title,
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
            const Text(
              'Passcode adds an extra layer of security\nwhen using the app',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _NumberPad(
              onNumberTap: _onNumberTap,
              onDelete: _onDelete,
              onBiometric: _onBiometric,
              showBiometric: isBiometricAvailable,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final void Function(String) onNumberTap;
  final VoidCallback onDelete;
  final VoidCallback onBiometric;
  final bool showBiometric;
  const _NumberPad({required this.onNumberTap, required this.onDelete, required this.onBiometric, this.showBiometric = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('1', onNumberTap),
            _NumButton('2', onNumberTap),
            _NumButton('3', onNumberTap),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('4', onNumberTap),
            _NumButton('5', onNumberTap),
            _NumButton('6', onNumberTap),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('7', onNumberTap),
            _NumButton('8', onNumberTap),
            _NumButton('9', onNumberTap),
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
                  )
                : _CircleIconButton(
                    icon: null,
                    onTap: () {}, // دکمه غیر فعال
                  ),
            _NumButton('0', onNumberTap),
            _CircleIconButton(
              icon: Icons.backspace,
              onTap: onDelete,
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
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, size: 28, color: Colors.grey) : null,
        ),
      ),
    );
  }
}

class _NumButton extends StatelessWidget {
  final String number;
  final void Function(String) onTap;
  const _NumButton(this.number, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: () => onTap(number),
        child: Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
      ),
    );
  }
} 