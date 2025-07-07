import 'package:flutter/material.dart';
import '../layout/bottom_menu_with_siri.dart';

class InsideNewWalletScreen extends StatefulWidget {
  const InsideNewWalletScreen({Key? key}) : super(key: key);

  @override
  State<InsideNewWalletScreen> createState() => _InsideNewWalletScreenState();
}

class _InsideNewWalletScreenState extends State<InsideNewWalletScreen> {
  bool isLoading = false;
  String errorMessage = '';
  bool showErrorModal = false;
  String walletName = 'New 1';

  @override
  void initState() {
    super.initState();
    // TODO: نام کیف پول را بر اساس SharedPreferences یا Provider تولید کن
  }

  void _generateWallet() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    // TODO: عملیات ساخت کیف پول (API یا Provider)
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      isLoading = false;
    });
    // فرض: موفقیت
    if (mounted) Navigator.pop(context, {'walletName': walletName});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Generate new wallet', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0x0D16B369),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Secret phrase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                          SizedBox(height: 10),
                          Text('Generate a new secret phrase.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      height: 36,
                      child: OutlinedButton(
                        onPressed: isLoading ? null : _generateWallet,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF16B369)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          backgroundColor: isLoading ? Colors.grey : Colors.transparent,
                          foregroundColor: isLoading ? Colors.grey[200] : const Color(0xFF16B369),
                          padding: EdgeInsets.zero,
                        ),
                        child: isLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16B369)))
                            : const Text('Generate', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16B369))),
                      ),
                    ),
                  ],
                ),
              ),
              if (errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14)),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
} 