import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:developer' show Timeline;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lumina_engine/client.dart';
import 'package:lumina_engine/core_backend.dart';
import 'package:lumina_engine/response_backend.dart';
import '../source_models.dart';
import 'lumina_work_scheduler.dart';

final _host = _NativeLuminaHost();
final _scheduler = LuminaWorkScheduler();
Future<Map<String, dynamic>> executeLumina(
  String operation,
  Map<String, dynamic> payload,
  CancelToken? cancel,
) async {
  if (!luminaSupported)
    throw const SourceException('PLATFORM_UNSUPPORTED', '当前平台尚无动漫引擎');
  try {
    if (cancel?.isCancelled == true)
      throw const SourceException('CANCELLED', '请求已取消');
    validatePayload(operation, payload);
    return await _scheduler.run(
      (token) => _host.call(operation, payload, token),
      background: Zone.current[#luminaBackground] == true,
      cancel: cancel,
    );
  } on LuminaFailure catch (error) {
    throw SourceException(error.code, '动漫请求参数无效');
  } on SourceException catch (error) {
    if (AppBuildPolicy.developerTools) {
      debugPrint(
        'PLAYRA_LUMINA ${jsonEncode({'stage': 'request_failure', 'operation': operation, 'code': error.code})}',
      );
    }
    rethrow;
  } on TimeoutException {
    throw const SourceException('TIMEOUT', '动漫请求超时');
  } on FileSystemException {
    throw const SourceException('SDK_RESOURCE_MISSING', '动漫资源不可用');
  } on FormatException {
    throw const SourceException('SDK_INTEGRITY_ERROR', '动漫资源校验失败');
  } catch (_) {
    throw const SourceException('ENGINE_UNAVAILABLE', '动漫引擎不可用');
  }
}

class _NativeLuminaHost {
  Future<SendPort>? _startup;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final ReceivePort _messages = ReceivePort();
  int _sequence = 0;
  bool _dead = false;
  _NativeLuminaHost() {
    _messages.listen((dynamic message) {
      if (message is! Map || message['id'] is! int) return;
      if (message['trace'] is Map) {
        if (AppBuildPolicy.developerTools) {
          debugPrint('PLAYRA_LUMINA ${jsonEncode(message['trace'])}');
        }
        return;
      }
      final pending = _pending.remove(message['id']);
      if (pending == null) return; // 已取消/超时的结果不能被后续请求消费。
      if (message['error'] case final String code) {
        pending.completeError(SourceException(code, '动漫来源暂时不可用'));
      } else {
        pending.complete(Map<String, dynamic>.from(message['result'] as Map));
      }
    });
  }
  Future<SendPort> _start() async {
    final manifest =
        jsonDecode(
              await rootBundle.loadString('packages/lumina_engine/inputs.json'),
            )
            as Map;
    final profileBytes = (await rootBundle.load(
      'assets/lumina_private/profile.json',
    )).buffer.asUint8List();
    if (sha256.convert(profileBytes).toString() !=
        manifest['assets']['profile.json']) {
      throw const SourceException('SDK_INTEGRITY_ERROR', '动漫资源校验失败');
    }
    final profile = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(profileBytes)),
    );
    final support = await getApplicationSupportDirectory();
    // Android 的 applicationSupportDirectory 为 filesDir，复用原安装持久身份。
    final identity = File('${support.path}/lumina/device.json');
    await identity.parent.create(recursive: true);
    if (!await identity.exists()) {
      final random = Random.secure();
      final fingerprint = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final scratch = File('${identity.path}.native-new');
      await scratch.writeAsString(
        jsonEncode({'deviceFingerprint': fingerprint}),
        flush: true,
      );
      await scratch.rename(identity.path);
    }
    if (await identity.length() > 4096) {
      throw const SourceException('IDENTITY_ERROR', '设备身份异常');
    }
    final fp = jsonDecode(await identity.readAsString())['deviceFingerprint'];
    if (fp is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(fp)) {
      throw const SourceException('IDENTITY_ERROR', '设备身份异常');
    }
    final directory = Directory('${support.path}/lumina/native-data');
    await directory.create(recursive: true);
    final image = File(
      '${directory.path}/image-${(manifest['imageSha256'] as String).substring(0, 16)}.bin',
    );
    if (!await image.exists()) {
      final bytes = (await rootBundle.load(
        'assets/lumina_private/fuse_image.bin.gz',
      )).buffer.asUint8List();
      if (sha256.convert(bytes).toString() !=
          manifest['assets']['fuse_image.bin.gz']) {
        throw const SourceException('SDK_INTEGRITY_ERROR', '动漫资源校验失败');
      }
      final compressed = File('${image.path}.gz');
      await compressed.writeAsBytes(bytes, flush: true);
      if (!await _checkImageInWorker(
        image.path,
        manifest['imageSha256'] as String,
        compressed.path,
      )) {
        throw const SourceException('SDK_INTEGRITY_ERROR', '动漫资源校验失败');
      }
    } else {
      final valid = await _checkImageInWorker(
        image.path,
        manifest['imageSha256'] as String,
        null,
      );
      if (!valid) {
        throw const SourceException('SDK_INTEGRITY_ERROR', '动漫资源校验失败');
      }
    }
    final coreDirectory = Directory('${support.path}/lumina/core-data');
    await coreDirectory.create(recursive: true);
    var mode = const String.fromEnvironment(
      'LUMINA_RESPONSE_BACKEND',
      defaultValue: 'auto',
    );
    if (!['auto', 'fuse', 'core'].contains(mode)) mode = 'auto';
    // 仅诊断包读取固定枚举；正式包不允许外部文件改变解密后端。
    if (AppBuildPolicy.developerTools && Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final file = File('${external.path}/lumina-backend.txt');
        if (await file.exists() && await file.length() <= 16) {
          final value = (await file.readAsString()).trim();
          if (['auto', 'fuse', 'core'].contains(value)) mode = value;
        }
      }
    }
    final ready = ReceivePort(), errors = ReceivePort(), exit = ReceivePort();
    void failed() {
      _dead = true;
      for (final pending in _pending.values) {
        pending.completeError(
          const SourceException('ENGINE_UNAVAILABLE', '动漫引擎不可用'),
        );
      }
      _pending.clear();
    }

    errors.listen((_) => failed());
    exit.listen((_) => failed());
    await Isolate.spawn(
      _worker,
      [
        ready.sendPort,
        _messages.sendPort,
        profile,
        image.path,
        fp,
        coreDirectory.path,
        mode,
      ],
      onError: errors.sendPort,
      onExit: exit.sendPort,
      errorsAreFatal: true,
    );
    final dynamic result = await ready.first.timeout(
      const Duration(seconds: 30),
    );
    ready.close();
    if (result is! SendPort) {
      _dead = true;
      throw const SourceException('ENGINE_UNAVAILABLE', '动漫引擎不可用');
    }
    return result;
  }

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> payload,
    CancelToken? cancel,
  ) async {
    final deadline = Timeline.now + const Duration(seconds: 30).inMicroseconds;
    Future<T> wait<T>(Future<T> work) =>
        Future.any<T>([
          work,
          if (cancel != null)
            cancel.whenCancel.then<T>(
              (_) => throw const SourceException('CANCELLED', '请求已取消'),
            ),
        ]).timeout(
          Duration(microseconds: (deadline - Timeline.now).clamp(1, 30000000)),
          onTimeout: () => throw const SourceException('TIMEOUT', '动漫请求超时'),
        );
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    if (_dead) throw const SourceException('ENGINE_UNAVAILABLE', '动漫引擎不可用');
    if (_pending.length >= 16) throw const SourceException('BUSY', '动漫请求繁忙');
    final port = await wait(_startup ??= _start());
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    if (_dead) throw const SourceException('ENGINE_UNAVAILABLE', '动漫引擎不可用');
    if (_pending.length >= 16) throw const SourceException('BUSY', '动漫请求繁忙');
    final id = ++_sequence, completion = Completer<Map<String, dynamic>>();
    _pending[id] = completion;
    port.send({
      'id': id,
      'operation': operation,
      'payload': payload,
      'deadline': deadline,
      'queued': Timeline.now,
    });

    try {
      return await wait(completion.future);
    } finally {
      if (_pending.remove(id) != null) port.send({'cancel': id});
    }
  }
}

// 独立函数只捕获字符串，避免实例方法的闭包上下文携带 ReceivePort 跨 isolate。
Future<bool> _checkImageInWorker(
  String path,
  String expected,
  String? compressed,
) => Isolate.run(() => _checkImage(path, expected, compressed));
Future<bool> _checkImage(
  String path,
  String expected,
  String? compressed,
) async {
  if (compressed == null)
    return (await sha256.bind(File(path).openRead()).first).toString() ==
        expected;
  final scratch = File('$path.part');
  await gzip.decoder
      .bind(File(compressed).openRead())
      .pipe(scratch.openWrite());
  if ((await sha256.bind(scratch.openRead()).first).toString() != expected) {
    await scratch.delete();
    return false;
  }
  await scratch.rename(path);
  await File(compressed).delete();
  return true;
}

void _worker(List<dynamic> arguments) {
  final ready = arguments[0] as SendPort, replies = arguments[1] as SendPort;
  try {
    final initClock = Stopwatch()..start();
    void trace(String stage, int micros) {
      if (AppBuildPolicy.developerTools) {
        replies.send({
          'id': Zone.current['requestId'] ?? 0,
          'trace': {
            'stage': stage,
            'ms': micros / 1000,
            'backend': stage == 'backend_core'
                ? 'core'
                : stage == 'backend_fuse'
                ? 'fuse'
                : 'dart-c',
            'operation': Zone.current['operation'] ?? 'initialize',
            'requestId': Zone.current['requestId'] ?? 0,
          },
        });
      }
    }

    final profile = Map<String, dynamic>.from(arguments[2] as Map);
    final mode = arguments[6] as String;
    CoreResponseBackend? core;
    if (mode != 'fuse' && CoreResponseBackend.supported) {
      final clock = Stopwatch()..start();
      try {
        core = CoreResponseBackend.open(
          profile,
          arguments[4] as String,
          arguments[5] as String,
        );
      } on ResponseBackendFailure catch (error) {
        trace('fallback_${error.code}', 0);
        if (mode == 'core') rethrow;
      } finally {
        trace('core_initialize', clock.elapsedMicroseconds);
      }
    } else if (mode == 'core') {
      throw const ResponseBackendFailure('CORE_UNSUPPORTED', terminal: true);
    }
    final client = LuminaClient(
      profile,
      arguments[3] as String,
      arguments[4] as String,
      responseBackend: core,
      strictResponseBackend: mode == 'core',
      trace: trace,
    );
    if (AppBuildPolicy.developerTools)
      replies.send({
        'id': 0,
        'trace': {
          'stage': 'initialize',
          'ms': initClock.elapsedMilliseconds,
          'backend': 'dart-c',
          'engine': client.engine.version,
          'responseBackend': core == null ? 'fuse' : 'core',
          if (core != null) 'coreVersion': core.version,
        },
      });
    final requests = ReceivePort();
    final running = <int>{}, cancelled = <int>{};
    var active = 0;
    requests.listen((dynamic raw) async {
      final message = raw as Map;
      if (message['cancel'] case final int cancelledId) {
        if (running.contains(cancelledId)) cancelled.add(cancelledId);
        return;
      }
      final id = message['id'] as int;
      final remaining = (message['deadline'] as int) - Timeline.now;
      if (remaining <= 0) {
        replies.send({'id': id, 'error': 'TIMEOUT'});
        return;
      }
      if (AppBuildPolicy.developerTools)
        replies.send({
          'id': id,
          'trace': {
            'stage': 'queue',
            'ms': (Timeline.now - (message['queued'] as int)) / 1000,
            'backend': 'dart-c',
            'operation': message['operation'],
          },
        });
      if (active >= 16) {
        replies.send({'id': id, 'error': 'BUSY'});
        return;
      }
      active++;
      running.add(id);
      try {
        final result = await runZoned(
          () => client.call(
            message['operation'] as String,
            Map<String, dynamic>.from(message['payload'] as Map),
            timeout: Duration(microseconds: remaining),
            isCancelled: () => cancelled.contains(id),
          ),
          zoneValues: {'requestId': id, 'operation': message['operation']},
        );
        replies.send({'id': id, 'result': result});
      } catch (error) {
        replies.send({
          'id': id,
          'error': error is LuminaFailure ? error.code : 'ENGINE_ERROR',
        });
      } finally {
        running.remove(id);
        cancelled.remove(id);
        active--;
      }
    });
    ready.send(requests.sendPort);
  } catch (_) {
    ready.send('ENGINE_UNAVAILABLE');
  }
}
