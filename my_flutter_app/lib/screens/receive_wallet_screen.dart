import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

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

  void _showAmountModal() async {
    final controller = TextEditingController(text: amount);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text('Enter Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Amount',
                    ),
                    onChanged: (val) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(context, controller.text),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        amount = result;
      });
    }
  }

  Future<void> _shareQrAndAddress() async {
    try {
      if (_qrKey.currentContext == null || !mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code is not ready.')));
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
      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
        subject: 'Public Address',
      );
      // هیچ return یا متغیر result اینجا وجود ندارد
    } catch (e, stack) {
      debugPrint('Share error: \\${e.toString()}');
      debugPrint(stack.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing: \\${e.toString()}')),
      );
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
        title: const Text('Receive', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                      'Only send (${widget.blockchainName}) assets to this address.\nOther assets will be lost forever.',
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
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _qrKey,
                child: Container(
                  color: Colors.white,
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 220,
                    gapless: false,
                    embeddedImage: AssetImage('assets/images/logo.png'),
                    embeddedImageStyle: QrEmbeddedImageStyle(size: const Size(40, 40)),
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
                  label: copied ? 'Copied!' : 'Copy',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.address));
                    setState(() { copied = true; });
                    Future.delayed(const Duration(seconds: 2), () => setState(() => copied = false));
                  },
                ),
                _ActionButton(
                  icon: Icons.edit,
                  label: 'Set Amount',
                  onTap: _showAmountModal,
                ),
                _ActionButton(
                  icon: Icons.share,
                  label: 'Share',
                  onTap: _shareQrAndAddress,
                ),
              ],
            ),
            if (amount.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
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
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
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
            const Text('Enter Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Amount',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => widget.onDone(_controller.text),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 