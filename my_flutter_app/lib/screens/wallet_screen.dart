import 'package:flutter/material.dart';
import '../layout/main_layout.dart';

class WalletScreen extends StatefulWidget {
  final String walletName;
  
  const WalletScreen({Key? key, required this.walletName}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late String walletName;
  bool showDeleteDialog = false;

  @override
  void initState() {
    super.initState();
    walletName = widget.walletName;
  }

  void _saveWalletName() {
    // TODO: Save wallet name to SharedPreferences
    // TODO: Update mnemonic for wallet name
    Navigator.pushReplacementNamed(context, '/wallets');
  }

  void _deleteWallet() {
    setState(() {
      showDeleteDialog = false;
    });
    // TODO: Delete wallet from SharedPreferences
    // TODO: Remove mnemonic
    Navigator.pushReplacementNamed(context, '/wallets');
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with Save and Delete buttons
                    const SizedBox(height: 8),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const Center(
                          child: Text(
                            'Wallet',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.black),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    showDeleteDialog = true;
                                  });
                                },
                                icon: Image.asset(
                                  'assets/images/recycle_bin.png',
                                  width: 18,
                                  height: 18,
                                  color: Colors.black,
                                ),
                              ),
                              TextButton(
                                onPressed: _saveWalletName,
                                child: const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF2AC079),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Name Input
                    const Text(
                      'Name',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: walletName),
                      onChanged: (value) {
                        setState(() {
                          walletName = value.trim();
                        });
                      },
                      decoration: InputDecoration(
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
                    const SizedBox(height: 28),
                    // Secret phrase backups section
                    const Text(
                      'Secret phrase backups',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Manual backup option
                    GestureDetector(
                      onTap: () {
                        // TODO: Navigate to phrase key passcode page
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/images/hold.png',
                                  width: 28,
                                  height: 28,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 16),
                                const Text(
                                  'Manual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Warning box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'We highly recommend completing both backup options to help prevent the loss of your crypto.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFFE68A00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Delete confirmation dialog
              if (showDeleteDialog)
                _DeleteDialog(
                  onDelete: _deleteWallet,
                  onCancel: () {
                    setState(() {
                      showDeleteDialog = false;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _DeleteDialog({
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete Wallet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Are you sure you want to delete this wallet? This action cannot be undone.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onCancel,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFFBDBDBD),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextButton(
                        onPressed: onDelete,
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ),
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