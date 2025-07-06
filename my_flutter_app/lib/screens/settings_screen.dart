import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String walletName = 'No Wallet Selected'; // مقدار اولیه، بعداً از SharedPreferences یا Provider بخوانید
  bool showQRDialog = false;
  String qrContent = '';

  // شبیه‌سازی بارگذاری نام کیف پول انتخاب‌شده
  @override
  void initState() {
    super.initState();
    // TODO: مقدار walletName را از منبع داده واقعی بخوانید
    walletName = 'My Wallet';
  }

  void _showQRDialog(String content) {
    setState(() {
      qrContent = content;
      showQRDialog = true;
    });
  }

  void _hideQRDialog() {
    setState(() {
      showQRDialog = false;
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              const SizedBox(height: 8),
              _Section(
                title: 'General Settings',
                children: [
                  _SettingItem(
                    icon: 'assets/images/wallet.png',
                    title: 'Wallets',
                    subtitle: walletName,
                    onTap: () {
                      Navigator.pushNamed(context, '/wallets');
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Utilities',
                children: [
                  _SettingItem(
                    icon: 'assets/images/alert.png',
                    title: 'Price Alerts',
                    onTap: () {},
                  ),
                  _SettingItem(
                    icon: 'assets/images/address_book.png',
                    title: 'Address Book',
                    onTap: () {
                      Navigator.pushNamed(context, '/address-book');
                    },
                  ),
                  _SettingItem(
                    icon: 'assets/images/scan.png',
                    title: 'Scan QR Code',
                    onTap: () async {
                      final result = await Navigator.pushNamed(context, '/qr-scanner');
                      if (result != null && result is String && result.isNotEmpty) {
                        _showQRDialog(result);
                      }
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Security',
                children: [
                  _SettingItem(
                    icon: 'assets/images/setting.png',
                    title: 'Preferences',
                    onTap: () {
                      Navigator.pushNamed(context, '/preferences');
                    },
                  ),
                  _SettingItem(
                    icon: 'assets/images/shield.png',
                    title: 'Security',
                    onTap: () {
                      Navigator.pushNamed(context, '/security-passcode');
                    },
                  ),
                  _SettingItem(
                    icon: 'assets/images/bell.png',
                    title: 'Notifications',
                    onTap: () {
                      Navigator.pushNamed(context, '/notificationmanagement');
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Support',
                children: [
                  _SettingItem(
                    icon: 'assets/images/question.png',
                    title: 'Help Center',
                    onTap: () {},
                  ),
                  _SettingItem(
                    icon: 'assets/images/support.png',
                    title: 'Support',
                    onTap: () {},
                  ),
                  _SettingItem(
                    icon: 'assets/images/logo.png',
                    title: 'About',
                    onTap: () {},
                  ),
                ],
              ),
              _Section(
                title: 'Social media',
                children: [
                  _SettingItem(
                    icon: 'assets/images/x.png',
                    title: 'X platform',
                    onTap: () {
                      // باز کردن لینک X (توییتر)
                      // TODO: استفاده از url_launcher
                    },
                  ),
                  _SettingItem(
                    icon: 'assets/images/instagram.png',
                    title: 'Instagram',
                    onTap: () {
                      // باز کردن لینک اینستاگرام
                    },
                  ),
                  _SettingItem(
                    icon: 'assets/images/telegram.png',
                    title: 'Telegram',
                    onTap: () {
                      // باز کردن لینک تلگرام
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
          if (showQRDialog)
            _QRDialog(
              content: qrContent,
              onCopy: () => _copyToClipboard(qrContent),
              onDismiss: _hideQRDialog,
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
        ...children,
        const Divider(color: Color(0x32626262), thickness: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingItem({required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(icon, width: 20, height: 20, color: Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, color: Color(0xFF494949), fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Image.asset('assets/images/rightarrow.png', width: 16, height: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _QRDialog extends StatelessWidget {
  final String content;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;
  const _QRDialog({required this.content, required this.onCopy, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scanned Content',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 16),
                Text(
                  content,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: onCopy,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF16B369),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                          side: const BorderSide(color: Color(0xFF16B369)),
                        ),
                      ),
                      child: const Text('Copy'),
                    ),
                    ElevatedButton(
                      onPressed: onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFDC0303),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                          side: const BorderSide(color: Color(0xFFDC0303)),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 