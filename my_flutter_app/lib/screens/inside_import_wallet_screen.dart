import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../layout/bottom_menu_with_siri.dart';

class InsideImportWalletScreen extends StatefulWidget {
  const InsideImportWalletScreen({Key? key}) : super(key: key);

  @override
  State<InsideImportWalletScreen> createState() => _InsideImportWalletScreenState();
}

class _InsideImportWalletScreenState extends State<InsideImportWalletScreen> {
  final TextEditingController _secretPhraseController = TextEditingController();
  String errorMessage = '';
  bool isLoading = false;
  bool showErrorModal = false;

  // فرض: نام کیف پول جدید به صورت خودکار تولید می‌شود
  String walletName = 'Import 1';

  @override
  void initState() {
    super.initState();
    // TODO: نام کیف پول را بر اساس SharedPreferences یا Provider تولید کن
  }

  @override
  void dispose() {
    _secretPhraseController.dispose();
    super.dispose();
  }

  bool validateSecretPhrase(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return [12, 18, 24].contains(words.length);
  }

  void _restoreWallet() async {
    final phrase = _secretPhraseController.text.trim();
    if (!validateSecretPhrase(phrase)) {
      setState(() {
        errorMessage = 'Secret phrase must contain 12, 18, or 24 words.';
        showErrorModal = true;
      });
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    // TODO: عملیات ایمپورت کیف پول (API یا Provider)
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      isLoading = false;
    });
    // فرض: موفقیت
    if (mounted) Navigator.pop(context, {'walletName': walletName});
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _secretPhraseController.text = data.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isValid = validateSecretPhrase(_secretPhraseController.text);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Multi-coin wallet', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Secret phrase label
              const Text('Secret phrase', style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  TextField(
                    controller: _secretPhraseController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Enter your secret phrase',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF16B369)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                  TextButton(
                    onPressed: _pasteFromClipboard,
                    child: const Text('Paste', style: TextStyle(color: Color(0xFF16B369), fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isValid && !isLoading ? _restoreWallet : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isValid ? const Color(0xFF16B369) : Colors.grey[300],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Restore wallet', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: const Text('What is a secret phrase?', style: TextStyle(fontSize: 14, color: Color(0xFF16B369))),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
} 