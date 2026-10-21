// Standalone Relay V2 handshake debugger: dumps every raw frame.
// Usage: dart run tool/ws_debug.dart <jwt> <sid> [mid]
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:zemote/protocol/relay_http.dart';

Future<void> main(List<String> args) async {
  final jwt = args[0];
  final sid = args[1];
  final mid = args.length > 2 ? args[2] : null;

  final relay = RelayHttpClient();
  final token = await relay.fetchToken(jwt, role: 'terminal');
  print('token: ${token.length} chars');

  final uri = Uri(
    scheme: 'wss',
    host: 'zcode.z.ai',
    path: '/api/v1/remote/ws2',
    queryParameters: {'token': token, if (mid != null) 'mid': mid},
  );
  print('ws: $uri (token redacted below)');
  final ws = WebSocketChannel.connect(uri);
  await ws.ready;
  print('ws OPEN');

  final sub = ws.stream.listen(
    (data) => print('<< $data'),
    onError: (e) => print('!! error: $e'),
    onDone: () => print(
        '!! closed code=${ws.closeCode} reason=${ws.closeReason}'),
  );

  void send(Map<String, dynamic> m) {
    print('>> ${jsonEncode(m)}');
    ws.sink.add(jsonEncode(m));
  }

  send({
    'type': 'auth_init',
    'device_sid': sid,
    'meta': {'platform': 'windows', 'version': '3.16.2', 'name': 'zemote-debug'},
    'client_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  });

  var tick = 0;
  late final Timer timer;
  timer = Timer.periodic(const Duration(seconds: 5), (_) {
    tick++;
    send({'type': 'pair_status_query', 'client_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000});
    if (tick >= 6) {
      timer.cancel();
      sub.cancel();
      ws.sink.close();
      print('done');
      exit(0);
    }
  });
}
