import 'package:flutter/material.dart';

class CreateNewWalletScreen extends StatefulWidget {
  const CreateNewWalletScreen({Key? key}) : super(key: key);

  @override
  State<CreateNewWalletScreen> createState() => _CreateNewWalletScreenState();
}

class _CreateNewWalletScreenState extends State<CreateNewWalletScreen> {
  String? errorMessage;
  String walletName = '';
  bool showErrorModal = false;

  @override
  void initState() {
    super.initState();
    // Placeholder: Suggest wallet name (simulate async)
    Future.delayed(Duration.zero, () {
      setState(() {
        walletName = 'Wallet 1'; // TODO: Implement findNextAvailableWalletName
      });
    });
  }

  Future<void> _generateWallet() async {
    // Placeholder: Simulate wallet generation
    setState(() {
      errorMessage = null;
    });
    await Future.delayed(const Duration(seconds: 2));
    // Simulate error
    setState(() {
      errorMessage =
          'Device registration failed due to server security restrictions. This may be caused by Cloudflare protection blocking mobile app requests. Please contact support or try again later.';
      showErrorModal = true;
    });
    // Navigation to backup screen after generation (simulate success)
    Navigator.pushReplacementNamed(context, '/backup?walletName=$walletName');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0BAB9B),
        elevation: 0,
        title: const Text(
          'Generate new wallet',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WalletOptionItemNew(
              title: 'Secret phrase',
              points: 100,
              buttonText: 'Generate',
              onClickCreate: _generateWallet,
              expandedContent: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  DetailRow(
                    label: 'Security',
                    content:
                        'Create and recover wallet with a 12, 18, or 24-word secret phrase. You must manually store this, or back up with Google Drive storage.',
                  ),
                  SizedBox(height: 12),
                  DetailRow(
                    label: 'Transaction',
                    content:
                        'Transactions are available on more networks (chains), but require more steps to complete.',
                    showIcons: true,
                  ),
                  SizedBox(height: 12),
                  DetailRow(
                    label: 'Fees',
                    content:
                        'Pay network fee (gas) with native tokens only. For example, if your transaction is on the Ethereum network, you can only pay for this fee with ETH.',
                  ),
                ],
              ),
            ),
            if (showErrorModal && errorMessage != null)
              CreateWalletErrorModal(
                show: showErrorModal,
                onDismiss: () => setState(() => showErrorModal = false),
                message: errorMessage!,
              ),
          ],
        ),
      ),
    );
  }
}

class WalletOptionItemNew extends StatefulWidget {
  final String title;
  final int? points;
  final String buttonText;
  final Future<void> Function() onClickCreate;
  final WidgetBuilder? expandedContent;

  const WalletOptionItemNew({
    Key? key,
    required this.title,
    this.points,
    required this.buttonText,
    required this.onClickCreate,
    this.expandedContent,
  }) : super(key: key);

  @override
  State<WalletOptionItemNew> createState() => _WalletOptionItemNewState();
}

class _WalletOptionItemNewState extends State<WalletOptionItemNew> {
  bool isExpanded = false;
  bool isLoading = false;

  void _onClick() async {
    if (isLoading) return;
    setState(() => isLoading = true);
    await widget.onClickCreate();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0x0D16B369),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (widget.points != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            "+${widget.points} points",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ]
                      ],
                    ),
                    GestureDetector(
                      onTap: () => setState(() => isExpanded = !isExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          isExpanded ? 'Hide details ▲' : 'Show details ▼',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF16B369)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                height: 36,
                child: OutlinedButton(
                  onPressed: isLoading ? null : _onClick,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16B369),
                    side: const BorderSide(color: Color(0xFF16B369)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Color(0xFF16B369),
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Generate',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
          if (isExpanded && widget.expandedContent != null) ...[
            const SizedBox(height: 16),
            widget.expandedContent!(context),
          ]
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String content;
  final bool showIcons;
  const DetailRow({Key? key, required this.label, required this.content, this.showIcons = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xA6000000)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            content,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.start,
          ),
        ),
        if (showIcons)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                ...[
                  'btc.png',
                  'ethereum_logo.png',
                  'binance_logo.png',
                  'tron.png',
                ].map((iconName) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Image.asset(
                        'assets/images/$iconName',
                        width: 24,
                        height: 24,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_balance_wallet, size: 24, color: Colors.grey),
                      ),
                    )),
                const Text(
                  '+ more chains',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              ],
            ),
          )
      ],
    );
  }
}

class CreateWalletErrorModal extends StatelessWidget {
  final bool show;
  final VoidCallback onDismiss;
  final String message;
  final String title;
  const CreateWalletErrorModal({
    Key? key,
    required this.show,
    required this.onDismiss,
    required this.message,
    this.title = 'Error',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(
              color: Colors.black.withOpacity(0.6),
            ),
          ),
        ),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
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
                      elevation: 0,
                    ),
                    child: const Text('OK',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
} 