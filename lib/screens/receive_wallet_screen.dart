import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import '../providers/price_provider.dart';
import '../utils/shared_preferences_utils.dart';

class ReceiveWalletScreen extends StatefulWidget {
  final String cryptoName;
  final String blockchainName;
  final String address;
  final String symbol;
  const ReceiveWalletScreen({Key? key, required this.cryptoName, required this.blockchainName, required this.address, required this.symbol}) : super(key: key);

  @override
  State<ReceiveWalletScreen> createState() => _ReceiveWalletScreenState();
}

class _ReceiveWalletScreenState extends State<ReceiveWalletScreen> {
  String amount = '';
  bool showAmountDialog = false;
  bool copied = false;
  final GlobalKey _qrKey = GlobalKey();
  String selectedCurrency = 'USD';
  double tokenPrice = 0.0;
  bool isPriceLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedCurrency();
    _fetchTokenPrice();
  }

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  /// بارگذاری ارز انتخابی (مطابق با Kotlin recieve_wallet.kt)
  Future<void> _loadSelectedCurrency() async {
    try {
      selectedCurrency = await SharedPreferencesUtils.getSelectedCurrency();
      setState(() {});
      print('💰 ReceiveWallet Screen - Loaded selected currency: $selectedCurrency');
    } catch (e) {
      print('❌ Error loading selected currency: $e');
      selectedCurrency = 'USD'; // fallback
    }
  }

  /// دریافت قیمت توکن خاص (مطابق با Kotlin recieve_wallet.kt)
  Future<void> _fetchTokenPrice() async {
    setState(() {
      isPriceLoading = true;
    });

    try {
      print('🔄 ReceiveWallet Screen: Fetching price for token: ${widget.symbol} (matching Kotlin recieve_wallet.kt)');
      
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // دریافت قیمت فقط برای این توکن مطابق با Kotlin recieve_wallet.kt
      await priceProvider.fetchPrices([widget.symbol], currencies: [selectedCurrency]);
      
      final price = priceProvider.getPriceForCurrency(widget.symbol, selectedCurrency);
      
      setState(() {
        tokenPrice = price ?? 0.0;
        isPriceLoading = false;
      });
      
      if (price != null && price > 0.0) {
        print('✅ ReceiveWallet Screen: Price for ${widget.symbol}: $price $selectedCurrency');
      } else {
        print('⚠️ ReceiveWallet Screen: No price found for ${widget.symbol}');
      }
    } catch (e) {
      print('❌ ReceiveWallet Screen: Error fetching price: $e');
      setState(() {
        tokenPrice = 0.0;
        isPriceLoading = false;
      });
    }
  }

  void _showAmountModal() async {
    // Remove modal bottom sheet - amount modal removed
  }

  Future<void> _shareQrAndAddress() async {
    try {
      if (_qrKey.currentContext == null || !mounted) {
        // Remove error message - QR not ready silently
        debugPrint('QR context is null or not mounted');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      var image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      Directory tempDir;
      if (Platform.isIOS) {
        tempDir = await getTemporaryDirectory();
      } else {
        tempDir = Directory.systemTemp;
      }
      final file = await File('${tempDir.path}/qr_code.png').create();
      await file.writeAsBytes(pngBytes);
      debugPrint('QR file path: \\${file.path} exists: \\${await file.exists()} size: \\${pngBytes.length}');
      final text = 'Public Address: ${widget.address}';
      // Share functionality removed for now
      print('Share functionality removed');
      // هیچ return یا متغیر result اینجا وجود ندارد
    } catch (e, stack) {
      debugPrint('Share error: \\${e.toString()}');
      debugPrint(stack.toString());
      // Remove error message - sharing failed silently
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrData = amount.isEmpty ? widget.address : "${widget.address}?amount=$amount";
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_safeTranslate('receive', 'Receive'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Image.asset('assets/images/danger.png', width: 28, height: 28, color: const Color(0xFFE68A00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _safeTranslate('only_send_assets_warning', 'Only send ({blockchain}) assets to this address.\nOther assets will be lost forever.').replaceAll('{blockchain}', widget.blockchainName),
                      style: const TextStyle(fontSize: 13, color: Color(0xFFE68A00)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(widget.cryptoName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(widget.blockchainName, style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  color: Colors.white,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40), // گوشه‌های نرم
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 220,
                      gapless: false,
                      embeddedImage: const AssetImage('assets/images/logo.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(40, 40)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              widget.address,
              style: const TextStyle(fontSize: 15, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.copy,
                  label: copied ? _safeTranslate('copied', 'Copied!') : _safeTranslate('copy', 'Copy'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.address));
                    setState(() { copied = true; });
                    Future.delayed(const Duration(seconds: 2), () => setState(() => copied = false));
                  },
                ),
                _ActionButton(
                  icon: Icons.edit,
                  label: _safeTranslate('set_amount', 'Set Amount'),
                  onTap: _showAmountModal,
                ),
                _ActionButton(
                  icon: Icons.share,
                  label: _safeTranslate('share', 'Share'),
                  onTap: _shareQrAndAddress,
                ),
              ],
            ),
            if (amount.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$amount ${widget.cryptoName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => amount = ''),
                          child: const Icon(Icons.cancel, size: 20, color: Colors.grey),
                        ),
                      ],
                    ),
                    // نمایش تقریبی قیمت مقدار وارد شده
                    if (tokenPrice > 0.0)
                      Consumer<PriceProvider>(
                        builder: (context, priceProvider, child) {
                          final amountValue = double.tryParse(amount) ?? 0.0;
                          final totalValue = amountValue * tokenPrice;
                          final currencySymbol = priceProvider.getCurrencySymbolForCurrency(selectedCurrency);
                          
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '~ $currencySymbol${totalValue.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.black),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;
  const _AmountDialog({required this.initial, required this.onDone, required this.onCancel});

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late TextEditingController _controller;

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
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_safeTranslate('enter_amount', 'Enter Amount'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _safeTranslate('amount', 'Amount'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onCancel, child: Text(_safeTranslate('cancel', 'Cancel'))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => widget.onDone(_controller.text),
                  child: Text(_safeTranslate('ok', 'OK')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 