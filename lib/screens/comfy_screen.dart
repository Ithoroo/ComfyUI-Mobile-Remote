import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Full-screen WebView that loads ComfyUI.
class ComfyScreen extends StatefulWidget {
  final String url;
  const ComfyScreen({super.key, required this.url});

  @override
  State<ComfyScreen> createState() => _ComfyScreenState();
}

class _ComfyScreenState extends State<ComfyScreen> {
  InAppWebViewController? _controller;
  double _loadProgress = 0;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ComfyUI'),
        actions: [
          // Reload button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _loadProgress),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          // Allow mixed content (HTTP ComfyUI inside HTTPS if needed)
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onLoadStart: (controller, url) => setState(() => _isLoading = true),
        onLoadStop:  (controller, url) => setState(() => _isLoading = false),
        onProgressChanged: (controller, progress) =>
            setState(() => _loadProgress = progress / 100),
        onReceivedError: (controller, request, error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Load error: ${error.description}')),
          );
        },
      ),
    );
  }
}
