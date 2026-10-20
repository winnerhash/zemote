import 'package:flutter_test/flutter_test.dart';

import 'package:zemote/protocol/connection_params.dart';
import 'package:zemote/protocol/crc32.dart';
import 'package:zemote/protocol/ipc_codec.dart';
import 'package:zemote/protocol/conversation.dart';

void main() {
  test('Conversation V4 uses desktop protocol capability version', () {
    expect(conversationProtocolAppVersion, '3.6.5');
  });

  test('parse zemote v2 connection url', () {
    final params = ZemoteConnectionParams.parse(
      'https://zcode.z.ai/remote/v4?sid=SID123&mid=MID-1&name=DESKTOP&app_version=3.6.5',
    );
    expect(params, isNotNull);
    expect(params!.deviceSid, 'SID123');
    expect(params.deviceMid, 'MID-1');
    expect(params.deviceName, 'DESKTOP');
    expect(params.appVersion, '3.6.5');
    expect(
      params.relayWsUri(token: 'TOKEN').toString(),
      'wss://zcode.z.ai/api/v1/remote/ws2?token=TOKEN&mid=MID-1',
    );
  });

  test('reject invalid url', () {
    expect(ZemoteConnectionParams.parse('not a url'), isNull);
    expect(
      ZemoteConnectionParams.parse(
          'http://zcode.z.ai/remote/v4?sid=s'),
      isNull,
    );
  });

  test('reject legacy v1 credential urls', () {
    expect(
      ZemoteConnectionParams.parse(
          'https://zcode.z.ai/remote/v4?sid=s&hash=h&t=1'),
      isNull,
    );
    expect(
      ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?sid=s&t=1'),
      isNull,
    );
    expect(
      ZemoteConnectionParams.parse('https://zcode.z.ai/remote/v4?sid=s&hash=h'),
      isNull,
    );
  });

  test('crc32 known vector', () {
    expect(Crc32.hexOf('123456789'.codeUnits), 'cbf43926');
  });

  test('ipc value codec roundtrip', () {
    final writer = ValueWriter();
    encodeValue(writer, [100, 7, 'zcode-task', 'listTasks']);
    encodeValue(writer, [
      {'workspacePath': 'C:/proj', 'n': 42, 'ok': true, 's': '文本'}
    ]);
    final bytes = writer.toBytes();

    final reader = ValueReader(bytes);
    final header = decodeValue(reader) as List;
    expect(header, [100, 7, 'zcode-task', 'listTasks']);
    final args = decodeValue(reader) as List;
    expect(args, hasLength(1));
    final scope = args[0] as Map;
    expect(scope['workspacePath'], 'C:/proj');
    expect(scope['n'], 42);
    expect(scope['ok'], true);
    expect(scope['s'], '文本');
    expect(reader.remaining, 0);
  });

  test('ipc frame encode/parse roundtrip', () {
    final body = ValueWriter()..writeVarint(300);
    final frame = IpcFraming.encode(body.toBytes());
    final parser = IpcFrameParser();
    // split into two chunks to exercise incremental parsing
    final out1 = parser.acceptChunk(frame.sublist(0, 5));
    expect(out1, isEmpty);
    final out2 = parser.acceptChunk(frame.sublist(5));
    expect(out2, hasLength(1));
    final reader = ValueReader(out2[0]);
    expect(reader.readVarint(), 300);
  });
}
