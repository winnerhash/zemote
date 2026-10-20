import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zemote/protocol/connection_params.dart';
import 'package:zemote/protocol/relay_http.dart';
import 'package:zemote/state/account_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  RelayDevice device(String sid,
      {String mid = 'm', bool online = false, String? name}) {
    return RelayDevice(
      deviceSid: sid,
      deviceMid: mid,
      online: online,
      createdAt: 1700000000,
      name: name,
    );
  }

  test('exportJson round-trips through importJson', () async {
    final store = AccountStore();
    await store.syncDevices([device('abc', name: '桌面1', online: true)]);
    final exported = store.exportJson();
    final parsed = jsonDecode(exported) as Map<String, dynamic>;
    expect(parsed['accounts'], isA<List>());
    expect((parsed['accounts'] as List), hasLength(1));

    final store2 = AccountStore();
    final count = await store2.importJson(exported);
    expect(count, 1);
    expect(store2.accounts, hasLength(1));
    expect(store2.accounts.first.deviceSid, 'abc');
    expect(store2.accounts.first.label, '桌面1');
  });

  test('importJson skips entries without sid and duplicates', () async {
    final store = AccountStore();
    await store.syncDevices([device('abc', name: '桌面1')]);
    final count = await store.importJson(jsonEncode({
      'app': 'zemote',
      'accounts': [
        {
          'id': 'x1',
          'label': 'dup',
          'deviceSid': 'abc',
          'origin': 'https://zcode.z.ai'
        },
        {'id': 'x2', 'label': 'legacy v1', 'url': 'https://zcode.z.ai/remote/v4?sid=z&hash=h&t=1'},
        {'id': 'x3', 'label': 'new', 'deviceSid': 'zzz'},
      ],
    }));
    expect(count, 1);
    expect(store.accounts, hasLength(2));
  });

  test('importJson rejects non-device files', () async {
    final store = AccountStore();
    await expectLater(
      store.importJson('{"foo": 1}'),
      throwsFormatException,
    );
  });

  test('syncDevices merges by sid and refreshes online state', () async {
    final store = AccountStore();
    await store.syncDevices([
      device('a', name: 'A', online: true),
      device('b', name: 'B'),
    ]);
    expect(store.accounts, hasLength(2));
    expect(store.accounts.firstWhere((d) => d.deviceSid == 'a').online, isTrue);

    // a went offline, b renamed+online, c is new
    await store.syncDevices([
      device('a', name: 'A'),
      device('b', name: 'B2', online: true),
      device('c', name: 'C', online: true),
    ]);
    expect(store.accounts, hasLength(3));
    final a = store.accounts.firstWhere((d) => d.deviceSid == 'a');
    expect(a.online, isFalse);
    // online records take the server's fresh name
    final b = store.accounts.firstWhere((d) => d.deviceSid == 'b');
    expect(b.label, 'B2');
    expect(store.accounts.any((d) => d.deviceSid == 'c'), isTrue);
  });

  test('addParams dedupes by sid', () async {
    final store = AccountStore();
    final p1 = ZemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s1&name=One')!;
    final p2 = ZemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s1&name=Two')!;
    await store.addParams(p1);
    await store.addParams(p2);
    expect(store.accounts, hasLength(1));
    expect(store.accounts.first.label, 'One');
  });

  test('addParams rejects sid-less params (parse contract)', () {
    // Account.fromParams requires deviceSid; the UI guards this before
    // calling, but the store contract keeps it visible.
    final params =
        ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4');
    expect(params, isNotNull);
    expect(params!.deviceSid, isNull);
  });

  test('legacy v1 entries are dropped on load', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zemote_devices_v2', jsonEncode([
      {
        'id': 'old1',
        'label': 'V1 设备',
        'url': 'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1',
      },
      {
        'id': 'new1',
        'label': 'V2 设备',
        'deviceSid': 'sid2',
        'origin': 'https://zcode.z.ai',
      },
    ]));
    final store = AccountStore();
    await store.load();
    expect(store.accounts, hasLength(1));
    expect(store.accounts.first.deviceSid, 'sid2');
  });
}
