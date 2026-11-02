import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lumina_engine/client.dart';
import 'package:lumina_engine/core_backend.dart';
import 'package:lumina_engine/primitives.dart';
import 'package:lumina_engine/response_backend.dart';
import 'package:lumina_engine/response_context.dart';

/// 独立验收入口：密文和设备身份只在内存使用，不输出请求头或播放地址。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('C backend comparison'))),
    ),
  );
  final support = await getApplicationSupportDirectory();
  final manifest =
      jsonDecode(
            await rootBundle.loadString('packages/lumina_engine/inputs.json'),
          )
          as Map;
  final profile =
      jsonDecode(
            await rootBundle.loadString('assets/lumina_private/profile.json'),
          )
          as Map<String, dynamic>;
  final fp =
      jsonDecode(
            await File('${support.path}/lumina/device.json').readAsString(),
          )['deviceFingerprint']
          as String;
  final image =
      '${support.path}/lumina/native-data/image-${(manifest['imageSha256'] as String).substring(0, 16)}.bin';
  try {
    final result = await Isolate.run(
      () => compare(profile, fp, image, '${support.path}/lumina/core-data'),
    );
    final external = await getExternalStorageDirectory();
    if (external == null) throw StateError('REPORT_DIRECTORY');
    await File(
      '${external.path}/lumina-core-benchmark.json',
    ).writeAsString(jsonEncode(result), flush: true);
    // Android 日志可能截断长行；完整样本落到独立诊断文件，日志仅输出分位数。
    debugPrint(
      'LUMINA_CORE_COMPARE ${jsonEncode({
        'pass': result['pass'],
        'abi': result['abi'],
        'samePlaintext': result['samePlaintext'],
        for (final key in ['fuseFreshKey', 'fuseCachedKey', 'core']) key: {'p50Ms': result[key]['p50Ms'], 'p95Ms': result[key]['p95Ms']},
      })}',
    );
  } catch (error) {
    debugPrint(
      'LUMINA_CORE_COMPARE ${jsonEncode({'pass': false, 'error': error is LuminaFailure
          ? error.code
          : error is ResponseBackendFailure
          ? error.code
          : '${error.runtimeType}'})}',
    );
  }
}

Future<Map<String, dynamic>> compare(
  Map<String, dynamic> p,
  String fp,
  String image,
  String files,
) async {
  final cold = Stopwatch()..start();
  final core = CoreResponseBackend.open(p, fp, files);
  final initMs = cold.elapsedMicroseconds / 1000;
  final fuse = LuminaClient(p, image, fp);
  final direct = LuminaClient(
    p,
    image,
    fp,
    responseBackend: core,
    strictResponseBackend: true,
  );
  final operations = <Map<String, dynamic>>[];
  Future<Map> call(String operation, Map<String, dynamic> payload) async {
    final clock = Stopwatch()..start();
    final result = await direct.call(operation, payload);
    if (result['meta']['responseBackend'] != 'core') {
      throw StateError('UNEXPECTED_RESPONSE_BACKEND');
    }
    operations.add({
      'operation': operation,
      'ms': clock.elapsedMicroseconds / 1000,
      'backend': 'core',
    });
    return result['data'] as Map;
  }

  await call('config', {});
  final channels = await call('channels', {});
  final channel = channels['channels'][0]['id'];
  await call('banners', {'channelId': channel});
  final catalog = await call('catalog', {'channelId': channel, 'pageSize': 1});
  final id = catalog['videos'][0]['id'];
  await call('search', {
    'keyword': catalog['videos'][0]['title'],
    'pageSize': 1,
  });
  final detail = await call('detail', {'videoId': id});
  final road = (detail['parts'] as List).firstWhere(
    (r) => (r['episodes'] as List).isNotEmpty,
  );
  final play = await call('play', {
    'videoId': id,
    'playFormat': road['play'],
    'part': road['episodes'][0]['part'],
  });
  if (play['status'] != 'ready') throw StateError('PLAY_NOT_READY');
  const path = '/app/video/detail';
  final now = DateTime.now().millisecondsSinceEpoch;
  final seed =
      '${p['CODE_VERSION']}-$now-Android-${p['APP_VERSION']}-$fp-${p['CLIENT_CATEGORY']}';
  final authentication = cb64(
    fuse.engine.auth(
      hexBytes(p['_AUTH_KEY']),
      hexBytes(p['_AUTH_IV']),
      ascii.encode(cb64(ascii.encode(seed))),
    ),
  );
  final http = HttpClient();
  final responseUri = Uri(
    scheme: 'http',
    host: p['API_HOST'],
    port: p['API_PORT'],
    path: path,
    queryParameters: {'id': '$id'},
  );
  late Uint8List raw;
  try {
    final request = await http.getUrl(responseUri);
    for (final entry in {
      'appid': '${p['APP_ID']}',
      'ts': '$now',
      'nonce': '${10000000 + Random.secure().nextInt(90000000)}',
      'tcs': '${p['TCS']}',
      'x-version': '${p['PROTOCOL_X_VERSION']}',
      'authentication': authentication,
      'content-type': 'application/json; charset=utf-8',
      'user-agent': '${p['USER_AGENT']}',
    }.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw StateError('HTTP_${response.statusCode}');
    final body = BytesBuilder();
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      body.add(chunk);
      if (body.length > maxResponseBytes)
        throw StateError('RESPONSE_TOO_LARGE');
    }
    raw = body.takeBytes();
  } finally {
    http.close(force: true);
  }
  if (splitEnvelope(utf8.decode(raw)) == null)
    throw StateError('EXPECTED_ENCRYPTED_ENVELOPE');
  final contextPath = luminaResponsePath(responseUri);
  final expected = jsonEncode(fuse.openBody(raw, path: contextPath));
  if (jsonEncode(direct.openBody(raw, path: contextPath)) != expected)
    throw StateError('PLAINTEXT_MISMATCH');
  List<double> sample(LuminaClient client, {bool clear = false}) =>
      List.generate(20, (_) {
        if (clear) client.engine.clearCalibrationCache();
        final clock = Stopwatch()..start();
        final value = client.openBody(raw, path: contextPath);
        final ms = clock.elapsedMicroseconds / 1000;
        if (jsonEncode(value) != expected)
          throw StateError('PLAINTEXT_MISMATCH');
        return ms;
      });
  Map<String, dynamic> stats(List<double> values) {
    final sorted = values.toList()..sort();
    return {'p50Ms': sorted[9], 'p95Ms': sorted[18], 'samplesMs': values};
  }

  final fresh = sample(fuse, clear: true);
  final cached = sample(fuse);
  final native = sample(direct);
  return {
    'pass': true,
    'abi': '${Abi.current()}',
    'coreVersion': core.version,
    'coreInitializeMs': initMs,
    'envelopeBytes': raw.length,
    'samplesPerGroup': 20,
    'samePlaintext': true,
    'operations': operations,
    'fuseFreshKey': stats(fresh),
    'fuseCachedKey': stats(cached),
    'core': stats(native),
  };
}
