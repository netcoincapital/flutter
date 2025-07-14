import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class SecurityScreen extends StatefulWidget {
  final String initialAutoLockOption;
  const SecurityScreen({Key? key, this.initialAutoLockOption = 'Immediate'}) : super(key: key);

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool passcodeEnabled = true;
  String selectedAutoLockOption = '';

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
    selectedAutoLockOption = widget.initialAutoLockOption;
  }

  Map<String, int> get _autoLockOptions => {
    _safeTranslate('immediate', 'Immediate'): 0,
    _safeTranslate('one_min', '1 min'): 1,
    _safeTranslate('five_min', '5 min'): 5,
    _safeTranslate('ten_min', '10 min'): 10,
    _safeTranslate('fifteen_min', '15 min'): 15,
  };

  void _showAutoLockDialog() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6F3),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(_safeTranslate('select_auto_lock_time', 'Select Auto-lock Time'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ..._autoLockOptions.keys.map((label) => InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(context, label),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
                  child: Text(label, style: const TextStyle(fontSize: 16)),
                ),
              )),
            ],
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        selectedAutoLockOption = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _SettingItemWithSwitch(
              title: _safeTranslate('passcode', 'Passcode'),
              subtitle: '',
              value: passcodeEnabled,
              onChanged: (val) => setState(() => passcodeEnabled = val),
            ),
            _SettingItem(
              title: _safeTranslate('auto_lock', 'Auto-lock'),
              subtitle: selectedAutoLockOption,
              onTap: _showAutoLockDialog,
            ),
            _SettingItem(
              title: _safeTranslate('lock_method', 'Lock method'),
              subtitle: _safeTranslate('passcode_biometric', 'Passcode / Biometric'),
              onTap: () {},
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: _safeTranslate('home', 'Home')),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: _safeTranslate('settings', 'Settings')),
        ],
        currentIndex: 1,
        onTap: (idx) {
          // ناوبری ساده برای نمونه
          if (idx == 0) Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    );
  }
}

class _SettingItemWithSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingItemWithSwitch({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingItem({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
} 