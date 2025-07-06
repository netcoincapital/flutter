import 'package:flutter/material.dart';
import 'dart:async';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';

class BottomMenuWithSiri extends StatelessWidget {
  const BottomMenuWithSiri({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BottomMenu();
  }
}

class SiriButton extends StatelessWidget {
  const SiriButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 30);
        }
        Navigator.pushNamed(context, '/ai');
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Center(
          child: Image.asset('assets/images/siri.png', width: 80, height: 80, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class BottomMenu extends StatelessWidget {
  const BottomMenu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MenuIcon(
            icon: 'assets/images/home.png',
            onTap: () => Navigator.pushNamed(context, '/home'),
          ),
          _MenuIcon(
            icon: 'assets/images/couple.png',
            onTap: () {},
          ),
          _MenuIcon(
            icon: 'assets/images/qrcode.png',
            onTap: () async {
              final result = await Navigator.pushNamed(context, '/qr-scanner');
              if (result != null && result is String && result.isNotEmpty) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Scanned Content'),
                    content: Text(result),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Clipboard.setData(ClipboardData(text: result));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')),
                          );
                        },
                        child: const Text('Copy'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          _MenuIcon(
            icon: 'assets/images/setting.png',
            onTap: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _MenuIcon({required this.icon, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Image.asset(icon, width: 28, height: 28),
    );
  }
} 