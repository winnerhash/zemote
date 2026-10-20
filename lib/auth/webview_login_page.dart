import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'oauth.dart';

/// In-app OAuth login. The official redirect URI
/// (`https://zcode.z.ai/remote/v4`) is not registrable by third parties,
/// so we load the provider's authorize page in a WebView and intercept the
/// callback navigation (code + state) before the official page consumes
/// it, then exchange the code natively via [OAuthClient].
class WebViewLoginPage extends StatefulWidget {
  final OAuthProviderId provider;
  final OAuthClient client;

  const WebViewLoginPage({
    super.key,
    required this.provider,
    required this.client,
  });

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  late final String _state = _generateState();
  late final WebViewController _controller;
  String? _error;
  bool _exchanging = false;

  static String _generateState() {
    final random = Random.secure();
    return List.generate(24, (_) => _alphabet[random.nextInt(_alphabet.length)])
        .join();
  }

  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final callback = _matchCallback(request.url);
            if (callback != null) {
              _exchange(callback);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(OAuthConfig.authorizeUrl(widget.provider,
          state: _state)));
  }

  OAuthCallback? _matchCallback(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return OAuthCallbacks.parse(uri, _state);
  }

  Future<void> _exchange(OAuthCallback callback) async {
    if (_exchanging) return;
    setState(() => _exchanging = true);
    try {
      final session = await widget.client.exchangeCode(
        provider: widget.provider,
        code: callback.code,
        state: callback.state,
      );
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exchanging = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 ${widget.provider.label}'),
      ),
      body: Column(
        children: [
          if (_exchanging)
            const LinearProgressIndicator(
                minHeight: 3, backgroundColor: Colors.transparent),
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                        context)
                                    .colorScheme
                                    .onErrorContainer))),
                    TextButton(
                      onPressed: () => _controller.loadRequest(Uri.parse(
                          OAuthConfig.authorizeUrl(widget.provider,
                              state: _state))),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
