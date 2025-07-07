import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../layout/bottom_menu_with_siri.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({Key? key}) : super(key: key);

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  String currentCurrency = 'USD';
  String currentLanguage = 'System default';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentCurrency = prefs.getString('selected_currency') ?? 'USD';
      // TODO: Load language preference when language screen is implemented
      currentLanguage = 'System default';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Preferences', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _PreferenceItem(
              title: 'Currency',
              subtitle: currentCurrency,
              onTap: () async {
                final result = await Navigator.pushNamed(context, '/fiat-currencies');
                if (result != null) {
                  _loadPreferences(); // Reload preferences after returning
                }
              },
            ),
            _PreferenceItem(
              title: 'App Language',
              subtitle: currentLanguage,
              onTap: () async {
                final result = await Navigator.pushNamed(context, '/languages');
                if (result != null) {
                  _loadPreferences();
                }
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _PreferenceItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _PreferenceItem({required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.black)),
            ),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
} 