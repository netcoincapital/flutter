import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

class BottomMenuWithSiri extends StatelessWidget {
  const BottomMenuWithSiri({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BottomMenu();
  }
}

class SiriButton extends StatefulWidget {
  const SiriButton({Key? key}) : super(key: key);

  @override
  State<SiriButton> createState() => _SiriButtonState();
}

class _SiriButtonState extends State<SiriButton> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (_isNavigating) return;
        
        setState(() {
          _isNavigating = true;
        });
        
        // Vibration functionality removed for now
        print('Vibration functionality removed');
        
        try {
          // Check if we're not already on the AI route
          final currentRoute = ModalRoute.of(context)?.settings.name;
          if (currentRoute != '/ai') {
            await Navigator.pushReplacementNamed(context, '/ai');
          }
        } finally {
          if (mounted) {
            setState(() {
              _isNavigating = false;
            });
          }
        }
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: Center(
          child: Icon(
            Icons.mic_rounded,
            size: 40,
            color: const Color(0xFF11c699),
          ),
        ),
      ),
    );
  }
}

class BottomMenu extends StatefulWidget {
  const BottomMenu({Key? key}) : super(key: key);

  @override
  State<BottomMenu> createState() => _BottomMenuState();
}

class _BottomMenuState extends State<BottomMenu> {
  bool _isNavigating = false;
  Timer? _debounceTimer;

  String _safeTranslate(String key, String fallback) {
    try {
      return key.tr();
    } catch (e) {
      return fallback;
    }
  }

  void _navigateTo(String routeName) async {
    // Prevent multiple navigation calls
    if (_isNavigating) return;
    
    // Get current route name
    final currentRoute = ModalRoute.of(context)?.settings.name;
    
    // Don't navigate if we're already on the target route
    if (currentRoute == routeName) return;
    
    // Cancel any existing timer
    _debounceTimer?.cancel();
    
    // Set debounce timer to prevent rapid clicks
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (mounted && !_isNavigating) {
        setState(() {
          _isNavigating = true;
        });
        
        try {
          // Use pushReplacementNamed to replace current route instead of stacking
          await Navigator.pushReplacementNamed(context, routeName);
        } finally {
          if (mounted) {
            setState(() {
              _isNavigating = false;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80, // increased height for larger text
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: 8, // symmetric padding
        horizontal: 16,
      ),
      child: ClipRect(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          children: [
          _MenuIcon(
            icon: Icons.home_rounded,
            label: _safeTranslate('home', 'Home'),
            onTap: () => _navigateTo('/home'),
            isDisabled: _isNavigating,
          ),
          // _MenuIcon(
          //   icon: Icons.swap_horiz_rounded,
          //   label: _safeTranslate('dex', 'DEX'),
          //   onTap: () => _navigateTo('/dex'),
          //   isDisabled: _isNavigating,
          // ),
          _MenuIcon(
            icon: Icons.qr_code_scanner_rounded,
            label: _safeTranslate('scan', 'Scan'),
            onTap: () async {
              if (_isNavigating) return;
              
              setState(() {
                _isNavigating = true;
              });
              
              try {
                final result = await Navigator.pushNamed(context, '/qr-scanner');
                if (result != null && result is String && result.isNotEmpty) {
                  if (mounted) {
                    // Remove alert dialog - just copy to clipboard silently
                    Clipboard.setData(ClipboardData(text: result));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  }
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isNavigating = false;
                  });
                }
              }
            },
            isDisabled: _isNavigating,
          ),
          _MenuIcon(
            icon: Icons.settings_rounded,
            label: _safeTranslate('settings', 'Settings'),
            onTap: () => _navigateTo('/settings'),
            isDisabled: _isNavigating,
          ),
          ],
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDisabled;
  
  const _MenuIcon({
    required this.icon,
    required this.label,
    required this.onTap, 
    this.isDisabled = false,
    Key? key
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 24,
                color: isDisabled ? Colors.grey : Colors.black54,
              ),
              const SizedBox(height: 2),
              Container(
                height: 18,
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDisabled ? Colors.grey : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 