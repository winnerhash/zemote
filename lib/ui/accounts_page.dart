import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/login_page.dart';
import '../auth/oauth.dart';
import '../protocol/connection_params.dart';
import '../protocol/relay_client.dart';
import '../protocol/relay_http.dart';
import '../state/account_store.dart';
import '../state/app_session.dart';
import '../state/session_store.dart';
import 'log_page.dart';
import 'main_shell.dart';
import 'qr_scan_page.dart';
import 'theme.dart';

/// Home page: login gate + device list (Relay V2). Devices come from the
/// account's relay registration (V2-capable desktops); bookmarks persist
/// locally. Connect/switch between them like before.
class AccountsPage extends StatefulWidget {
  final AccountStore store;
  final SessionStore sessions;
  final AppSession session;
  final RelayHttpClient relayHttp;
  final OAuthClient oauthClient;

  const AccountsPage({
    super.key,
    required this.store,
    required this.sessions,
    required this.session,
    required this.relayHttp,
    required this.oauthClient,
  });

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool _refreshing = false;
  Object? _refreshError;
  bool _hadSession = false;

  @override
  void initState() {
    super.initState();
    if (!widget.store.loaded) widget.store.load();
    widget.sessions.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  void _onSessionChanged() {
    final has = widget.sessions.hasSession && !widget.session.authExpired;
    // Fresh login (or first boot with a stored session): pull the device
    // list right away so the list isn't stale.
    if (has && !_hadSession) {
      _refreshDevices(silent: true);
    }
    _hadSession = has;
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _refreshDevices({bool silent = false}) async {
    if (_refreshing) return;
    final jwt = widget.sessions.session?.jwt;
    if (jwt == null) return;
    setState(() {
      _refreshing = true;
      if (!silent) _refreshError = null;
    });
    try {
      final devices = await widget.relayHttp.listDevices(jwt);
      await widget.store.syncDevices(devices);
      if (mounted) setState(() => _refreshError = null);
    } catch (e) {
      if (e is RelayHttpException && e.reason == 'auth-required') {
        // JWT revoked server-side (signed out elsewhere / rotated): clear
        // locally and drop back to the login gate.
        await widget.session.disconnectAll();
        await widget.sessions.clear();
        return;
      }
      if (mounted) setState(() => _refreshError = '$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _switchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换账号？'),
        content: const Text('将退出当前手机端账号，返回登录页。\n电脑端仍保持登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出并切换')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.session.disconnectAll();
    widget.session.clearAuthExpired();
    await widget.sessions.clear();
  }

  /// Exports device bookmarks to a JSON file. V2 bookmarks carry no
  /// credentials — sharing them only reveals device names/sids.
  Future<void> _exportDevices(BuildContext context) async {
    final json = widget.store.exportJson();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出设备'),
        content: const Text('将导出设备书签（V2 格式，不含账号凭据）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导出')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '导出设备',
        fileName: 'zemote-devices.json',
        bytes: utf8.encode(json),
      );
      if (path == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导出 ${widget.store.accounts.length} 台设备')));
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: json));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存文件失败，已将导出内容复制到剪贴板')));
      }
    }
  }

  Future<void> _importDevices(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      var bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) return;
      final count = await widget.store.importJson(utf8.decode(bytes));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(count > 0 ? '导入 $count 台设备' : '没有可导入的新设备')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  Future<void> _addByUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴远程控制链接'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'https://zcode.z.ai/remote/v4?sid=...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    final params = ZemoteConnectionParams.parse(url);
    if (params?.deviceSid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('链接无效：需要 V2 格式（sid 参数，且不含 hash/t）')));
      }
      return;
    }
    await widget.store.addParams(params!);
  }

  Future<void> _addByScan() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (url == null || url.isEmpty) return;
    final params = ZemoteConnectionParams.parse(url);
    if (params?.deviceSid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('二维码无效：不是 V2 远程控制链接')),
        );
      }
      return;
    }
    await widget.store.addParams(params!);
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('扫码添加'),
              subtitle: const Text('扫描桌面端远程控制二维码'),
              onTap: () {
                Navigator.pop(context);
                _addByScan();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('粘贴链接添加'),
              subtitle: const Text('输入 https://zcode.z.ai/remote/v4?sid=... 链接'),
              onTap: () {
                Navigator.pop(context);
                _addByUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新设备列表'),
              subtitle: const Text('从账号拉取已注册的桌面设备'),
              onTap: () {
                Navigator.pop(context);
                _refreshDevices();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(Account account) async {
    final controller = TextEditingController(text: account.label);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label != null) await widget.store.rename(account.id, label);
  }

  Future<void> _delete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备？'),
        content: Text('将移除「${account.label}」的书签。'
            '${account.online ? '\n设备在线：仅移除本地书签，服务端记录保留。' : '\n设备离线：同时尝试删除服务端记录。'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.session.isConnected(account.id)) {
      await widget.session.disconnect(account.id);
    }
    await widget.store.remove(account.id);
    // Server-side cleanup is best-effort and only allowed for offline
    // devices (the relay rejects deleting online ones with code 3005).
    if (!account.online) {
      final jwt = widget.sessions.session?.jwt;
      if (jwt != null) {
        try {
          await widget.relayHttp.deleteDevice(jwt, account.deviceSid);
        } catch (_) {}
      }
    }
  }

  /// Open the active device's shell. Already-connected devices switch
  /// instantly without reconnecting.
  Future<void> _open(Account account) async {
    await widget.store.touch(account.id);
    try {
      await widget.session.connect(account);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MainShell(
            session: widget.session,
            store: widget.store,
            onAddDevice: _showAddSheet,
            onDisconnect: () {
              widget.session.disconnect(account.id);
              Navigator.of(context).pop();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('连接失败: $e')));
    }
  }

  String _stateText(RelayState state) {
    switch (state) {
      case RelayState.connecting:
        return '连接中转服务…';
      case RelayState.authenticating:
        return '认证设备…';
      case RelayState.waiting:
        return '等待桌面端配对…';
      case RelayState.paired:
        return '已配对';
      case RelayState.reconnecting:
        return '重连中…';
      case RelayState.error:
        return '连接失败';
      case RelayState.kicked:
        return '已被踢下线';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [widget.store, widget.session, widget.sessions]),
      builder: (context, _) {
        if (!widget.sessions.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        // Login gate: no session, or the JWT died mid-use (auth-required).
        if (!widget.sessions.hasSession || widget.session.authExpired) {
          return LoginPage(
              sessions: widget.sessions, client: widget.oauthClient);
        }
        final accounts = widget.store.accounts;
        final session = widget.session;
        final user = widget.sessions.session?.user;
        final provider = widget.sessions.session?.provider;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Zemote 远程控制'),
                Text(
                  '${user?.displayName ?? user?.username ?? '已登录'} · ${provider?.label ?? ''}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: ZInk.faint(context)),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                tooltip: '刷新设备列表',
                onPressed: _refreshing ? null : () => _refreshDevices(),
              ),
              IconButton(
                icon: const Icon(Icons.switch_account),
                tooltip: '切换账号',
                onPressed: _switchAccount,
              ),
              IconButton(
                icon: const Icon(Icons.terminal),
                tooltip: '协议日志',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LogPage())),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) {
                  if (v == 'import') _importDevices(context);
                  if (v == 'export') _exportDevices(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'import', child: Text('导入设备')),
                  PopupMenuItem(value: 'export', child: Text('导出设备')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: session.connectingAny ? null : _showAddSheet,
            icon: const Icon(Icons.add),
            label: const Text('添加设备'),
          ),
          body: _deviceBody(context, accounts, session),
        );
      },
    );
  }

  Widget _deviceBody(
      BuildContext context, List<Account> accounts, AppSession session) {
    if (_refreshError != null) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.cloud_off,
                  color: Theme.of(context).colorScheme.onErrorContainer),
              title: Text('设备列表刷新失败：$_refreshError',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer)),
              trailing: TextButton(
                  onPressed: () => _refreshDevices(),
                  child: const Text('重试')),
            ),
          ),
          Expanded(child: _accountList(context, accounts, session)),
        ],
      );
    }
    return _accountList(context, accounts, session);
  }

  Widget _accountList(
      BuildContext context, List<Account> accounts, AppSession session) {
    if (accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.desktop_windows_outlined,
                    size: 34, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('还没有设备',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                '在桌面端 ZCode（新版）登录同一账号并开启远程控制，\n'
                '然后刷新列表或扫码添加',
                textAlign: TextAlign.center,
                style: TextStyle(color: ZInk.faint(context), height: 1.6),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh),
                label: const Text('刷新设备列表'),
                onPressed: () => _refreshDevices(),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refreshDevices(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: accounts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) =>
            _deviceTile(context, accounts[index], session),
      ),
    );
  }

  Widget _deviceTile(BuildContext context, Account account, AppSession session) {
    final isCurrent = session.current?.id == account.id;
    final client = session.clientOf(account.id);
    final connecting = session.connecting(account.id);
    final error = session.errorOf(account.id);
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isCurrent
                ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isCurrent
                ? Icons.desktop_windows
                : Icons.desktop_windows_outlined,
            size: 20,
            color: isCurrent
                ? const Color(0xFF22C55E)
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(account.label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Icon(
              Icons.circle,
              size: 8,
              color: account.online
                  ? const Color(0xFF22C55E)
                  : ZInk.ghost(context),
            ),
            const SizedBox(width: 4),
            Text(
              account.online ? '在线' : '离线',
              style: TextStyle(
                fontSize: 10,
                color: account.online
                    ? const Color(0xFF22C55E)
                    : ZInk.faint(context),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.deviceMid ?? account.deviceSid,
              style: TextStyle(fontSize: 11, color: ZInk.faint(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (client != null)
              ValueListenableBuilder<RelayState>(
                valueListenable: client.relay.stateListenable,
                builder: (context, state, _) {
                  if (connecting &&
                      state != RelayState.paired &&
                      state != RelayState.error) {
                    return _PairSteps(state: state);
                  }
                  final text = _stateText(state);
                  if (text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    text,
                    style: TextStyle(
                      fontSize: 11,
                      color: state == RelayState.paired
                          ? Colors.green
                          : state == RelayState.error ||
                                  state == RelayState.kicked
                              ? Colors.red
                              : Colors.orange,
                    ),
                  );
                },
              )
            else if (error != null)
              Text(error,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
            else if (connecting)
              const Text('正在连接…',
                  style: TextStyle(fontSize: 11, color: Colors.orange))
            else
              Text('未连接',
                  style: TextStyle(fontSize: 11, color: ZInk.faint(context))),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connecting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (client != null)
              IconButton(
                icon: Icon(isCurrent ? Icons.link_off : Icons.play_arrow),
                tooltip: isCurrent ? '断开' : '打开',
                onPressed: () => isCurrent
                    ? widget.session.disconnect(account.id)
                    : _open(account),
              )
            else
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: '连接',
                onPressed: () => _open(account),
              ),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'rename') _rename(account);
                if (action == 'delete') _delete(account);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
        onTap: connecting ? null : () => _open(account),
      ),
    );
  }
}

/// 4-step pairing progress (mirrors the web bootstrap steps).
class _PairSteps extends StatelessWidget {
  final RelayState state;

  const _PairSteps({required this.state});

  static const _steps = ['连接中转', '设备认证', '等待配对', '完成'];

  @override
  Widget build(BuildContext context) {
    final current = switch (state) {
      RelayState.connecting => 0,
      RelayState.authenticating => 1,
      RelayState.waiting => 2,
      _ => 3,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              Container(
                width: 10,
                height: 1,
                color: i <= current ? Colors.green : ZInk.ghost(context),
              ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < current
                    ? Colors.green
                    : i == current
                        ? Colors.orange
                        : ZInk.ghost(context),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              _steps[i],
              style: TextStyle(
                fontSize: 9,
                color: i <= current ? ZInk.soft(context) : ZInk.ghost(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
