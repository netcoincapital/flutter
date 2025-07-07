import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhraseKeyScreen extends StatefulWidget {
  final String walletName;
  final bool showCopy;
  final String mnemonic;
  const PhraseKeyScreen({Key? key, required this.walletName, required this.mnemonic, this.showCopy = false}) : super(key: key);

  @override
  State<PhraseKeyScreen> createState() => _PhraseKeyScreenState();
}

class _PhraseKeyScreenState extends State<PhraseKeyScreen> {
  bool copied = false;

  @override
  Widget build(BuildContext context) {
    final mnemonicWords = widget.mnemonic.trim().split(RegExp(r'\s+'));
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Mnemonic for ${widget.walletName}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // نمایش کلمات mnemonic به صورت دو ستونه
                    for (int i = 0; i < mnemonicWords.length; i += 2)
                      Row(
                        children: [
                          Expanded(
                            child: _PhraseCard(number: i + 1, word: mnemonicWords[i]),
                          ),
                          if (i + 1 < mnemonicWords.length)
                            const SizedBox(width: 8),
                          if (i + 1 < mnemonicWords.length)
                            Expanded(
                              child: _PhraseCard(number: i + 2, word: mnemonicWords[i + 1]),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (widget.showCopy)
              Padding(
                padding: const EdgeInsets.only(top: 15.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: widget.mnemonic));
                      setState(() { copied = true; });
                      Future.delayed(const Duration(seconds: 2), () => setState(() => copied = false));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF08C495),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      elevation: 0,
                    ),
                    child: Text(copied ? 'Copied!' : 'Copy Mnemonic', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/images/danger.png', width: 20, height: 20, color: Color(0xFFFFAA00)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Never share your secret phrase with anyone, and store it securely!',
                      style: TextStyle(fontSize: 12, color: Colors.black),
                    ),
                  ),
                  IconButton(
                    icon: Image.asset('assets/images/rightarrow.png', width: 20, height: 20),
                    onPressed: () {
                      // Next page logic
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

class _PhraseCard extends StatelessWidget {
  final int number;
  final String word;
  const _PhraseCard({required this.number, required this.word});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text('$number. $word', style: const TextStyle(fontSize: 12, color: Colors.black)),
      ),
    );
  }
} 