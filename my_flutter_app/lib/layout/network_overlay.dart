import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../screens/network_error_dialog.dart';
import 'dart:async';

class NetworkOverlay extends StatefulWidget {
  final Widget child;
  const NetworkOverlay({Key? key, required this.child}) : super(key: key);

  @override
  State<NetworkOverlay> createState() => _NetworkOverlayState();
}

class _NetworkOverlayState extends State<NetworkOverlay> {
  bool showNetworkError = false;
  late final Connectivity _connectivity;
  late final Stream<ConnectivityResult> _connectivityStream;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity();
    _connectivityStream = _connectivity.onConnectivityChanged;
    _connectivityStream.listen((result) async {
      final hasInternet = await _hasRealInternet();
      if (!hasInternet) {
        setState(() {
          showNetworkError = true;
        });
        _startRetryTimer();
      } else {
        setState(() {
          showNetworkError = false;
        });
        _stopRetryTimer();
      }
    });
    _checkInitialConnection();
  }

  @override
  void dispose() {
    _stopRetryTimer();
    super.dispose();
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final hasInternet = await _hasRealInternet();
      if (hasInternet) {
        setState(() {
          showNetworkError = false;
        });
        _stopRetryTimer();
      }
    });
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _checkInitialConnection() async {
    final hasInternet = await _hasRealInternet();
    setState(() {
      showNetworkError = !hasInternet;
    });
    if (!hasInternet) {
      _startRetryTimer();
    }
  }

  Future<bool> _hasRealInternet() async {
    final List<String> testSites = [
      'google.com',
      'example.com',
      'cloudflare.com',
    ];
    for (final site in testSites) {
      try {
        final result = await InternetAddress.lookup(site);
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // ignore
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (showNetworkError)
          AbsorbPointer(
            absorbing: true,
            child: NetworkErrorDialog(
              onDismiss: () {}, // دیگر dismiss نمی‌شود
            ),
          ),
      ],
    );
  }
} 