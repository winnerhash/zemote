import 'dart:convert';

import 'package:http/http.dart' as http;

/// Relay V2 HTTP API (`/api/v1/remote/*`). Every call carries the account
/// JWT as a Bearer token; successful envelopes are `{code: 0, msg, data}`.
class RelayHttpException implements Exception {
  /// 'auth-required' (JWT invalid/expired — re-login), 'relay-unavailable'
  /// (network/5xx — retryable), or 'server' (business error).
  final String reason;
  final bool retryable;
  final String? detail;

  const RelayHttpException(this.reason, {this.retryable = false, this.detail});

  @override
  String toString() =>
      detail == null ? 'RelayHttpException($reason)' : 'RelayHttpException($reason: $detail)';
}

class RelayDevice {
  final String deviceSid;
  final String deviceMid;
  final bool online;
  final int createdAt;
  final String? name;
  final String? platform;
  final String? version;

  const RelayDevice({
    required this.deviceSid,
    required this.deviceMid,
    required this.online,
    required this.createdAt,
    this.name,
    this.platform,
    this.version,
  });

  String get displayName => (name == null || name!.isEmpty) ? '未命名设备' : name!;

  factory RelayDevice.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    String? metaStr(String k) {
      final v = meta[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return RelayDevice(
      deviceSid: json['device_sid'] as String,
      deviceMid: json['device_mid'] as String,
      online: json['online'] as bool? ?? false,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      name: metaStr('name'),
      platform: metaStr('platform'),
      version: metaStr('version'),
    );
  }
}

class RelayHttpClient {
  final String origin;
  final http.Client _http;

  RelayHttpClient({
    this.origin = 'https://zcode.z.ai',
    http.Client? client,
  }) : _http = client ?? http.Client();

  Map<String, String> _headers(String jwt) => {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    String jwt, {
    Map<String, dynamic>? body,
  }) async {
    http.Response response;
    try {
      final uri = Uri.parse('$origin$path');
      if (method == 'GET') {
        response = await _http.get(uri, headers: _headers(jwt));
      } else {
        response = await _http.post(
          uri,
          headers: _headers(jwt),
          body: body == null ? null : jsonEncode(body),
        );
      }
    } catch (e) {
      throw RelayHttpException('relay-unavailable', retryable: true, detail: '$e');
    }
    if (response.statusCode == 401) {
      throw const RelayHttpException('auth-required');
    }
    Map<String, dynamic> decoded;
    try {
      final v = jsonDecode(utf8.decode(response.bodyBytes));
      if (v is! Map<String, dynamic>) throw const FormatException('not an object');
      decoded = v;
    } catch (_) {
      // Non-2xx without a JSON body still means the relay is unhappy.
      if (response.statusCode >= 500) {
        throw RelayHttpException('relay-unavailable',
            retryable: true, detail: 'HTTP ${response.statusCode}');
      }
      throw RelayHttpException('relay-unavailable', detail: 'HTTP ${response.statusCode}');
    }
    final code = (decoded['code'] as num?)?.toInt();
    if (code == null || code != 0) {
      throw RelayHttpException('server',
          detail: decoded['msg'] as String? ?? 'code=$code');
    }
    return decoded;
  }

  /// Devices registered under the logged-in account. A V2-capable desktop
  /// registers itself when remote control is enabled; V1 desktops never
  /// appear here.
  Future<List<RelayDevice>> listDevices(String jwt) async {
    final res = await _request('GET', '/api/v1/remote/device', jwt);
    final data = res['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((m) => RelayDevice.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// One-time websocket token. 16 random bytes, base64url (22 chars), 60s
  /// TTL, atomically consumed at the WS upgrade — never cache, fetch a
  /// fresh one for every connection attempt.
  Future<String> fetchToken(String jwt, {String role = 'terminal'}) async {
    final res =
        await _request('POST', '/api/v1/remote/token', jwt, body: {'role': role});
    final data = res['data'];
    final token = data is Map ? data['token'] as String? : null;
    if (token == null || token.isEmpty) {
      throw const RelayHttpException('server', detail: 'token missing');
    }
    return token;
  }

  /// Removes an OFFLINE device registration (the server rejects deleting
  /// online devices with code 3005). Purely a hygiene call — failures are
  /// non-fatal for the app.
  Future<void> deleteDevice(String jwt, String deviceSid) async {
    await _request('POST', '/api/v1/remote/device/delete', jwt,
        body: {'device_sid': deviceSid});
  }

  void dispose() => _http.close();
}
