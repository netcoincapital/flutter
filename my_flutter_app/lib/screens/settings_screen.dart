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
import '../services/data_clearance_manager.dart';
import 'package:easy_localization/easy_localization.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String walletName = 'No Wallet Selected'; // مقدار اولیه، بعداً از SharedPreferences یا Provider بخوانید
  bool showQRDialog = false;
  String qrContent = '';

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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_safeTranslate('device_management', 'Device Management')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text(_safeTranslate('registered_devices', 'Registered Devices')),
              subtitle: Text(_safeTranslate('view_and_manage_devices', 'View and manage your registered devices')),
              onTap: () {
                Navigator.pop(context);
                _showRegisteredDevices();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(_safeTranslate('re_register_device', 'Re-register Device')),
              subtitle: Text(_safeTranslate('register_device_again', 'Register this device again')),
              onTap: () {
                Navigator.pop(context);
                _reRegisterDevice();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(_safeTranslate('unregister_device', 'Unregister Device')),
              subtitle: Text(_safeTranslate('remove_device_from_server', 'Remove this device from server')),
              onTap: () {
                Navigator.pop(context);
                _unregisterDevice();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_safeTranslate('cancel', 'Cancel')),
          ),
        ],
      ),
    );
  }

  /// نمایش دستگاه‌های ثبت شده
  Future<void> _showRegisteredDevices() async {
    try {
      final devices = await DeviceRegistrationManager.instance.getAllRegisteredDevices();
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_safeTranslate('registered_devices', 'Registered Devices')),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? Text(_safeTranslate('no_devices_registered', 'No devices registered'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        title: Text(device['deviceName'] ?? _safeTranslate('unknown', 'Unknown Device')),
                        subtitle: Text('${_safeTranslate('registered', 'Registered')}: ${device['registeredAt'] ?? _safeTranslate('unknown', 'Unknown')}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteDevice(device),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_safeTranslate('close', 'Close')),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('error_loading_devices', 'Error loading devices: {error}').replaceAll('{error}', e.toString()))),
      );
    }
  }

  /// ثبت مجدد دستگاه
  Future<void> _reRegisterDevice() async {
    try {
      final userId = await _getUserId();
      final walletId = await _getWalletId();
      
      if (userId != null && walletId != null) {
        final success = await DeviceRegistrationManager.instance.registerDevice(
          userId: userId,
          walletId: walletId,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? _safeTranslate('device_reregistered_successfully', 'Device re-registered successfully') 
              : _safeTranslate('failed_to_reregister_device', 'Failed to re-register device')),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('error_reregistering_device', 'Error re-registering device: {error}').replaceAll('{error}', e.toString()))),
      );
    }
  }

  /// حذف ثبت دستگاه
  Future<void> _unregisterDevice() async {
    try {
      final userId = await _getUserId();
      final walletId = await _getWalletId();
      
      if (userId != null && walletId != null) {
        final success = await DeviceRegistrationManager.instance.unregisterDevice(
          userId: userId,
          walletId: walletId,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? _safeTranslate('device_unregistered_successfully', 'Device unregistered successfully') 
              : _safeTranslate('failed_to_unregister_device', 'Failed to unregister device')),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_safeTranslate('error_unregistering_device', 'Error unregistering device: {error}').replaceAll('{error}', e.toString()))),
      );
    }
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

  /// نمایش دیالوگ وضعیت شبکه
  void _showNetworkStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_safeTranslate('network_status', 'Network Status')),
        content: FutureBuilder<Map<String, dynamic>>(
          future: Future.value(ServiceProvider.instance.getNetworkStatus()),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            
            final networkInfo = snapshot.data ?? {};
            final isOnline = networkInfo['isOnline'] ?? false;
            final connectionType = networkInfo['connectionType'] ?? 'unknown';
            final hasRealInternet = networkInfo['hasRealInternet'] ?? false;
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NetworkStatusItem(
                  label: _safeTranslate('connection_status', 'Connection Status'),
                  value: isOnline ? _safeTranslate('connected', 'Connected') : _safeTranslate('disconnected', 'Disconnected'),
                  isOnline: isOnline,
                ),
                const SizedBox(height: 8),
                _NetworkStatusItem(
                  label: _safeTranslate('connection_type', 'Connection Type'),
                  value: connectionType.toUpperCase(),
                  isOnline: true,
                ),
                const SizedBox(height: 8),
                _NetworkStatusItem(
                  label: _safeTranslate('internet_access', 'Internet Access'),
                  value: hasRealInternet ? _safeTranslate('available', 'Available') : _safeTranslate('unavailable', 'Unavailable'),
                  isOnline: hasRealInternet,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_safeTranslate('close', 'Close')),
          ),
        ],
      ),
    );
  }

  /// نمایش دیالوگ مدیریت نوتیفیکیشن
  void _showNotificationManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_safeTranslate('notification_management', 'Notification Management')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: Text(_safeTranslate('request_permission', 'Request Permission')),
              onTap: () async {
                Navigator.pop(context);
                await NotificationHelper.requestNotificationPermission(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_safeTranslate('permission_requested', 'Permission requested!'))),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(_safeTranslate('clear_all_notifications', 'Clear All Notifications')),
              onTap: () async {
                Navigator.pop(context);
                await NotificationHelper.cancelAllNotifications();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_safeTranslate('all_notifications_cleared', 'All notifications cleared!'))),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: Text(_safeTranslate('delete_notification_channels', 'Delete Notification Channels')),
              onTap: () async {
                Navigator.pop(context);
                await NotificationHelper.deleteNotificationChannels();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_safeTranslate('notification_channels_deleted', 'Notification channels deleted!'))),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.celebration),
              title: Text(_safeTranslate('show_welcome_notification', 'Show Welcome Notification')),
              onTap: () async {
                Navigator.pop(context);
                await NotificationHelper.showWelcomeNotification();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_safeTranslate('close', 'Close')),
          ),
        ],
      ),
    );
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
                        // مقدار تستی برای passcode ذخیره‌شده (در حالت واقعی از SharedPreferences بخوان)
                        const savedPasscode = '123456';
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PasscodeScreen(
                              title: _safeTranslate('enter_passcode', 'Enter Passcode'),
                              savedPasscode: savedPasscode,
                              onSuccess: () {
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
                  title: _safeTranslate('data_management', 'Data Management'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/delete.png',
                      title: _safeTranslate('factory_reset', 'Factory Reset'),
                      subtitle: _safeTranslate('clear_all_data_reset_app', 'Clear all data and reset app'),
                      onTap: () {
                        DataClearanceManager.factoryReset(context);
                      },
                    ),
                  ],
                ),
                _Section(
                  title: _safeTranslate('social_media', 'Social media'),
                  children: [
                    _SettingItem(
                      icon: 'assets/images/x.png',
                      title: _safeTranslate('x_platform', 'X platform'),
                      onTap: () {
                        // باز کردن لینک X (توییتر)
                        // TODO: استفاده از url_launcher
                      },
                    ),
                    _SettingItem(
                      icon: 'assets/images/instagram.png',
                      title: _safeTranslate('instagram', 'Instagram'),
                      onTap: () {
                        // باز کردن لینک اینستاگرام
                      },
                    ),
                    _SettingItem(
                      icon: 'assets/images/telegram.png',
                      title: _safeTranslate('telegram', 'Telegram'),
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
        iconData = Icons.account_balance_wallet_rounded;
        break;
      case 'price alerts':
      case 'هشدارهای قیمت':
      case 'تنبيهات الأسعار':
      case 'fiyat uyarıları':
      case 'alertas de precio':
        iconData = Icons.notifications_active_rounded;
        break;
      case 'address book':
      case 'دفترچه آدرس':
      case 'دفتر العناوين':
      case 'adres defteri':
      case 'libreta de direcciones':
        iconData = Icons.contacts_rounded;
        break;
      case 'scan qr code':
      case 'اسکن کد qr':
      case 'مسح رمز qr':
      case 'qr kod tara':
      case 'escanear código qr':
        iconData = Icons.qr_code_scanner_rounded;
        break;
      case 'preferences':
      case 'تنظیمات برگزیده':
      case 'التفضيلات':
      case 'tercihler':
      case 'preferencias':
        iconData = Icons.tune_rounded;
        break;
      case 'security':
      case 'امنیت':
      case 'الأمان':
      case 'güvenlik':
      case 'seguridad':
        iconData = Icons.security_rounded;
        break;
      case 'notifications':
      case 'اعلان‌ها':
      case 'الإشعارات':
      case 'bildirimler':
      case 'notificaciones':
        iconData = Icons.notifications_rounded;
        break;
      case 'help center':
      case 'مرکز راهنمایی':
      case 'مركز المساعدة':
      case 'yardım merkezi':
      case 'centro de ayuda':
        iconData = Icons.help_center_rounded;
        break;
      case 'support':
      case 'پشتیبانی':
      case 'الدعم':
      case 'destek':
      case 'soporte':
        iconData = Icons.support_agent_rounded;
        break;
      case 'about':
      case 'درباره':
      case 'حول':
      case 'hakkında':
      case 'acerca de':
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