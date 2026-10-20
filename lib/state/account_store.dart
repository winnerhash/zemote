import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/connection_params.dart';
import '../protocol/relay_http.dart';

/// A desktop device bookmark (Relay V2). Carries NO credentials — the
/// relay authorizes via the account JWT ([SessionStore]) and matches the
/// `device_sid` registered by the desktop. Device records ultimately come
/// from the server (`RelayHttpClient.listDevices`); local entries persist
/// across restarts for instant boot and offline display.
class Account {
  final String id;
  final String deviceSid;
  String label;
  final String? deviceMid;
  final String? appVersion;
  final String origin;
  final int addedAt;
  int? lastUsedAt;

  /// Last server-reported online state (null = unknown / offline record).
  bool online;

  Account({
    required this.id,
    required this.deviceSid,
    required this.label,
    required this.origin,
    required this.addedAt,
    this.deviceMid,
    this.appVersion,
    this.lastUsedAt,
    this.online = false,
  });

  factory Account.fromDevice(RelayDevice device, {String origin = 'https://zcode.z.ai'}) =>
      Account(
        id: device.deviceSid,
        deviceSid: device.deviceSid,
        label: device.displayName,
        origin: origin,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        deviceMid: device.deviceMid,
        online: device.online,
      );

  /// From a scanned/pasted V2 URL (sid/mid/name/app_version, no creds).
  factory Account.fromParams(ZemoteConnectionParams params) => Account(
        id: params.deviceSid!,
        deviceSid: params.deviceSid!,
        label: params.deviceName ?? '未命名设备',
        origin: Uri(scheme: 'https', host: params.source.host).toString(),
        addedAt: DateTime.now().millisecondsSinceEpoch,
        deviceMid: params.deviceMid,
        appVersion: params.appVersion,
      );

  /// Connection params rebuilt from stored fields.
  ZemoteConnectionParams get params => ZemoteConnectionParams(
        deviceSid: deviceSid,
        deviceMid: deviceMid,
        deviceName: label,
        appVersion: appVersion,
        source: Uri.parse('$origin/remote/v4'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceSid': deviceSid,
        'label': label,
        'origin': origin,
        'addedAt': addedAt,
        'online': online,
        if (deviceMid != null) 'deviceMid': deviceMid,
        if (appVersion != null) 'appVersion': appVersion,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['deviceSid'] as String? ?? json['id'] as String? ?? '',
        deviceSid: json['deviceSid'] as String? ?? '',
        label: json['label'] as String? ?? '未命名设备',
        origin: json['origin'] as String? ?? 'https://zcode.z.ai',
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
        deviceMid: json['deviceMid'] as String?,
        appVersion: json['appVersion'] as String?,
        lastUsedAt: (json['lastUsedAt'] as num?)?.toInt(),
        online: json['online'] as bool? ?? false,
      );
}

/// Device bookmark store persisted in SharedPreferences. The live list is
/// authoritative from the relay; this keeps a local merged copy.
class AccountStore extends ChangeNotifier {
  static const _prefsKey = 'zemote_devices_v2';

  final List<Account> _accounts = [];
  List<Account> get accounts => List.unmodifiable(_accounts);

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _accounts.clear();
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final map = item.cast<String, dynamic>();
              // Legacy V1 entries ('url' with hash/t credentials) are dead:
              // the relay rejects them and the desktop cannot re-issue.
              if (!map.containsKey('deviceSid')) continue;
              final account = Account.fromJson(map);
              if (account.deviceSid.isNotEmpty) _accounts.add(account);
            }
          }
        }
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // No credentials in this format (V2 URLs carry none), so plaintext
    // persistence is fine — unlike the old V1 URL store.
    await prefs.setString(
        _prefsKey, jsonEncode(_accounts.map((a) => a.toJson()).toList()));
  }

  /// Merges the server device list into local bookmarks: upserts by sid,
  /// refreshes online state/labels, adds unseen devices. Entries known
  /// locally but missing server-side (e.g. desktop re-registered) are
  /// dropped — their sid is no longer connectable.
  Future<void> syncDevices(List<RelayDevice> devices) async {
    final bySid = {for (final d in devices) d.deviceSid: d};
    final merged = <Account>[];
    for (final d in devices) {
      final existing = _accounts.where((a) => a.deviceSid == d.deviceSid).firstOrNull;
      if (existing == null) {
        merged.add(Account.fromDevice(d));
        continue;
      }
      existing.online = d.online;
      // Server meta.name wins while the device is online (fresh); keep the
      // local (possibly renamed) label when the record is offline.
      if (d.online && d.name != null && d.name!.isNotEmpty) {
        existing.label = d.name!;
      }
      merged.add(existing);
    }
    final knownOffline =
        _accounts.where((a) => !bySid.containsKey(a.deviceSid)).toList();
    _accounts
      ..clear()
      ..addAll(merged)
      ..addAll(knownOffline);
    await _save();
    notifyListeners();
  }

  Future<Account> addParams(ZemoteConnectionParams params) async {
    final account = Account.fromParams(params);
    final existing =
        _accounts.where((a) => a.deviceSid == account.deviceSid).firstOrNull;
    if (existing != null) {
      _activate(existing);
      return existing;
    }
    _accounts.add(account);
    await _save();
    notifyListeners();
    return account;
  }

  void _activate(Account account) {
    account.lastUsedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> remove(String id) async {
    _accounts.removeWhere((a) => a.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> rename(String id, String label) async {
    final account = _accounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return;
    account.label = label.trim().isEmpty ? account.label : label.trim();
    await _save();
    notifyListeners();
  }

  Future<void> touch(String id) async {
    final account = _accounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return;
    _activate(account);
    await _save();
    notifyListeners();
  }

  String exportJson() => jsonEncode({
        'app': 'zemote',
        'format': 'devices',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'accounts': _accounts.map((a) => a.toJson()).toList(),
      });

  /// V2 exports carry no credentials — importing just re-creates bookmarks.
  Future<int> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    final list = decoded is Map ? decoded['accounts'] : decoded;
    if (list is! List) {
      throw const FormatException('不是有效的设备导出文件');
    }
    var added = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      if (map['deviceSid'] == null) continue;
      final account = Account.fromJson(map);
      if (account.deviceSid.isEmpty) continue;
      if (_accounts.any((a) => a.deviceSid == account.deviceSid)) continue;
      _accounts.add(account);
      added++;
    }
    if (added > 0) {
      await _save();
      notifyListeners();
    }
    return added;
  }
}
