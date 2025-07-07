import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ImportCreateScreen extends StatefulWidget {
  const ImportCreateScreen({super.key});

  @override
  State<ImportCreateScreen> createState() => _ImportCreateScreenState();
}

class _ImportCreateScreenState extends State<ImportCreateScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _logoTapCount = 0;

  void _onLogoTap() {
    setState(() {
      _logoTapCount++;
    });
    if (_logoTapCount == 24) {
      _logoTapCount = 0;
      _showCreatorModal();
    }
  }

  void _showCreatorModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AnimatedGradientModal();
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: -500.0,
      end: 800.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(0.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                GestureDetector(
                  onTap: _onLogoTap,
                  child: Image.asset(
                    'assets/logo-512.png',
                    width: 250,
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                ),
                
                // Animated Gradient Text
                Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: const [
                                Color(0xFF0BAB9B),
                                Color(0xFF04243C),
                                Color(0xFF0BAB9B),
                              ],
                              begin: Alignment(_animation.value / bounds.width, 0),
                              end: Alignment((_animation.value + 500) / bounds.width, 0),
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'LAXCE WALLET',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            // No overflow or maxLines needed
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Description Text
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: const Text(
                    'Import your existing wallet or create a new one to get started',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Import Wallet Button
                Container(
                  width: double.infinity,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF0BAB9B), width: 1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/import-wallet');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0BAB9B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Import Wallet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Create New Wallet Button
                Container(
                  width: double.infinity,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/create-new-wallet');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0BAB9B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Create New Wallet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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

class AnimatedGradientModal extends StatefulWidget {
  @override
  State<AnimatedGradientModal> createState() => _AnimatedGradientModalState();
}

class _AnimatedGradientModalState extends State<AnimatedGradientModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getDecodedContent() {
    // Encrypted content split into multiple parts
    final List<String> encryptedParts = [
      '8J+UjCBTb2Z0d2FyZSBPd25lcnNoaXAgYW5kIERlY2xhcmF0aW9uCkksIE1vaGFtbWFkIE5hemFybmVqYWQsIGhlcmVieSBkZWNsYXJlIGFuZCBhZmZpcm0gdGhhdCBhbGwgc3RhZ2VzIG9mIGRlc2lnbiwgZGV2ZWxvcG1lbnQsIGFuZCBpbXBsZW1lbnRhdGlvbiBvZiB0aGUgc29mdHdhcmUgcHJvamVjdCB0aXRsZWQgTGF4Y2UsIGluY2x1ZGluZyB0aGUgZm9sbG93aW5nIGNvbXBvbmVudHM6Cg==',
      'RnVsbCBkZXNpZ24gYW5kIGltcGxlbWVudGF0aW9uIG9mIHRoZSBhcHBsaWNhdGlvbiAoaW5jbHVkaW5nIERFWCwgd2FsbGV0LCBhbmQgb3RoZXIgcmVsYXRlZCBtb2R1bGVzKQoKVVkgKFVzZXIgSW50ZXJmYWNlKSBhbmQgVVggKFVzZXIgRXhwZXJpZW5jZSkgZGVzaWduIGZvciBib3RoIG1vYmlsZSBhbmQgd2ViIHZlcnNpb25zCgpTZXJ2ZXItc2lkZSBjb25maWd1cmF0aW9uLCBkZXBsb3ltZW50LCBhbmQgaW5mcmFzdHJ1Y3R1cmUgc2V0dXAgKEJhY2stRW5kKQoKU3VibWlzc2lvbiwgdXBsb2FkaW5nLCBhbmQgcHVibGlzaGluZyBvZiB0aGUgYXBwbGljYXRpb24gb24gb2ZmaWNpYWwgcGxhdGZvcm1zIGluY2x1ZGluZyBHb29nbGUgUGxheSBhbmQgQXBwbGUgQXBwIFN0b3JlCg==',
      'aGF2ZSBiZWVuIHNvbGVseSBhbmQgZXhjbHVzaXZlbHkgY2FycmllZCBvdXQgYnkgbXlzZWxmLCB3aXRob3V0IHRoZSBpbnZvbHZlbWVudCBvciBjb250cmlidXRpb24gb2YgYW55IG90aGVyIHBlcnNvbiBvciBlbnRpdHkgaW4gdGhlIHRlY2huaWNhbCBvciBvcGVyYXRpb25hbCBhc3BlY3RzIG9mIHRoZSBtZW50aW9uZWQgcHJvamVjdC4KCkEgZGVjbGFyYXRpb24gaXMgaXNzdWVkIGFzIGV2aWRlbmNlIG9mIG15IGludGVsbGVjdHVhbCBhbmQgbGVnYWwgb3duZXJzaGlwIG92ZXIgdGhlIHNvdXJjZSBjb2RlLCBkZXNpZ25zLCBhbmQgZGV2ZWxvcG1lbnQgcHJvY2Vzc2VzIGFuZCBtYXkgYmUgcHJlc2VudGVkIGJlZm9yZSByZWxldmFudCBsZWdhbCBhdXRob3JpdGllcyBvciBjb3VydHMgYXMgdmFsaWQgcHJvb2YuCg==',
      'RnVsbCBOYW1lOiBNb2hhbW1hZCBOYXphcm5lamFkCklyYW5pYW4gTmF0aW9uYWwgSUQ6IDI2NDAxMjcxMzYKVHVya2lzaCBOYXRpb25hbCBJRDogOTk5MDYyOTc2NTIKRW1haWwgQWRkcmVzc2VzOgoKbmV0Y29pbmNhcGl0YWwuY29tcGFueUBnbWFpbC5jb20KCm1vaGFtbWFkLm5hemFybmV6aGFkQGdtYWlsLmNvbQpEYXRlOiBKdWx5IDYsIDIwMjUKU2lnbmF0dXJlOiBbVG8gYmUgcHJvdmlkZWQgaWYgcHJpbnRlZCBvciByZXF1aXJlZF0='
    ];
    
    // Decode and combine all parts
    String decodedContent = '';
    for (String part in encryptedParts) {
      try {
        decodedContent += utf8.decode(base64.decode(part));
      } catch (e) {
        // Fallback in case of decoding error
        decodedContent += 'Error decoding content';
      }
    }
    
    return decodedContent;
  }

  List<Color> _getDecodedColors() {
    final List<String> encryptedColors = [
      'AP8Lq5s=', // 0xFF0BAB9B
      'AP85tvY=', // 0xFF39b6fb
      'AP8Ws2k=', // 0xFF16B369
      'AP8EJDw=', // 0xFF04243C
      'AP8Lq5s=', // 0xFF0BAB9B
      'AP//s0c=', // 0xFFffb347
      'AP//XmI=', // 0xFFff5e62
    ];
    return encryptedColors.map((b64) {
      final bytes = base64.decode(b64);
      final value = bytes.fold(0, (prev, elem) => (prev << 8) + elem);
      return Color(value);
    }).toList();
  }

  String _getDecodedImagePath() {
    // Encrypted image path
    final String encryptedPath = 'YXNzZXRzL2ltYWdlcy8yMDI1LTA3LTA3XzEyLjQ3LjM4LXJlbW92ZWJnLXByZXZpZXcucG5n';
    try {
      return utf8.decode(base64.decode(encryptedPath));
    } catch (e) {
      return 'assets/images/default.png';
    }
  }

  IconData _getDecodedIconData() {
    // Encrypted icon name
    final String encryptedIcon = 'Y2VsZWJyYXRpb24=';
    try {
      String iconName = utf8.decode(base64.decode(encryptedIcon));
      switch (iconName) {
        case 'celebration':
          return Icons.celebration;
        case 'star':
          return Icons.star;
        case 'favorite':
          return Icons.favorite;
        default:
          return Icons.celebration;
      }
    } catch (e) {
      return Icons.celebration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.9;
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              gradient: LinearGradient(
                colors: _getDecodedColors(),
                begin: Alignment(-1 + 2 * _controller.value, -1),
                end: Alignment(1 - 2 * _controller.value, 1),
                stops: const [0.0, 0.18, 0.35, 0.55, 0.7, 0.85, 1.0],
                tileMode: TileMode.mirror,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: child,
          );
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 32),
                Icon(_getDecodedIconData(), color: Colors.white, size: 48),
                SizedBox(height: 24),
                Text(
                  _getDecodedContent(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,2))],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                Image.asset(
                  _getDecodedImagePath(),
                  width: 220,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 