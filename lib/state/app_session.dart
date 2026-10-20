import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/relay_http.dart';
import '../protocol/zemote_client.dart';
import '../state/log_store.dart';
import 'account_store.dart';
import 'session_store.dart';

/// Manages connections to multiple devices simultaneously. Each device can
/// have an independent live connection; exactly one is "active" and drives
/// the MainShell view. Switching to an already-connected device does not
/// reconnect.
///
/// Relay V2: every connection fetches a one-time token with the account
/// JWT ([SessionStore]); an 'auth-required' failure means the login died —
/// surfaced via [authExpired] so the UI can return to the login page.
class AppSession extends ChangeNotifier {
  final SessionStore sessions;
  final RelayHttpClient relayHttp;

  AppSession({required this.sessions, RelayHttpClient? relayHttp})
      : relayHttp = relayHttp ?? RelayHttpClient();

  final Map<String, ZemoteClient> _connections = {};
  final Map<String, StreamSubscription> _failureSubs = {};
  final Set<String> _connecting = {};
  final Map<String, String> _errors = {};
  String? _activeId;
  Account? _activeAccount;

  /// Set when any connection hit 'auth-required' (JWT expired/revoked).
  bool _authExpired = false;
  bool get authExpired => _authExpired;

  /// Currently active device client (drives MainShell).
  ZemoteClient? get client => _connections[_activeId];

  /// Currently active device account.
  Account? get current => _activeAccount;

  /// Whether [accountId] currently has a live connection.
  bool isConnected(String accountId) => _connections.containsKey(accountId);

  /// Whether [accountId] is currently establishing a connection.
  bool connecting(String accountId) => _connecting.contains(accountId);

  /// Last error for [accountId], if any.
  String? errorOf(String accountId) => _errors[accountId];

  /// Client for a specific (possibly non-active) device.
  ZemoteClient? clientOf(String accountId) => _connections[accountId];

  /// True while any device is connecting (disables global add actions).
  bool get connectingAny => _connecting.isNotEmpty;

  /// Fetches a one-time terminal token with the current JWT.
  Future<String> _fetchToken() async {
    final jwt = sessions.session?.jwt;
    if (jwt == null || jwt.isEmpty) {
      throw const RelayHttpException('auth-required');
    }
    return relayHttp.fetchToken(jwt, role: 'terminal');
  }

  /// Ensure [account] is connected and make it active. Reuses an existing
  /// live connection; otherwise establishes a new one.
  Future<ZemoteClient> connect(Account account) async {
    final existing = _connections[account.id];
    if (existing != null) {
      _activate(account);
      return existing;
    }
    if (!sessions.hasSession) {
      _authExpired = true;
      notifyListeners();
      throw StateError('请先登录 ZCode 账号');
    }
    _connecting.add(account.id);
    _errors.remove(account.id);
    notifyListeners();
    final params = account.params;
    final c = ZemoteClient(params, getToken: _fetchToken, onLog: log);
    // Lives for the connection's lifetime: an 'auth-required' relay failure
    // at ANY point (token refresh mid-reconnect) must bounce to login.
    final failureSub = c.relay.failures.listen((f) {
      if (f.reason == 'auth-required') {
        _authExpired = true;
        notifyListeners();
      }
    });
    try {
      await c.connect();
      await c.waitPaired(timeout: const Duration(seconds: 90));
      _connections[account.id] = c;
      _failureSubs[account.id] = failureSub;
      _activate(account);
      return c;
    } catch (e, st) {
      _connecting.remove(account.id);
      _errors[account.id] = '$e';
      notifyListeners();
      await failureSub.cancel();
      await c.dispose();
      Error.throwWithStackTrace(StateError('$e'), st);
    }
  }

  /// Switch the active device without reconnecting. Connects first if needed.
  Future<void> switchTo(Account account) async {
    if (_connections.containsKey(account.id)) {
      _activate(account);
      return;
    }
    await connect(account);
  }

  void _activate(Account account) {
    _activeId = account.id;
    _activeAccount = account;
    _connecting.remove(account.id);
    _errors.remove(account.id);
    notifyListeners();
  }

  /// Disconnect a single device.
  Future<void> disconnect(String accountId) async {
    final conn = _connections.remove(accountId);
    final sub = _failureSubs.remove(accountId);
    _connecting.remove(accountId);
    _errors.remove(accountId);
    if (_activeId == accountId) {
      _activeId = null;
      _activeAccount = null;
    }
    notifyListeners();
    await sub?.cancel();
    await conn?.dispose();
  }

  /// Disconnect everything.
  Future<void> disconnectAll() async {
    final all = _connections.values.toList();
    final subs = _failureSubs.values.toList();
    _connections.clear();
    _failureSubs.clear();
    _connecting.clear();
    _errors.clear();
    _activeId = null;
    _activeAccount = null;
    notifyListeners();
    for (final s in subs) {
      await s.cancel();
    }
    for (final c in all) {
      await c.dispose();
    }
  }

  /// Call after a successful re-login: clears the auth-expired flag and
  /// lets the user retry connections.
  void clearAuthExpired() {
    _authExpired = false;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await disconnectAll();
    super.dispose();
  }
}
