import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../layout/bottom_menu_with_siri.dart';

class LanguagesScreen extends StatefulWidget {
  const LanguagesScreen({Key? key}) : super(key: key);

  @override
  State<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends State<LanguagesScreen> {
  String selectedLanguage = 'default';

  final List<Map<String, String>> suggestedLanguages = [
    {'code': 'en', 'name': 'English'},
    {'code': 'fa', 'name': 'Persian'},
    {'code': 'tr', 'name': 'Türkçe'},
  ];

  final List<Map<String, String>> allLanguages = [
    {'code': 'en', 'name': 'English'},
    {'code': 'fa', 'name': 'Persian'},
    {'code': 'tr', 'name': 'Türkçe'},
    {'code': 'de', 'name': 'Deutsch'},
    {'code': 'fr', 'name': 'Français'},
    {'code': 'es', 'name': 'Español'},
    {'code': 'cs', 'name': 'Čeština'},
    {'code': 'da', 'name': 'Dansk'},
    {'code': 'br', 'name': 'Brezhoneg'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = prefs.getString('language_code') ?? 'default';
    });
  }

  Future<void> _saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    setState(() {
      selectedLanguage = code;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('App languages', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Center(
                    child: Image.asset('assets/images/logo.png', width: 50, height: 50),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Coinceeper', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Suggested', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: suggestedLanguages.map((lang) => _LanguageRow(
                  name: lang['name']!,
                  isChecked: selectedLanguage == lang['code'],
                  onTap: () => _saveLanguage(lang['code']!),
                )).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('All Languages', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListView.separated(
                  itemCount: allLanguages.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.grey, height: 0.5),
                  itemBuilder: (context, index) {
                    final lang = allLanguages[index];
                    return _LanguageRow(
                      name: lang['name']!,
                      isChecked: selectedLanguage == lang['code'],
                      onTap: () => _saveLanguage(lang['code']!),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  final String name;
  final bool isChecked;
  final VoidCallback onTap;
  const _LanguageRow({required this.name, required this.isChecked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
              child: Text(name, style: const TextStyle(fontSize: 16, color: Colors.black)),
            ),
            if (isChecked)
              const Text('✔', style: TextStyle(fontSize: 16, color: Color(0xFF16B369))),
          ],
        ),
      ),
    );
  }
} 