import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/app_provider.dart';
import '../services/service_provider.dart';
import '../layout/main_layout.dart';
import '../services/device_registration_manager.dart';
import '../services/network_monitor.dart';
import 'address_book_screen.dart';
import 'wallets_screen.dart';

import 'package:my_flutter_app/screens/security_screen.dart';
import 'package:my_flutter_app/screens/passcode_screen.dart';
import '../services/notification_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import '../services/passcode_manager.dart';
import 'passcode_screen.dart';
import 'security_screen.dart';
import '../services/security_settings_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String walletName = 'No Wallet Selected'; // مقدار اولیه، بعداً از SharedPreferences یا Provider بخوانید
  bool showQRDialog = false;
  String qrContent = '';

  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

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
      SnackBar(content: Text(_safeTranslate('copied_to_clipboard', 'Copied to clipboard'))),
    );
  }

  /// نمایش دیالوگ مدیریت دستگاه
  void _showDeviceManagementDialog() {
    // Remove dialog - device management removed
  }

  /// نمایش دستگاه‌های ثبت شده
  void _showRegisteredDevices() {
    // Remove dialog - registered devices removed
  }

  /// ثبت مجدد دستگاه
  void _reRegisterDevice() {
    // Remove dialog - re-register device removed
  }

  /// حذف ثبت دستگاه
  void _unregisterDevice() {
    // Remove dialog - unregister device removed
  }

  /// حذف دستگاه خاص
  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    try {
      // TODO: پیاده‌سازی حذف دستگاه خاص
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('device_deleted_successfully', 'Device deleted successfully'))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('error_deleting_device', 'Error deleting device: {error}').replaceAll('{error}', e.toString()))),
      );
    }
  }

  /// دریافت User ID (در حالت واقعی از SecureStorage)
  Future<String?> _getUserId() async {
    // TODO: دریافت از SecureStorage یا Provider
    return 'user_123'; // مقدار نمونه
  }

  /// دریافت Wallet ID (در حالت واقعی از SecureStorage)
  Future<String?> _getWalletId() async {
    // TODO: دریافت از SecureStorage یا Provider
    return 'wallet_456'; // مقدار نمونه
  }

  /// باز کردن لینک تلگرام
  Future<void> _openTelegramLink() async {
    const telegramUrl = 'https://t.me/Laxce_L2';
    
    print('🔗 Trying to open Telegram link...');
    
    // Try direct URL launch first
    try {
      print('🌐 Trying direct URL launcher...');
      final success = await launchUrl(
        Uri.parse(telegramUrl),
        mode: LaunchMode.externalApplication,
      );
      
      if (success) {
        print('✅ URL launcher succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_telegram', 'Opening Telegram...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
      print('❌ URL launcher returned false');
    } catch (urlError) {
      print('❌ URL launcher failed: $urlError');
    }
    
    // Try external app launcher
    try {
      print('📱 Trying External App Launcher...');
      await LaunchApp.openApp(
        androidPackageName: 'org.telegram.messenger',
        iosUrlScheme: 'tg://resolve?domain=Laxce_L2',
        appStoreLink: telegramUrl,
        openStore: false,
      );
      
      print('✅ External launcher succeeded!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_safeTranslate('opening_telegram', 'Opening Telegram...')), duration: const Duration(seconds: 1)),
        );
      }
      return;
    } catch (externalError) {
      print('📱 External launcher failed: $externalError');
    }
    
    // Try with different launch modes
    try {
      print('🔄 Trying with platformDefault mode...');
      final success = await launchUrl(
        Uri.parse(telegramUrl),
        mode: LaunchMode.platformDefault,
      );
      
      if (success) {
        print('✅ Platform default succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_telegram', 'Opening Telegram...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
    } catch (e) {
      print('❌ Platform default failed: $e');
    }
    
    // Final fallback - copy link to clipboard
    print('📋 Copying to clipboard as final fallback...');
    await Clipboard.setData(ClipboardData(text: telegramUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_safeTranslate('link_copied_to_clipboard', 'Link copied to clipboard. Please open manually.')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// باز کردن لینک X (توییتر)
  Future<void> _openXLink() async {
    const xUrl = 'https://x.com/laxcecrypto';
    
    print('🔗 Trying to open X link...');
    
    // Try direct URL launch first
    try {
      print('🌐 Trying direct URL launcher...');
      final success = await launchUrl(
        Uri.parse(xUrl),
        mode: LaunchMode.externalApplication,
      );
      
      if (success) {
        print('✅ URL launcher succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_x', 'Opening X...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
      print('❌ URL launcher returned false');
    } catch (urlError) {
      print('❌ URL launcher failed: $urlError');
    }
    
    // Try external app launcher
    try {
      print('📱 Trying External App Launcher...');
      await LaunchApp.openApp(
        androidPackageName: 'com.twitter.android',
        iosUrlScheme: 'twitter://user?screen_name=laxcecrypto',
        appStoreLink: xUrl,
        openStore: false,
      );
      
      print('✅ External launcher succeeded!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_safeTranslate('opening_x', 'Opening X...')), duration: const Duration(seconds: 1)),
        );
      }
      return;
    } catch (externalError) {
      print('📱 External launcher failed: $externalError');
    }
    
    // Try with different launch modes
    try {
      print('🔄 Trying with platformDefault mode...');
      final success = await launchUrl(
        Uri.parse(xUrl),
        mode: LaunchMode.platformDefault,
      );
      
      if (success) {
        print('✅ Platform default succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_x', 'Opening X...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
    } catch (e) {
      print('❌ Platform default failed: $e');
    }
    
    // Final fallback - copy link to clipboard
    print('📋 Copying to clipboard as final fallback...');
    await Clipboard.setData(ClipboardData(text: xUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_safeTranslate('link_copied_to_clipboard', 'Link copied to clipboard. Please open manually.')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// باز کردن لینک اینستاگرام
  Future<void> _openInstagramLink() async {
    const instagramUrl = 'https://www.instagram.com/laxcecrypto/';
    
    print('🔗 Trying to open Instagram link...');
    
    // Try direct URL launch first
    try {
      print('🌐 Trying direct URL launcher...');
      final success = await launchUrl(
        Uri.parse(instagramUrl),
        mode: LaunchMode.externalApplication,
      );
      
      if (success) {
        print('✅ URL launcher succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_instagram', 'Opening Instagram...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
      print('❌ URL launcher returned false');
    } catch (urlError) {
      print('❌ URL launcher failed: $urlError');
    }
    
    // Try external app launcher
    try {
      print('📱 Trying External App Launcher...');
      await LaunchApp.openApp(
        androidPackageName: 'com.instagram.android',
        iosUrlScheme: 'instagram://user?username=laxcecrypto',
        appStoreLink: instagramUrl,
        openStore: false,
      );
      
      print('✅ External launcher succeeded!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_safeTranslate('opening_instagram', 'Opening Instagram...')), duration: const Duration(seconds: 1)),
        );
      }
      return;
    } catch (externalError) {
      print('📱 External launcher failed: $externalError');
    }
    
    // Try with different launch modes
    try {
      print('🔄 Trying with platformDefault mode...');
      final success = await launchUrl(
        Uri.parse(instagramUrl),
        mode: LaunchMode.platformDefault,
      );
      
      if (success) {
        print('✅ Platform default succeeded!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_safeTranslate('opening_instagram', 'Opening Instagram...')), duration: const Duration(seconds: 1)),
          );
        }
        return;
      }
    } catch (e) {
      print('❌ Platform default failed: $e');
    }
    
    // Final fallback - copy link to clipboard
    print('📋 Copying to clipboard as final fallback...');
    await Clipboard.setData(ClipboardData(text: instagramUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_safeTranslate('link_copied_to_clipboard', 'Link copied to clipboard. Please open manually.')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }



  /// باز کردن URL Social Media در مرورگر خارجی
  Future<void> _openSocialMediaUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('✅ Settings: Successfully opened social media URL: $url');
      } else {
        print('❌ Settings: Cannot launch URL: $url');
      }
    } catch (e) {
      print('❌ Settings: Error opening social media URL: $e');
    }
  }

  /// نمایش دیالوگ وضعیت شبکه
  void _showNetworkStatusDialog() {
    // Remove dialog - network status dialog removed
  }

  /// نمایش دیالوگ مدیریت نوتیفیکیشن
  void _showNotificationManagementDialog() {
    // Remove dialog - notification management dialog removed
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(_safeTranslate('settings', 'Settings'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: Stack(
          children: [
            ListView(
              children: [
                const SizedBox(height: 8),
                _Section(
                  title: _safeTranslate('general_settings', 'General Settings'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/wallet.png',
                      title: _safeTranslate('wallets', 'Wallets'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WalletsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                _Section(
                  title: _safeTranslate('utilities', 'Utilities'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/alert.png',
                      title: _safeTranslate('price_alerts', 'Price Alerts'),
                      onTap: () {},
                    ),
                    _SettingItem(
                      icon: 'assets/images/address_book.png',
                      title: _safeTranslate('address_book', 'Address Book'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddressBookScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingItem(
                      icon: 'assets/images/scan.png',
                      title: _safeTranslate('scan_qr_code', 'Scan QR Code'),
                      onTap: () async {
                        final result = await Navigator.pushNamed(
                          context, 
                          '/qr-scanner',
                          arguments: {'returnScreen': 'settings'},
                        );
                        if (result != null && result is String && result.isNotEmpty) {
                          _showQRDialog(result);
                        }
                      },
                    ),
                  ],
                ),
                _Section(
                  title: _safeTranslate('security', 'Security'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/setting.png',
                      title: _safeTranslate('preferences', 'Preferences'),
                      onTap: () {
                        Navigator.pushNamed(context, '/preferences');
                      },
                    ),
                    _SettingItem(
                      icon: 'assets/images/shield.png',
                      title: _safeTranslate('security', 'Security'),
                      onTap: () async {
                        // بررسی فعال بودن passcode
                        final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
                        
                        if (isPasscodeEnabled) {
                          // اگر passcode فعال است، بررسی وجود passcode
                          final hasPasscode = await PasscodeManager.isPasscodeSet();
                          
                          if (hasPasscode) {
                            // نمایش passcode screen برای احراز هویت
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PasscodeScreen(
                                  title: _safeTranslate('enter_passcode', 'Enter Passcode'),
                                  onSuccess: () {
                                    // بعد از احراز هویت موفق، برو به security screen
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SecurityScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          } else {
                            // اگر passcode تنظیم نشده، مستقیم به security screen برو
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SecurityScreen(),
                              ),
                            );
                          }
                        } else {
                          // اگر passcode غیرفعال است، مستقیم به security screen برو
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SecurityScreen(),
                            ),
                          );
                        }
                      },
                    ),
                    _SettingItem(
                      icon: 'assets/images/bell.png',
                      title: _safeTranslate('notifications', 'Notifications'),
                      onTap: () {
                        _showNotificationManagementDialog();
                      },
                    ),
                  ],
                ),
                _Section(
                  title: _safeTranslate('support', 'Support'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/question.png',
                      title: _safeTranslate('help_center', 'Help Center'),
                      onTap: () {},
                    ),
                    _SettingItem(
                      icon: 'assets/images/support.png',
                      title: _safeTranslate('support', 'Support'),
                      onTap: () {},
                    ),
                    _SettingItem(
                      icon: 'assets/images/logo.png',
                      title: _safeTranslate('about', 'About'),
                      onTap: () {},
                    ),
                  ],
                ),

                _Section(
                  title: _safeTranslate('social_media', 'Social media'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/x.png',
                      title: _safeTranslate('x_platform', 'X platform'),
                      onTap: () => _openSocialMediaUrl('https://x.com/laxcecrypto'),
                    ),
                    _SettingItem(
                      icon: 'assets/images/instagram.png',
                      title: _safeTranslate('instagram', 'Instagram'),
                      onTap: () => _openSocialMediaUrl('https://www.instagram.com/laxcecrypto/'),
                    ),
                    _SettingItem(
                      icon: 'assets/images/telegram.png',
                      title: _safeTranslate('telegram', 'Telegram'),
                      onTap: () => _openSocialMediaUrl('https://t.me/Laxce_L2'),
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
                safeTranslate: _safeTranslate,
              ),
          ],
        ),
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
            _getIconForTitle(title),
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
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _getIconForTitle(String title) {
    IconData iconData;
    switch (title.toLowerCase()) {
      case 'wallets':
      case 'کیف پول‌ها':
      case 'المحافظ':
      case 'cüzdanlar':
      case 'carteras':
      case '钱包':
        iconData = Icons.account_balance_wallet_rounded;
        break;
      case 'price alerts':
      case 'هشدارهای قیمت':
      case 'تنبيهات الأسعار':
      case 'fiyat uyarıları':
      case 'alertas de precio':
      case '价格提醒':
        iconData = Icons.notifications_active_rounded;
        break;
      case 'address book':
      case 'دفترچه آدرس':
      case 'دفتر العناوين':
      case 'adres defteri':
      case 'libreta de direcciones':
      case '地址簿':
        iconData = Icons.contacts_rounded;
        break;
      case 'scan qr code':
      case 'اسکن کد qr':
      case 'مسح رمز qr':
      case 'qr kod tara':
      case 'escanear código qr':
      case '扫描二维码':
        iconData = Icons.qr_code_scanner_rounded;
        break;
      case 'preferences':
      case 'تنظیمات برگزیده':
      case 'التفضيلات':
      case 'tercihler':
      case 'preferencias':
      case '偏好设置':
        iconData = Icons.tune_rounded;
        break;
      case 'security':
      case 'امنیت':
      case 'الأمان':
      case 'güvenlik':
      case 'seguridad':
      case '安全':
        iconData = Icons.security_rounded;
        break;
      case 'notifications':
      case 'اعلان‌ها':
      case 'الإشعارات':
      case 'bildirimler':
      case 'notificaciones':
      case '通知':
        iconData = Icons.notifications_rounded;
        break;
      case 'help center':
      case 'مرکز راهنمایی':
      case 'مركز المساعدة':
      case 'yardım merkezi':
      case 'centro de ayuda':
      case '帮助中心':
        iconData = Icons.help_center_rounded;
        break;
      case 'support':
      case 'پشتیبانی':
      case 'الدعم':
      case 'destek':
      case 'soporte':
      case '支持':
        iconData = Icons.support_agent_rounded;
        break;
      case 'about':
      case 'درباره':
      case 'حول':
      case 'hakkında':
      case 'acerca de':
      case '关于':
        iconData = Icons.info_rounded;
        break;
      case 'factory reset':
      case 'بازگردانی به حالت کارخانه':
      case 'إعادة تعيين المصنع':
      case 'fabrika ayarları':
      case 'restaurar valores de fábrica':
        iconData = Icons.restore_rounded;
        break;
      case 'x platform':
      case 'پلتفرم x':
      case 'منصة x':
      case 'x platformu':
      case 'plataforma x':
      case 'x平台':
        iconData = Icons.alternate_email_rounded; // X icon
        break;
      case 'instagram':
      case 'اینستاگرام':
      case 'إنستغرام':
      case 'instagram':
      case 'instagram':
        iconData = Icons.camera_alt_rounded; // Instagram icon
        break;
      case 'telegram':
      case 'تلگرام':
      case 'تيليغرام':
      case 'telegram':
      case 'telegram':
        iconData = Icons.telegram_rounded; // Telegram icon
        break;
      default:
        iconData = Icons.settings_rounded;
    }
    
    return Icon(
      iconData,
      size: 20,
      color: Colors.grey,
    );
  }
}

class _QRDialog extends StatelessWidget {
  final String content;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;
  final String Function(String, String) safeTranslate;
  
  const _QRDialog({
    required this.content, 
    required this.onCopy, 
    required this.onDismiss,
    required this.safeTranslate,
  });

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
                Text(
                  safeTranslate('scanned_content', 'Scanned Content'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
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
                      child: Text(safeTranslate('copy', 'Copy')),
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
                      child: Text(safeTranslate('cancel', 'Cancel')),
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

/// Widget برای نمایش آیتم وضعیت شبکه
class _NetworkStatusItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isOnline;

  const _NetworkStatusItem({
    required this.label,
    required this.value,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isOnline ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }
}