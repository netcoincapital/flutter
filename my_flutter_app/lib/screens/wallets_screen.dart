import 'package:flutter/material.dart';
import '../layout/main_layout.dart';
import 'wallet_screen.dart';
import 'inside_import_wallet_screen.dart';
import 'inside_new_wallet_screen.dart';

class Wallet {
  final String walletName;
  final String userId;
  final bool isBackedUp;

  Wallet({
    required this.walletName,
    required this.userId,
    this.isBackedUp = false,
  });
}

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({Key? key}) : super(key: key);

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  List<Wallet> wallets = [];
  String selectedWalletName = '';

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  void _loadWallets() {
    // TODO: Load wallets from SharedPreferences
    setState(() {
      wallets = [
        Wallet(walletName: 'My Wallet', userId: 'user1'),
        Wallet(walletName: 'Test Wallet', userId: 'user2'),
        Wallet(walletName: 'Demo Wallet', userId: 'user3'),
      ];
      if (wallets.isNotEmpty) {
        selectedWalletName = wallets.first.walletName;
      }
    });
  }

  void _saveSelectedWallet(String walletName, String userId) {
    // TODO: Save selected wallet to SharedPreferences
    setState(() {
      selectedWalletName = walletName;
    });
  }

  void _showAddWalletModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddWalletModalContent(
        onCreateNewWallet: _onCreateNewWallet,
        onAddExistingWallet: _onAddExistingWallet,
      ),
    );
  }

  void _onCreateNewWallet() {
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InsideNewWalletScreen()),
    );
  }

  void _onAddExistingWallet() {
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InsideImportWalletScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Header
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const Center(
                      child: Text(
                        'Wallets',
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
                      child: GestureDetector(
                        onTap: _showAddWalletModal,
                        child: Image.asset(
                          'assets/images/plus.png',
                          width: 16,
                          height: 16,
                          color: Color(0x99757575),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Wallets List
                Expanded(
                  child: ListView.builder(
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      final isDefault = wallet.walletName == selectedWalletName;
                      return _WalletItem(
                        wallet: wallet,
                        isDefault: isDefault,
                        onWalletClick: () {
                          _saveSelectedWallet(wallet.walletName, wallet.userId);
                          Navigator.pushReplacementNamed(context, '/home');
                        },
                        onMoreOptionsClick: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WalletScreen(walletName: wallet.walletName),
                            ),
                          );
                        },
                        onBackupClick: () {
                          // TODO: Navigate to backup page
                        },
                      );
                    },
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

class _WalletItem extends StatelessWidget {
  final Wallet wallet;
  final bool isDefault;
  final VoidCallback onWalletClick;
  final VoidCallback onMoreOptionsClick;
  final VoidCallback onBackupClick;

  const _WalletItem({
    required this.wallet,
    required this.isDefault,
    required this.onWalletClick,
    required this.onMoreOptionsClick,
    required this.onBackupClick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onWalletClick,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/wallet.png',
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        wallet.walletName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    if (isDefault)
                      Image.asset(
                        'assets/images/badge.png',
                        width: 28,
                        height: 28,
                        color: const Color(0xFF17D27C),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onMoreOptionsClick,
                      child: Image.asset(
                        'assets/images/more.png',
                        width: 24,
                        height: 24,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onBackupClick,
                  child: const Text(
                    'Back up now',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF007AFF),
                      fontWeight: FontWeight.bold,
                    ),
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

class _AddWalletModalContent extends StatelessWidget {
  final VoidCallback onCreateNewWallet;
  final VoidCallback onAddExistingWallet;

  const _AddWalletModalContent({
    required this.onCreateNewWallet,
    required this.onAddExistingWallet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/cryptowallet.png',
            width: 140,
            height: 140,
          ),
          const SizedBox(height: 16),
          _WalletOptionTile(
            icon: Icons.auto_awesome,
            title: 'Create new wallet',
            subtitle: 'Secret phrase or FaceID / fingerprint',
            onTap: onCreateNewWallet,
          ),
          const SizedBox(height: 12),
          _WalletOptionTile(
            icon: Icons.add_circle_outline,
            title: 'Add existing wallet',
            subtitle: 'Secret phrase, Google Drive or view-only',
            onTap: onAddExistingWallet,
          ),
        ],
      ),
    );
  }
}

class _WalletOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WalletOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6FFFA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF4C70D0), size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFFB2B2B2))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
} 