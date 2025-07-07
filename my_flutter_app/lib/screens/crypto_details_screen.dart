import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class CryptoDetailsScreen extends StatefulWidget {
  final String tokenName;
  final String tokenSymbol;
  final String iconUrl;
  final bool isToken;
  final String blockchainName;
  final double gasFee;
  // سایر پارامترهای مورد نیاز مانند قیمت، مقدار و ...

  const CryptoDetailsScreen({
    Key? key,
    required this.tokenName,
    required this.tokenSymbol,
    required this.iconUrl,
    required this.isToken,
    required this.blockchainName,
    required this.gasFee,
  }) : super(key: key);

  @override
  State<CryptoDetailsScreen> createState() => _CryptoDetailsScreenState();
}

class _CryptoDetailsScreenState extends State<CryptoDetailsScreen> {
  Color? dominantColor;

  @override
  void initState() {
    super.initState();
    _updatePalette(widget.iconUrl);
  }

  Future<void> _updatePalette(String iconUrl) async {
    try {
      final ImageProvider provider = iconUrl.startsWith('http')
          ? NetworkImage(iconUrl)
          : AssetImage(iconUrl) as ImageProvider;
      final PaletteGenerator paletteGenerator = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(40, 40),
      );
      setState(() {
        dominantColor = paletteGenerator.dominantColor?.color?.withOpacity(0.1) ?? const Color(0x80D7FBE7);
      });
    } catch (_) {
      setState(() {
        dominantColor = const Color(0x80D7FBE7);
      });
    }
  }

  Widget _buildTokenIcon(String iconUrl) {
    if (iconUrl.startsWith('http')) {
      return Image.network(
        iconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.monetization_on, size: 52, color: Colors.grey),
      );
    } else {
      return Image.asset(
        iconUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.monetization_on, size: 52, color: Colors.grey),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.notifications, color: Colors.grey),
                    Column(
                      children: [
                        Text(widget.tokenName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(
                          "${widget.isToken ? 'Token' : 'Coin'}  ||  ${widget.tokenSymbol}",
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                    Icon(Icons.info, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 16),
                // Token Icon with dominant color background
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: dominantColor ?? const Color(0x80D7FBE7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: ClipOval(
                      child: _buildTokenIcon(widget.iconUrl),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // قیمت، مقدار و ... (در اینجا به صورت نمونه)
                Text(
                  '0.00 ${widget.tokenSymbol}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '≈ 0.00 USD',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // دکمه‌های Send و Receive
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ActionButton(
                      assetIcon: 'assets/images/send.png',
                      label: 'Send',
                      color: const Color(0x80D7FBE7),
                      onTap: () {},
                    ),
                    _ActionButton(
                      assetIcon: 'assets/images/receive.png',
                      label: 'Receive',
                      color: const Color(0xFFE0F7FA),
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // لیست تراکنش‌ها (نمونه)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Transaction history will be here...', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String assetIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.assetIcon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Image.asset(
                assetIcon,
                width: 28,
                height: 28,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
} 