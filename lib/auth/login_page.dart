import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../state/session_store.dart';
import 'oauth.dart';
import 'webview_login_page.dart';

/// Login gate (Relay V2): pick Z.AI or BigModel and complete OAuth in a
/// WebView. Use the SAME account the desktop ZCode is logged into —
/// devices are listed and matched per account.
class LoginPage extends StatefulWidget {
  final SessionStore sessions;
  final OAuthClient client;

  const LoginPage({super.key, required this.sessions, required this.client});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _login(OAuthProviderId provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = await Navigator.of(context).push<OAuthSession>(
        MaterialPageRoute(
          builder: (_) => WebViewLoginPage(provider: provider, client: widget.client),
        ),
      );
      if (session != null) {
        await widget.sessions.save(session);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.devices_other_outlined,
                    size: 34, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('Zemote 远程控制',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                '登录与桌面端 ZCode 相同的账号\n远程控制按账号匹配设备',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 32),
              for (final provider in OAuthProviderId.values) ...[
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _login(provider),
                  icon: const Icon(Icons.login),
                  label: Text('${provider.label} 登录（${provider.region}）'),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 16),
              Text(
                '第三方协议复刻客户端，与 Z.ai 官方无关\n登录凭据仅存储于本机',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: ZInk.faint(context), height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
