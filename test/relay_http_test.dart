import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zemote/protocol/relay_http.dart';

void main() {
  http.Response ok(Object data) => http.Response.bytes(
      utf8.encode(jsonEncode({'code': 0, 'msg': 'ok', 'data': data})), 200);

  group('listDevices', () {
    test('parses device records and meta', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        expect(request.url.toString(), 'https://zcode.z.ai/api/v1/remote/device');
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer JWT');
        return ok([
          {
            'device_sid': 'sid1',
            'device_mid': 'mid1',
            'online': true,
            'created_at': 1700000000,
            'meta': {'name': '工位机', 'platform': 'win32', 'version': '3.16.2'},
          },
          {
            'device_sid': 'sid2',
            'device_mid': 'mid2',
            'online': false,
            'created_at': 1700000001,
            'meta': {},
          },
        ]);
      }));
      final devices = await client.listDevices('JWT');
      expect(devices, hasLength(2));
      expect(devices.first.deviceSid, 'sid1');
      expect(devices.first.name, '工位机');
      expect(devices.first.online, isTrue);
      expect(devices.last.displayName, '未命名设备');
    });

    test('401 → auth-required', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        return http.Response('unauthorized', 401);
      }));
      await expectLater(
        client.listDevices('JWT'),
        throwsA(isA<RelayHttpException>()
            .having((e) => e.reason, 'reason', 'auth-required')),
      );
    });

    test('business error code → server error', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        return http.Response(
            jsonEncode({'code': 3005, 'msg': 'wrong status'}), 400);
      }));
      await expectLater(
        client.listDevices('JWT'),
        throwsA(isA<RelayHttpException>()
            .having((e) => e.reason, 'reason', 'server')
            .having((e) => e.detail, 'detail', 'wrong status')),
      );
    });

    test('network failure → retryable relay-unavailable', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        throw http.ClientException('boom');
      }));
      await expectLater(
        client.listDevices('JWT'),
        throwsA(isA<RelayHttpException>()
            .having((e) => e.reason, 'reason', 'relay-unavailable')
            .having((e) => e.retryable, 'retryable', true)),
      );
    });
  });

  group('fetchToken', () {
    test('posts role and returns token', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        expect(request.url.toString(), 'https://zcode.z.ai/api/v1/remote/token');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'role': 'terminal'});
        return ok({
          'token': 'AbCdEfGhIjKlMnOpQrStUw',
          'expires_in': 60,
        });
      }));
      final token = await client.fetchToken('JWT');
      expect(token, 'AbCdEfGhIjKlMnOpQrStUw');
    });

    test('missing token in envelope → server error', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        return ok({'expires_in': 60});
      }));
      await expectLater(
        client.fetchToken('JWT'),
        throwsA(isA<RelayHttpException>()),
      );
    });
  });

  group('deleteDevice', () {
    test('posts device_sid', () async {
      final client = RelayHttpClient(client: MockClient((request) async {
        expect(request.url.toString(),
            'https://zcode.z.ai/api/v1/remote/device/delete');
        expect(jsonDecode(request.body), {'device_sid': 'sid1'});
        // Go server may omit data on delete success.
        return http.Response(jsonEncode({'code': 0, 'msg': 'ok'}), 200);
      }));
      await client.deleteDevice('JWT', 'sid1');
    });
  });
}
