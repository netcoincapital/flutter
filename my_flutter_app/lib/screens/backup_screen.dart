import 'package:flutter/material.dart';

class BackupScreen extends StatelessWidget {
  final String walletName;
  const BackupScreen({Key? key, required this.walletName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Backup',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/home');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x1A13CE76),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF16B369),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // تصویر اصلی
            Center(
              child: Image.asset(
                'assets/images/backupimage.png',
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.backup, size: 120, color: Color(0xFF16B369)),
              ),
            ),
            const SizedBox(height: 32),
            // متن‌های توضیحی
            const Text(
              'Back up secret phrase',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Protect your assets by backing up your seed phrase now.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // دکمه Backup
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final encodedWalletName = Uri.encodeComponent(walletName);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/phrasekeypasscode?walletName=$encodedWalletName&showCopy=true',
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0x0D1FD092),
                  foregroundColor: const Color(0xFF16B369),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Back up manually',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 