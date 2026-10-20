import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zemote/auth/oauth.dart';

void main() {
  group('authorizeUrl', () {
    test('zai uses redirect_uri/client_id params', () {
      final url = Uri.parse(OAuthConfig.authorizeUrl(OAuthProviderId.zai,
          state: 'ST'));
      expect(url.origin, 'https://chat.z.ai');
      expect(url.path, '/api/oauth/authorize');
      expect(url.queryParameters['redirect_uri'],
          'https://zcode.z.ai/remote/v4');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['client_id'], 'client_P8X5CMWmlaRO9gyO-KSqtg');
      expect(url.queryParameters['state'], 'ST');
    });

    test('bigmodel uses redirect/appId params', () {
      final url = Uri.parse(OAuthConfig.authorizeUrl(OAuthProviderId.bigmodel,
          state: 'ST'));
      expect(url.origin, 'https://bigmodel.cn');
      expect(url.path, '/login');
      expect(url.queryParameters['redirect'], 'https://zcode.z.ai/remote/v4');
      expect(url.queryParameters['appId'], 'zcode');
      expect(url.queryParameters['state'], 'ST');
    });
  });

  group('OAuthCallbacks.parse', () {
    test('zai code callback', () {
      final cb = OAuthCallbacks.parse(
        Uri.parse('https://zcode.z.ai/remote/v4?code=abc&state=ST'),
        'ST',
      );
      expect(cb, isNotNull);
      expect(cb!.code, 'abc');
      expect(cb.state, 'ST');
    });

    test('bigmodel authCode callback', () {
      final cb = OAuthCallbacks.parse(
        Uri.parse('https://zcode.z.ai/remote/v4?authCode=xyz&state=ST'),
        'ST',
      );
      expect(cb, isNotNull);
      expect(cb!.code, 'xyz');
    });

    test('rejects mismatched state (CSRF guard)', () {
      expect(
        OAuthCallbacks.parse(
            Uri.parse('https://zcode.z.ai/remote/v4?code=a&state=OTHER'), 'ST'),
        isNull,
      );
    });

    test('rejects foreign origins and error callbacks', () {
      expect(
        OAuthCallbacks.parse(
            Uri.parse('https://evil.example/remote/v4?code=a&state=ST'), 'ST'),
        isNull,
      );
      expect(
        OAuthCallbacks.parse(
            Uri.parse('https://zcode.z.ai/remote/v4?error=d&state=ST'), 'ST'),
        isNull,
      );
    });
  });

  group('OAuthClient.exchangeCode', () {
    test('parses zai token envelope', () async {
      final client = OAuthClient(
        client: MockClient((request) async {
          expect(request.url.toString(),
              'https://zcode.z.ai/api/v1/oauth/token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['provider'], 'zai');
          expect(body['code'], 'abc');
          expect(body['redirect_uri'], 'https://zcode.z.ai/remote/v4');
          expect(body['state'], 'ST');
          return http.Response(
            jsonEncode({
              'code': 0,
              'msg': 'ok',
              'data': {
                'token': 'JWT-VALUE',
                'zai': {'access_token': 'ZAI-AT'},
                'expires_in': 3600,
                'user': {
                  'id': 'u1',
                  'username': 'alice',
                  'displayName': 'Alice',
                },
              },
            }),
            200,
          );
        }),
        now: () => DateTime.fromMillisecondsSinceEpoch(1000000),
      );
      final session = await client.exchangeCode(
          provider: OAuthProviderId.zai, code: 'abc', state: 'ST');
      expect(session.jwt, 'JWT-VALUE');
      expect(session.provider, OAuthProviderId.zai);
      expect(session.providerAccessToken, 'ZAI-AT');
      expect(session.expiresAtMs, 1000000 + 3600 * 1000);
      expect(session.user?.displayName, 'Alice');
      expect(
        session.isExpired(
            now: DateTime.fromMillisecondsSinceEpoch(1000000)),
        isFalse,
      );
    });

    test('parses bigmodel envelope (access_token under bigmodel)', () async {
      final client = OAuthClient(client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'msg': 'ok',
            'data': {
              'token': 'JWT-BM',
              'bigmodel': {'access_token': 'BM-AT'},
              'expires_in': 60,
              'user': {'user_id': 'u2', 'name': 'bob', 'email': 'b@x'},
            },
          }),
          200,
        );
      }));
      final session = await client.exchangeCode(
          provider: OAuthProviderId.bigmodel, code: 'c', state: 's');
      expect(session.jwt, 'JWT-BM');
      expect(session.providerAccessToken, 'BM-AT');
      expect(session.user?.username, 'bob');
    });

    test('non-zero code → OAuthException', () async {
      final client = OAuthClient(client: MockClient((request) async {
        return http.Response(
            jsonEncode({'code': 1001, 'msg': 'bad code'}), 200);
      }));
      await expectLater(
        client.exchangeCode(
            provider: OAuthProviderId.zai, code: 'x', state: 's'),
        throwsA(isA<OAuthException>()),
      );
    });

    test('missing JWT in data → OAuthException', () async {
      final client = OAuthClient(client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'zai': {'access_token': 'AT'},
            }
          }),
          200,
        );
      }));
      await expectLater(
        client.exchangeCode(
            provider: OAuthProviderId.zai, code: 'x', state: 's'),
        throwsA(isA<OAuthException>()),
      );
    });
  });

  group('OAuthProviderId', () {
    test('round-trips ids', () {
      for (final p in OAuthProviderId.values) {
        expect(OAuthProviderId.fromId(p.id), p);
      }
      expect(OAuthProviderId.fromId('nope'), isNull);
    });
  });
}
