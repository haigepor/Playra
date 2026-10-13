import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/runtime/source_runtime.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

class RejectNetwork implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) => throw StateError('runtime request escaped to normal network');
}

Future<void> main(List<String> args) async {
  if (args.length != 1)
    throw ArgumentError('Pass an installed Python 3 executable path');
  final python = await Process.start(args.single, [
    '-X',
    'utf8',
    'tool/source_runtime/integration_fixture.py',
  ], workingDirectory: Directory.current.path);
  final pythonErrors = <String>[];
  python.stderr.transform(utf8.decoder).listen(pythonErrors.add);
  Process? node;
  final clients = <SourceRuntimeClient>[];
  final webErrors = <String>[];
  final probe = Dio();
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  Future<void> expectCode(Future<Object?> action, String code) async {
    try {
      await action;
      throw StateError('expected $code');
    } on SourceException catch (error) {
      check(error.code == code, 'expected $code, got ${error.code}');
    }
  }

  try {
    final ready = await python.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 8));
    final pythonPort = (jsonDecode(ready) as Map)['port'] as int;
    final reservation = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final webPort = reservation.port;
    await reservation.close(force: true);
    node = await Process.start(
      'node',
      ['tool/web_backend/server.cjs'],
      environment: {
        'KAZUMI_WEB_PORT': '$webPort',
        'PLAYRA_SOURCE_RUNTIME_PORT': '$pythonPort',
      },
      workingDirectory: Directory.current.path,
    );
    node.stdout.transform(utf8.decoder).listen((_) {});
    node.stderr.transform(utf8.decoder).listen(webErrors.add);
    var webReady = false;
    for (var i = 0; i < 40; i++) {
      try {
        await probe.get<Object>(
          'http://127.0.0.1:$webPort/api/health',
          options: Options(receiveTimeout: const Duration(milliseconds: 200)),
        );
        webReady = true;
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    check(webReady, 'Web bridge did not start');
    final text = await File(
      'tool/source_runtime/example-rule.json',
    ).readAsString(encoding: utf8);
    final fixture = SourceDefinition.fromJson(
      jsonDecode(text.replaceAll('/template/', '/fixture/'))
          as Map<String, dynamic>,
    );
    final template = SourceDefinition.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
    for (final endpoint in [
      'http://127.0.0.1:$pythonPort/v1/',
      'http://127.0.0.1:$webPort/api/runtime/v1/',
    ]) {
      final runtime = SourceRuntimeClient(
        endpoint: endpoint,
        allowInsecure: true,
      );
      clients.add(runtime);
      check((await runtime.health())['apiVersion'] == '1', 'health protocol');
      final service = SourceService(
        engine: RuleEngine(
          requestExecutor: SourceRuntimeExecutor(
            RejectNetwork(),
            runtime: runtime,
          ),
          logFailures: false,
        ),
      );
      final first = await service.search(fixture, 'test', page: 1);
      final second = await service.search(fixture, 'test', page: 2);
      check(first.items.single.title == '仅测试电影 1', 'search title');
      check(
        first.pagination.hasMore == true &&
            second.pagination.hasMore == false &&
            second.pagination.mode == 'upstream',
        'upstream pagination',
      );
      check(
        first.items.single.classification.kind == 'movie',
        'declared domain classification',
      );
      final lines = await service.lines(fixture, first.items.single.ref);
      check(
        lines.single.name == '测试原始线路' &&
            lines.single.episodes.map((e) => e.title).join('|') ==
                '第12集|SP|第11集',
        'original labels/order',
      );
      final media = await service.resolveApi(
        fixture,
        lines.single.episodes.first.pageUrl,
      );
      check(
        media?.format == 'hls' &&
            media?.headers['Referer'] == 'https://source.example.com/' &&
            media?.expiresAt?.isAfter(DateTime.now()) == true,
        'resolve media context',
      );
      check(
        (await service.search(fixture, 'empty')).items.isEmpty,
        'empty result is success',
      );
      await expectCode(service.search(template, 'test'), 'UNSUPPORTED');
      await expectCode(
        service.search(fixture, 'decrypt-error'),
        'DECRYPT_ERROR',
      );
      final cancel = CancelToken();
      final result = service.search(
        fixture,
        'slow',
        context: SourceContext(cancelToken: cancel),
      );
      final cancelled = expectCode(result, 'CANCELLED');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      cancel.cancel();
      await cancelled;
    }
    stdout.writeln(
      'PASS: $checks native HTTP + Web bridge + Python + actual RuleEngine checks',
    );
  } finally {
    for (final client in clients) {
      client.dispose();
    }
    probe.close(force: true);
    node?.kill();
    python.kill();
    await python.exitCode.timeout(const Duration(seconds: 4));
    if (node != null) await node.exitCode.timeout(const Duration(seconds: 4));
    if (pythonErrors.isNotEmpty) stderr.writeln(pythonErrors.join());
    if (webErrors.isNotEmpty) stderr.writeln(webErrors.join());
  }
}
