import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:lumina_engine/client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3)
    throw ArgumentError('profile.json image.bin report.json');
  final profile = Map<String, dynamic>.from(
    jsonDecode(File(args[0]).readAsStringSync()),
  );
  final identity = File(
    '${File(args[2]).parent.path}/native-check-device.json',
  );
  if (!identity.existsSync()) {
    final random = Random.secure();
    identity.writeAsStringSync(
      jsonEncode({
        'deviceFingerprint': List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
      }),
    );
  }
  final fp =
      jsonDecode(identity.readAsStringSync())['deviceFingerprint'] as String;
  final client = LuminaClient(profile, args[1], fp);
  final report = <String, dynamic>{
    'backend': 'dart-c',
    'engine': client.engine.version,
    'operations': <String, dynamic>{},
  };
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final result = await client
          .call(name, payload)
          .timeout(const Duration(seconds: 30));
      (report['operations'] as Map)[name] = {
        'pass': true,
        'ms': watch.elapsedMilliseconds,
      };
      print('$name PASS ${watch.elapsedMilliseconds}ms');
      return result['data'] as Map<String, dynamic>;
    } catch (error) {
      (report['operations'] as Map)[name] = {
        'pass': false,
        'code': error is LuminaFailure
            ? error.code
            : error.runtimeType.toString(),
      };
      rethrow;
    } finally {
      File(
        args[2],
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
  }

  try {
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
    if (play['status'] != 'ready') throw StateError('PLAY_NOT_READY');
    report['mediaCount'] = (play['medias'] as List).length;
    final http = HttpClient();
    try {
      final media = play['media'] as Map,
          request = await http.getUrl(validatePublicUri(media['url']));
      (media['headers'] as Map).forEach(
        (k, v) => request.headers.set('$k', '$v'),
      );
      request.headers.set('range', 'bytes=0-16383');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final first = await response.first.timeout(const Duration(seconds: 10));
      report['mediaProbe'] = {
        'status': response.statusCode,
        'bytes': first.length,
        'mp4': ascii
            .decode(first.take(64).toList(), allowInvalid: true)
            .contains('ftyp'),
      };
    } finally {
      http.close(force: true);
    }
    try {
      await client.call('channels', {}, isCancelled: () => true);
      throw StateError('cancel not enforced');
    } on LuminaFailure catch (error) {
      if (error.code != 'CANCELLED') rethrow;
      report['cancelledBeforeHttp'] = true;
      print('pre-HTTP cancellation PASS');
    }
    try {
      await client.call(
        'channels',
        {},
        timeout: const Duration(milliseconds: 1),
      );
      throw StateError('deadline not enforced');
    } on LuminaFailure catch (error) {
      if (error.code != 'TIMEOUT') rethrow;
      report['budgetTimeout'] = true;
      print('request budget PASS');
    }
    File(
      args[2],
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  } finally {
    client.close();
  }
}
