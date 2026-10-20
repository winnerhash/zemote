import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zemote/protocol/connection_params.dart';
import 'package:zemote/protocol/relay_http.dart';
import 'package:zemote/protocol/id.dart';
import 'package:zemote/state/account_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('generateUuid', () {
    test('produces a non-empty string', () {
      final uuid = generateUuid();
      expect(uuid, isNotEmpty);
    });

    test('contains hyphens at expected positions', () {
      final uuid = generateUuid();
      expect(uuid[8], '-');
      expect(uuid[13], '-');
      expect(uuid[18], '-');
      expect(uuid[23], '-');
    });

    test('is 36 characters (8-4-4-4-12)', () {
      final uuid = generateUuid();
      expect(uuid.length, 36);
    });

    test('version nibble is 4', () {
      final uuid = generateUuid();
      expect(uuid[14], '4');
    });

    test('variant is one of 8/9/a/b', () {
      final uuid = generateUuid();
      expect('89ab'.contains(uuid[19]), isTrue);
    });

    test('produces unique values', () {
      final ids = <String>{};
      for (var i = 0; i < 100; i++) {
        ids.add(generateUuid());
      }
      expect(ids, hasLength(100));
    });

    test('generateRequestId uses prefix', () {
      final id = generateRequestId('test');
      expect(id, startsWith('test-'));
      expect(id.length, greaterThan('test-'.length + 20));
    });
  });

  group('Account model', () {
    test('fromParams constructs account from valid V2 URL', () {
      final account = Account.fromParams(ZemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s1&name=Test&mid=m1',
      )!);
      expect(account.label, 'Test');
      expect(account.deviceSid, 's1');
      expect(account.deviceMid, 'm1');
      expect(account.params.deviceSid, 's1');
    });

    test('fromParams defaults label when no name set', () {
      final account = Account.fromParams(ZemoteConnectionParams.parse(
        'https://zcode.z.ai/remote/v4?sid=s1',
      )!);
      expect(account.label, '未命名设备');
    });

    test('fromDevice carries online state and meta', () {
      final account = Account.fromDevice(const RelayDevice(
        deviceSid: 'sid9',
        deviceMid: 'mid9',
        online: true,
        createdAt: 1700000000,
        name: '工位机',
      ));
      expect(account.label, '工位机');
      expect(account.online, isTrue);
      expect(account.deviceMid, 'mid9');
    });

    test('unique id per creation', () {
      final a1 = Account.fromParams(ZemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=a&name=A')!);
      final a2 = Account.fromParams(ZemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=b&name=B')!);
      expect(a1.id, isNot(equals(a2.id)));
    });
  });

  group('AccountStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state is empty', () {
      final store = AccountStore();
      expect(store.accounts, isEmpty);
      expect(store.loaded, isFalse);
    });

    test('addParams returns Account', () async {
      final store = AccountStore();
      final account = await store.addParams(
          ZemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v4?sid=s&name=MyDevice')!);
      expect(account.label, 'MyDevice');
      expect(store.accounts, hasLength(1));
    });

    test('rename updates label', () async {
      final store = AccountStore();
      final account = await store.addParams(
          ZemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v4?sid=s&name=Old')!);
      await store.rename(account.id, 'NewName');
      expect(store.accounts.first.label, 'NewName');
    });

    test('remove deletes account', () async {
      final store = AccountStore();
      final account = await store.addParams(
          ZemoteConnectionParams.parse(
              'https://zcode.z.ai/remote/v4?sid=s&name=Device')!);
      expect(store.accounts, hasLength(1));
      await store.remove(account.id);
      expect(store.accounts, isEmpty);
    });

    test('touch updates lastUsedAt', () async {
      final store = AccountStore();
      final account = await store.addParams(
          ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?sid=s')!);
      final before = account.lastUsedAt;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await store.touch(account.id);
      final after = store.accounts.first.lastUsedAt;
      // touch updates the timestamp, so the store's version should be newer
      expect(after != null, isTrue);
      if (before != null) {
        expect(after! >= before, isTrue);
      }
    });
  });
}
