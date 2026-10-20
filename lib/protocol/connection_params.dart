/// Parses a ZCode web-remote connection URL (Relay V2), e.g.
/// https://zcode.z.ai/remote/v4?sid=...&mid=...&name=...&app_version=...
///
/// V2 URLs carry routing hints only — no credentials. Pairing is
/// account-scoped: the relay matches a device_sid registered by a desktop
/// that is logged into the same account as this client's JWT. Legacy V1
/// URLs (with `hash`/`t` device credentials) are rejected outright; the
/// V1 protocol no longer exists server-side.
class ZemoteConnectionParams {
  final String? deviceSid;
  final String? deviceMid;
  final String? deviceName;
  final String? appVersion;
  final String? theme;
  final Uri source;

  const ZemoteConnectionParams({
    this.deviceSid,
    this.deviceMid,
    this.deviceName,
    this.appVersion,
    this.theme,
    required this.source,
  });

  static String? _get(Uri uri, String key) {
    final v = uri.queryParameters[key]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Parses a QR / pasted URL. Returns null for non-https(s) URLs and for
  /// V1 URLs (a `hash` or `t` parameter marks the dead credential format).
  /// A URL without `sid` is valid (device-list entry point).
  static ZemoteConnectionParams? parse(String raw) {
    Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme != 'https' && uri.scheme != 'wss') return null;
    if (_get(uri, 'hash') != null || _get(uri, 't') != null) return null;
    return ZemoteConnectionParams(
      deviceSid: _get(uri, 'sid'),
      deviceMid: _get(uri, 'mid'),
      deviceName: _get(uri, 'name'),
      appVersion: _get(uri, 'app_version'),
      theme: _get(uri, 'theme'),
      source: uri,
    );
  }

  bool get uriSchemeIsSecure =>
      source.scheme == 'https' || source.scheme == 'wss';

  /// Relay V2 websocket URL: `<ws(s)>://<host>/api/v1/remote/ws2` with the
  /// one-time token (consumed atomically at upgrade, 60s TTL — fetch it
  /// fresh for every connection) and the gateway routing hint `mid`.
  Uri relayWsUri({required String token}) {
    final scheme = uriSchemeIsSecure ? 'wss' : 'ws';
    final base = Uri(
      scheme: scheme,
      host: source.host,
      port: source.hasPort ? source.port : null,
      path: '/api/v1/remote/ws2',
    );
    return base.replace(queryParameters: {
      'token': token,
      if (deviceMid != null) 'mid': deviceMid!,
    });
  }
}
