import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/oauth.dart';
import 'credential_cipher.dart';

/// Persisted login session (Relay V2): the ZCode account JWT plus display
/// info. The JWT is the account credential — on Android it is stored
/// Keystore-encrypted (CredentialCipher); other platforms fall back to
/// plaintext SharedPreferences (same policy as the old V1 URL store).
class SessionStore extends ChangeNotifier {
  static const _prefsKey = 'zemote_session_v2';

  OAuthSession? _session;
  bool _loaded = false;

  OAuthSession? get session => _session;
  bool get loaded => _loaded;
  bool get hasSession =>
      _session != null && _session!.jwt.isNotEmpty && !_session!.isExpired();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _session = null;
    if (raw != null) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final storedJwt = map['jwt'] as String? ?? '';
        String? jwt;
        if (CredentialCipher.isEncrypted(storedJwt)) {
          jwt = await CredentialCipher.decrypt(storedJwt);
        } else {
          jwt = storedJwt;
        }
        final provider = OAuthProviderId.fromId(map['provider'] as String?);
        if (jwt != null && jwt.isNotEmpty && provider != null) {
          final userMap = map['user'];
          _session = OAuthSession(
            jwt: jwt,
            provider: provider,
            expiresAtMs: (map['expiresAtMs'] as num?)?.toInt(),
            user: userMap is Map
                ? OAuthUserInfo(
                    id: userMap['id'] as String? ?? 'unknown',
                    username:
                        userMap['username'] as String? ?? userMap['id'] as String? ?? 'unknown',
                    displayName: userMap['displayName'] as String? ?? 'unknown',
                    avatarUrl: userMap['avatarUrl'] as String?,
                  )
                : null,
          );
        }
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(OAuthSession session) async {
    _session = session;
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final s = _session;
    if (s == null) return;
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'provider': s.provider.id,
      'expiresAtMs': s.expiresAtMs,
      if (s.user != null)
        'user': {
          'id': s.user!.id,
          'username': s.user!.username,
          'displayName': s.user!.displayName,
          if (s.user!.avatarUrl != null) 'avatarUrl': s.user!.avatarUrl,
        },
      'jwt': await CredentialCipher.encrypt(s.jwt) ?? s.jwt,
    };
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
