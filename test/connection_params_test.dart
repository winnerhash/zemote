import 'package:flutter_test/flutter_test.dart';

import 'package:zemote/protocol/connection_params.dart';

void main() {
  group('parse (Relay V2)', () {
    test('full url with all routing hints', () {
      final params = ZemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=SID&mid=MID&name=DEV&app_version=3.16.2&theme=dark',
      );
      expect(params, isNotNull);
      expect(params!.deviceSid, 'SID');
      expect(params.deviceMid, 'MID');
      expect(params.deviceName, 'DEV');
      expect(params.appVersion, '3.16.2');
      expect(params.theme, 'dark');
    });

    test('url without sid is valid (device-list entry)', () {
      final params =
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4');
      expect(params, isNotNull);
      expect(params!.deviceSid, isNull);
    });

    test('rejects v1 credential urls', () {
      expect(
          ZemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1785734607338'),
          isNull);
      expect(
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?hash=h'),
          isNull);
      expect(
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?t=123'),
          isNull);
    });

    test('rejects insecure scheme', () {
      expect(
          ZemoteConnectionParams.parse('http://zcode.z.ai/remote/v4?sid=s'),
          isNull);
      expect(ZemoteConnectionParams.parse('ftp://x/remote'), isNull);
    });

    test('rejects garbage', () {
      expect(ZemoteConnectionParams.parse('not a url'), isNull);
      expect(ZemoteConnectionParams.parse(''), isNull);
    });

    test('blank values are treated as absent', () {
      final params = ZemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=%20&name=');
      expect(params, isNotNull);
      expect(params!.deviceSid, isNull);
      expect(params.deviceName, isNull);
    });
  });

  group('relayWsUri', () {
    test('builds ws2 url with token and mid', () {
      final params = ZemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=s&mid=m');
      expect(
        params!.relayWsUri(token: 'TOKEN').toString(),
        'wss://zcode.z.ai/api/v1/remote/ws2?token=TOKEN&mid=m',
      );
    });

    test('omits mid when absent', () {
      final params =
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?sid=s');
      expect(
        params!.relayWsUri(token: 'T').toString(),
        'wss://zcode.z.ai/api/v1/remote/ws2?token=T',
      );
    });

    test('keeps custom port', () {
      final params = ZemoteConnectionParams.parse(
          'https://relay.example:8443/remote/v4?sid=s');
      expect(
        params!.relayWsUri(token: 'T').toString(),
        'wss://relay.example:8443/api/v1/remote/ws2?token=T',
      );
    });

    test('token survives url decoding', () {
      final params =
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?sid=s');
      final uri = params!.relayWsUri(token: 'a+b/c?d');
      expect(uri.queryParameters['token'], 'a+b/c?d');
    });
  });

  group('uriSchemeIsSecure', () {
    test('https/wss → secure', () {
      expect(
        ZemoteConnectionParams(source: Uri.parse('https://zcode.z.ai/remote'))
            .uriSchemeIsSecure,
        isTrue,
      );
      expect(
        ZemoteConnectionParams(source: Uri.parse('wss://x/ws'))
            .uriSchemeIsSecure,
        isTrue,
      );
    });
  });
}
