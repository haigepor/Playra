import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/source/runtime/source_runtime.dart';
import 'package:kazumi/services/source/source_models.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Pass an installed Python executable');
  }
  final state = await Directory.systemTemp.createTemp('playra-mio-http-');
  final python = await Process.start(
    args.single,
    ['-B', '-X', 'utf8', 'tool/source_runtime/server.py', '--port', '0'],
    environment: {'PLAYRA_MIOMEDIA_STATE_DIR': state.path},
  );
  python.stderr.transform(utf8.decoder).listen((_) {});
  Process? node;
  final probe = Dio();
  final clients = <SourceRuntimeClient>[];
  var checks = 0;
  void check(bool ok, String message) {
    if (!ok) throw StateError(message);
    checks++;
  }

  try {
    final ready = await python.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 8));
    final base = Uri.parse(ready.split(' ').last);
    final reservation = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservation.port;
    await reservation.close(force: true);
    node = await Process.start(
      'node',
      ['tool/web_backend/server.cjs'],
      environment: {
        'KAZUMI_WEB_PORT': '$port',
        'PLAYRA_SOURCE_RUNTIME_PORT': '${base.port}',
      },
    );
    node.stdout.transform(utf8.decoder).listen((_) {});
    node.stderr.transform(utf8.decoder).listen((_) {});
    var readyWeb = false;
    for (var i = 0; i < 40; i++) {
      try {
        await probe.get<Object>(
          'http://127.0.0.1:$port/api/health',
          options: Options(receiveTimeout: const Duration(milliseconds: 200)),
        );
        readyWeb = true;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    check(readyWeb, 'Web bridge did not start');
    for (final endpoint in [
      base.toString(),
      'http://127.0.0.1:$port/api/runtime/v1/',
    ]) {
      final client = SourceRuntimeClient(
        endpoint: endpoint,
        allowInsecure: true,
      );
      clients.add(client);
      check((await client.health())['apiVersion'] == '1', 'runtime protocol');
      final result = await client.callMioMedia('recommend');
      final videos = result['data']['guessYouLike']['videos'] as List;
      check(
        videos.isNotEmpty && videos.first['id'] is String,
        'actual content and string IDs',
      );
      check(result['meta']['providerId'] == 'miomedia', 'source identity');
      final identity = await File('${state.path}/device.json').readAsBytes();
      for (var episode = 1; episode <= 2; episode++) {
        final playback = await client.callMioMedia(
          'play',
          payload: {
            'videoId': '318186806611144716',
            'code': 'dym3u8',
            'episodeNum': episode,
            'caps': <String>[],
          },
        );
        final data = playback['data'] as Map;
        check(data['status'] == 'ready', 'actual credential playback');
        check(
          data['strategy'] == 'token' &&
              data['rotated'] == false &&
              data['rotations'] == 0,
          'persistent identity strategy',
        );
        check(
          !jsonEncode(playback).contains('adToken') &&
              !jsonEncode(playback).contains('deviceSecret'),
          'private materials must remain in service',
        );
      }
      check(
        base64Encode(identity) ==
            base64Encode(await File('${state.path}/device.json').readAsBytes()),
        'identity preserved through HTTP playback',
      );
      try {
        await client.callMioMedia('auth/login');
        throw StateError('unsupported write was accepted');
      } on SourceException catch (error) {
        check(error.code == 'UNSUPPORTED', 'write rejection preserved');
      }
    }
    stdout.writeln(
      'PASS: $checks native + Web bridge + actual MioMedia SDK checks',
    );
  } finally {
    for (final client in clients) {
      client.dispose();
    }
    probe.close(force: true);
    node?.kill();
    python.kill();
    if (node != null) await node.exitCode;
    await python.exitCode;
    // 只清理本次创建的隔离目录，先检查绝对路径仍位于系统临时目录。
    final temporaryRoot =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}';
    if (state.absolute.path.startsWith(temporaryRoot) &&
        state.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last
            .startsWith('playra-mio-http-')) {
      await state.delete(recursive: true);
    }
  }
}
