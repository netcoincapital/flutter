import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'passcode_screen.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final TextEditingController _seedController = TextEditingController();
  bool _isLoading = false;
  bool _showErrorModal = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  void _importWallet() async {
    if (_seedController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2)); // Simulate import
    setState(() {
      _isLoading = false;
      _showErrorModal = true;
      _errorMessage = 'Unable to connect to the server at this time.';
    });
    // Navigation to backup screen after import (simulate success)
    // Replace 'ImportedWallet' with actual wallet name if available
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasscodeScreen(
          title: 'Choose Passcode',
          walletName: 'ImportedWallet',
        ),
      ),
    );
  }

  void _launchTerms() async {
    const url = 'https://coinceeper.com/terms-of-service';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _seedController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Wallet'),
        backgroundColor: const Color(0xFF0BAB9B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // تراز چپ
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // تراز چپ
                    children: [
                      // Title
                      const Text(
                        'Import Wallet',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.left,
                      ),
                      const SizedBox(height: 24),
                      // Seed phrase input with QR button
                      TextField(
                        controller: _seedController,
                        decoration: InputDecoration(
                          labelText: 'Seed phrase or private key',
                          labelStyle: const TextStyle(fontSize: 16),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code),
                            onPressed: () async {
                              final result = await Navigator.pushNamed(context, '/qr-scanner');
                              if (result != null && result is String && result.isNotEmpty) {
                                setState(() {
                                  _seedController.text = result;
                                });
                              }
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                            borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                            borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8), // تغییر به ۸ پیکسل
                            borderSide: const BorderSide(color: Color(0xFF0BAB9B), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        ),
                        style: const TextStyle(fontSize: 16),
                        minLines: 1,
                        maxLines: 1,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isValid ? 'Valid phrase/key detected' : 'Enter your recovery phrase',
                          style: TextStyle(
                            color: isValid ? const Color(0xFF0BAB9B) : Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // حذف متن توافق از اینجا
                    ],
                  ),
                ),
              ),
            ),
            // متن توافق به پایین صفحه منتقل شود
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text(
                    'By continuing, you agree to the ',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  GestureDetector(
                    onTap: _launchTerms,
                    child: const Text(
                      'Terms and Conditions',
                      style: TextStyle(
                        color: Color(0xFF0BAB9B),
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32, top: 8),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isValid && !_isLoading ? _importWallet : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isValid ? const Color(0xFF4C70D0) : const Color(0xFF858585),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Import',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
            if (_showErrorModal)
              _ErrorModal(
                message: _errorMessage,
                onDismiss: () => setState(() => _showErrorModal = false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorModal extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorModal({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.6),
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
                const Icon(Icons.error, color: Color(0xFFFF1961), size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1961),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 