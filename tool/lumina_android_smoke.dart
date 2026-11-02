import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/source/lumina/lumina_executor.dart';
import 'package:kazumi/services/source/source_models.dart';

/// 独立验收入口，正式 main.dart 不导入；不清理、重建或导出用户数据。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final rows = ValueNotifier<List<String>>([]);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: rows,
            builder: (_, value, _) =>
                ListView(children: [for (final row in value) Text(row)]),
          ),
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  void record(String text) {
    rows.value = [...rows.value, text];
    debugPrint('LUMINA_SMOKE $text');
  }

  Future<Map<String, dynamic>> call(
    String op,
    Map<String, dynamic> payload,
  ) async {
    final clock = Stopwatch()..start();
    final result = await executeLumina(op, payload, null);
    if (result['meta']['operation'] != op ||
        result['meta']['backend'] != 'dart-c')
      throw StateError('request routing');
    record(
      jsonEncode({
        'operation': op,
        'pass': true,
        'ms': clock.elapsedMilliseconds,
        'backend': result['meta']['backend'],
        'engine': result['meta']['engine'],
      }),
    );
    return Map<String, dynamic>.from(result['data'] as Map);
  }

  try {
    final support = await getApplicationSupportDirectory();
    final identity = File('${support.path}/lumina/device.json');
    if (await identity.exists()) {
      record(
        jsonEncode({
          'abi': Abi.current().toString(),
          'identitySha256': sha256
              .convert(await identity.readAsBytes())
              .toString(),
        }),
      );
    }
    await call('config', {});
    final channels = await call('channels', {}),
        channel = (channels['channels'] as List).first['id'];
    await call('banners', {'channelId': channel});
    final catalog = await call('catalog', {
      'channelId': channel,
      'pageSize': 6,
    });
    final video = (catalog['videos'] as List).first;
    await call('search', {'keyword': video['title'], 'pageSize': 5});
    final detail = await call('detail', {'videoId': video['id']});
    final road = (detail['parts'] as List).firstWhere(
      (dynamic r) => (r['episodes'] as List).isNotEmpty,
    );
    final play = await call('play', {
      'videoId': video['id'],
      'playFormat': road['play'],
      'part': road['episodes'][0]['part'],
    });
    if (play['status'] != 'ready') throw StateError('playback not ready');
    final http = HttpClient();
    try {
      final media = play['media'] as Map,
          request = await http.getUrl(Uri.parse(media['url']));
      (media['headers'] as Map).forEach(
        (k, v) => request.headers.set('$k', '$v'),
      );
      request.headers.set('range', 'bytes=0-16383');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final first = await response.first.timeout(const Duration(seconds: 10));
      if (response.statusCode != 206 ||
          !ascii
              .decode(first.take(64).toList(), allowInvalid: true)
              .contains('ftyp'))
        throw StateError('media probe');
      record(
        jsonEncode({
          'media': true,
          'status': response.statusCode,
          'mp4': true,
          'qualities': (play['medias'] as List).length,
        }),
      );
    } finally {
      http.close(force: true);
    }
    final cancel = CancelToken()..cancel();
    try {
      await executeLumina('channels', {}, cancel);
      throw StateError('cancel accepted');
    } on SourceException catch (e) {
      if (e.code != 'CANCELLED') rethrow;
    }
    final inFlightCancel = CancelToken();
    final cancelled = executeLumina('banners', {
      'channelId': channel,
    }, inFlightCancel);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    inFlightCancel.cancel();
    try {
      await cancelled;
      throw StateError('late cancel accepted');
    } on SourceException catch (e) {
      if (e.code != 'CANCELLED') rethrow;
    }
    final concurrent = await Future.wait([
      executeLumina('channels', {}, null),
      executeLumina('detail', {'videoId': video['id']}, null),
    ]);
    if (concurrent[0]['meta']['operation'] != 'channels' ||
        concurrent[1]['meta']['operation'] != 'detail')
      throw StateError('concurrent routing');
    record('PASS seven operations, media, cancellation, concurrent routing');
  } catch (error, stack) {
    record('FAIL ${error is SourceException ? error.code : error.runtimeType}');
    debugPrintStack(stackTrace: stack, maxFrames: 8);
  }
}
