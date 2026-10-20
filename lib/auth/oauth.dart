import 'dart:convert';

import 'package:http/http.dart' as http;

enum OAuthProviderId {
  zai,
  bigmodel;

  String get id => switch (this) {
        OAuthProviderId.zai => 'zai',
        OAuthProviderId.bigmodel => 'bigmodel',
      };

  String get label => switch (this) {
        OAuthProviderId.zai => 'Z.AI',
        OAuthProviderId.bigmodel => 'BigModel',
      };

  String get region => switch (this) {
        OAuthProviderId.zai => '全球',
        OAuthProviderId.bigmodel => '中国',
      };

  static OAuthProviderId? fromId(String? id) => switch (id) {
        'zai' => OAuthProviderId.zai,
        'bigmodel' => OAuthProviderId.bigmodel,
        _ => null,
      };
}

/// OAuth endpoints replicate the official web client (Relay V2 login).
/// The redirect URI is fixed to the official page — third parties cannot
/// register their own — so a WebView intercepts the callback navigation
/// and the app exchanges the code itself. No PKCE, no client secret.
abstract final class OAuthConfig {
  static const redirectUri = 'https://zcode.z.ai/remote/v4';
  static const zaiAuthorizeOrigin = 'https://chat.z.ai';
  static const zaiClientId = 'client_P8X5CMWmlaRO9gyO-KSqtg';
  static const bigmodelAuthorizeOrigin = 'https://bigmodel.cn';
  static const bigmodelAppId = 'zcode';

  static String authorizeUrl(OAuthProviderId provider, {required String state}) {
    if (provider == OAuthProviderId.bigmodel) {
      // BigModel uses `redirect`/`appId` and returns `authCode`.
      return Uri.parse('$bigmodelAuthorizeOrigin/login').replace(
        queryParameters: {
          'redirect': redirectUri,
          'appId': bigmodelAppId,
          'state': state,
        },
      ).toString();
    }
    return Uri.parse('$zaiAuthorizeOrigin/api/oauth/authorize').replace(
      queryParameters: {
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'client_id': zaiClientId,
        'state': state,
      },
    ).toString();
  }
}

class OAuthUserInfo {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  const OAuthUserInfo({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });
}

class OAuthSession {
  final String jwt;
  final OAuthProviderId provider;
  final String? providerAccessToken;
  final int? expiresAtMs;
  final OAuthUserInfo? user;

  const OAuthSession({
    required this.jwt,
    required this.provider,
    this.providerAccessToken,
    this.expiresAtMs,
    this.user,
  });

  /// True when expires_in was reported and is (nearly) past.
  bool isExpired({DateTime? now, Duration grace = const Duration(minutes: 5)}) {
    if (expiresAtMs == null) return false;
    return (now ?? DateTime.now()).isAfter(
        DateTime.fromMillisecondsSinceEpoch(expiresAtMs!).subtract(grace));
  }
}

/// Result of intercepting a callback navigation in the login WebView.
class OAuthCallback {
  final String code;
  final String state;

  const OAuthCallback({required this.code, required this.state});
}

abstract final class OAuthCallbacks {
  /// Matches a navigation to `<redirectUri>?code|authCode=...&state=...`
  /// (Z.AI returns `code`, BigModel returns `authCode`) and validates the
  /// state against the one we issued.
  static OAuthCallback? parse(Uri uri, String expectedState) {
    if (uri.origin != Uri.parse(OAuthConfig.redirectUri).origin) return null;
    if (!uri.path.startsWith('/remote')) return null;
    final state = uri.queryParameters['state']?.trim();
    if (state == null || state != expectedState) return null;
    final code = uri.queryParameters['code']?.trim().isNotEmpty == true
        ? uri.queryParameters['code']!.trim()
        : uri.queryParameters['authCode']?.trim();
    if (code == null || code.isEmpty) return null;
    return OAuthCallback(code: code, state: state);
  }
}

class OAuthException implements Exception {
  final String message;
  const OAuthException(this.message);
  @override
  String toString() => 'OAuthException($message)';
}

class OAuthClient {
  final String endpointOrigin;
  final http.Client _http;
  final DateTime Function() now;

  OAuthClient({
    this.endpointOrigin = 'https://zcode.z.ai',
    http.Client? client,
    DateTime Function()? now,
  })  : _http = client ?? http.Client(),
        now = now ?? DateTime.now;

  /// Exchanges the authorization code for the ZCode JWT. Public endpoint —
  /// mirrors `POST /api/v1/oauth/token` in the official web client.
  Future<OAuthSession> exchangeCode({
    required OAuthProviderId provider,
    required String code,
    required String state,
  }) async {
    http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$endpointOrigin/api/v1/oauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': provider.id,
          'code': code,
          'redirect_uri': OAuthConfig.redirectUri,
          'state': state,
        }),
      );
    } catch (e) {
      throw OAuthException('网络错误: $e');
    }
    Map<String, dynamic> body;
    try {
      final v = jsonDecode(utf8.decode(response.bodyBytes));
      if (v is! Map<String, dynamic>) throw const FormatException('not an object');
      body = v;
    } catch (_) {
      throw OAuthException('授权服务器响应异常 (HTTP ${response.statusCode})');
    }
    if (response.statusCode == 401 || body['code'] == 401) {
      throw const OAuthException('授权码无效或已过期，请重试');
    }
    final code0 = (body['code'] as num?)?.toInt();
    if (code0 == null || code0 != 0) {
      throw OAuthException(body['msg'] as String? ?? 'token 交换失败 (code=$code0)');
    }
    final data = body['data'];
    if (data is! Map) throw const OAuthException('响应缺少 data');
    final jwt = (data['token'] as String?)?.trim();
    if (jwt == null || jwt.isEmpty) {
      throw const OAuthException('响应缺少 JWT');
    }
    final providerPayload = data[provider.id];
    final providerAccessToken = providerPayload is Map
        ? (providerPayload['access_token'] as String?)?.trim()
        : null;
    final expiresIn = (data['expires_in'] as num?)?.toInt();
    return OAuthSession(
      jwt: jwt,
      provider: provider,
      providerAccessToken: (providerAccessToken == null || providerAccessToken.isEmpty)
          ? null
          : providerAccessToken,
      expiresAtMs: expiresIn == null
          ? null
          : now().millisecondsSinceEpoch + expiresIn * 1000,
      user: _parseUser(data['user']),
    );
  }

  static OAuthUserInfo? _parseUser(Object? raw) {
    if (raw is! Map) return null;
    String? str(Object? k) {
      final v = raw[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final id = str('id') ?? str('user_id') ?? 'unknown';
    final name = str('displayName') ?? str('username') ?? str('name') ?? str('email');
    if (name == null && id == 'unknown') return null;
    return OAuthUserInfo(
      id: id,
      username: name ?? id,
      displayName: str('displayName') ?? name ?? id,
      avatarUrl: str('avatarUrl') ?? str('avatar'),
    );
  }

  void dispose() => _http.close();
}
