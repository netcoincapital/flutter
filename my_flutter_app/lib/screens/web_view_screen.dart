import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';


class WebViewScreen extends StatefulWidget {
  final String url;
  const WebViewScreen({Key? key, required this.url}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  bool isLoading = true;
  String pageTitle = '';
  // WebView functionality removed for now

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
    pageTitle = _safeTranslate('loading', 'Loading...');
    // WebView initialization removed for now
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF11c699),
        foregroundColor: Colors.white,
        title: Text(pageTitle, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: Text(_safeTranslate('webview_removed', 'WebView functionality removed for now')),
          ),
        ],
      ),
    );
  }
} 