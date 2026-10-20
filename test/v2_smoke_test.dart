import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zemote/protocol/relay_http.dart';

// ignore_for_file: avoid_print

/// Relay V2 HTTP smoke test against the REAL relay — no desktop needed.
///
/// 1. Desktop browser: open https://zcode.z.ai/remote/v4, log in (Z.AI or
///    BigModel — the same account your desktop ZCode uses).
/// 2. DevTools → Application → Local Storage → zcode.z.ai → copy the value
///    of `zcodejwttoken` (long JWT string).
/// 3. Run:
///      `set ZEMOTE_PROBE_JWT=paste-the-jwt` then
///      `flutter test test/v2_smoke_test.dart`
///
/// Passes when: the JWT is accepted (token endpoint returns a one-time
/// WS token) and the device list parses. An empty device list is EXPECTED
/// until the desktop is updated to a Relay V2 build and enables remote
/// control.
void main() {
  test('relay v2 http smoke', () async {
    final jwt = Platform.environment['ZEMOTE_PROBE_JWT']?.trim() ?? '';
    if (jwt.isEmpty) {
      print('SKIP: ZEMOTE_PROBE_JWT not set — see instructions in this file.');
      return;
    }

    final relay = RelayHttpClient();

    final token = await relay.fetchToken(jwt, role: 'terminal');
    print('token endpoint OK: ${token.length} chars (expect 22)');
    expect(token, hasLength(22));
    expect(RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$').hasMatch(token), isTrue,
        reason: '16-byte base64url one-time token shape');

    final devices = await relay.listDevices(jwt);
    print('device list OK: ${devices.length} device(s)');
    for (final d in devices) {
      print('  ${d.online ? "[online] " : "[offline]"} '
          '${d.displayName} sid=${d.deviceSid} mid=${d.deviceMid}');
    }

    relay.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
