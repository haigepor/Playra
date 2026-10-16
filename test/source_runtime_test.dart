import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/runtime/source_runtime.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

class RecordingExecutor implements RuleRequestExecutor {
  PreparedRuleRequest? received;
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    received = request;
    return '{}';
  }
}

void main() {
  final config = SourceDefinition.fromJson({
    'name': 'runtime-test',
    'api': '8',
  }).execution;
  Matcher code(String value) =>
      isA<SourceException>().having((e) => e.code, 'code', value);
  late HttpServer server;
  late SourceRuntimeClient runtime;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    runtime = SourceRuntimeClient(
      endpoint: 'http://127.0.0.1:${server.port}/v1/',
      allowInsecure: true,
      timeout: const Duration(milliseconds: 350),
    );
  });
  tearDown(() async {
    runtime.dispose();
    await server.close(force: true);
  });

  test(
    'native unconfigured and insecure endpoints fail before network',
    () async {
      final empty = SourceRuntimeClient(endpoint: '');
      final insecure = SourceRuntimeClient(endpoint: 'http://127.0.0.1:1/v1/');
      try {
        await expectLater(empty.health(), throwsA(code('RUNTIME_UNAVAILABLE')));
        await expectLater(insecure.health(), throwsA(code('INVALID_ARGUMENT')));
      } finally {
        empty.dispose();
        insecure.dispose();
      }
    },
  );
  test(
    'runtime routes cannot target scripts or use the wrong method',
    () async {
      await expectLater(
        runtime.request('../scripts/run'),
        throwsA(code('UNSUPPORTED')),
      );
      await expectLater(
        runtime.request('adapters/test/resolve'),
        throwsA(code('UNSUPPORTED')),
      );
    },
  );
  test('ordinary rules retain their original request', () async {
    final delegate = RecordingExecutor();
    final request = PreparedRuleRequest(
      method: 'GET',
      url: 'https://anime.example/search',
    );
    await SourceRuntimeExecutor(
      delegate,
      runtime: runtime,
    ).execute(request, config);
    expect(identical(delegate.received, request), true);
  });
  test('Lumina uses a fixed route and preserves opaque part and empty UA', () async {
    server.listen((req) async {
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/adapters/lumina/sdk');
      expect(jsonDecode(await utf8.decoder.bind(req).join()), {
        'operation': 'play',
        'payload': {
          'videoId': '18446744073709551616',
          'playFormat': 'mp4',
          'part': '特别篇·上',
        },
      });
      req.response.write(jsonEncode({
        'data': {
          'status': 'ready',
          'media': {
            'url': 'https://media.example/test.m3u8',
            'headers': {'User-Agent': ''},
          },
        },
      }));
      await req.response.close();
    });
    final result = await runtime.callLumina('play', payload: {
      'videoId': '18446744073709551616',
      'playFormat': 'mp4',
      'part': '特别篇·上',
    });
    expect(result['data']['media']['headers'], {'User-Agent': ''});
    await expectLater(
      runtime.request('adapters/unknown/sdk', method: 'POST'),
      throwsA(code('UNSUPPORTED')),
    );
  });
  test(
    'MioMedia SDK uses the fixed POST envelope and preserves string IDs',
    () async {
      server.listen((req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v1/adapters/miomedia/sdk');
        expect(jsonDecode(await utf8.decoder.bind(req).join()), {
          'operation': 'detail',
          'payload': {'videoId': '329257153645817856'},
        });
        req.response.write(
          jsonEncode({
            'data': {
              'video': {'id': '329257153645817856'},
            },
          }),
        );
        await req.response.close();
      });
      final result = await runtime.callMioMedia(
        'detail',
        payload: {'videoId': '329257153645817856'},
      );
      expect(result['data']['video']['id'], '329257153645817856');
      await expectLater(
        runtime.request('adapters/test/sdk', method: 'POST'),
        throwsA(code('UNSUPPORTED')),
      );
    },
  );
  test('runtime HTTP error survives the source engine wrapper', () async {
    server.listen((req) async {
      req.response.statusCode = 422;
      req.response.write(
        jsonEncode({
          'error': {'code': 'DECRYPT_ERROR', 'message': 'secret'},
        }),
      );
      await req.response.close();
    });
    final error = await runtime
        .request('adapters/test/search')
        .then<Object>(
          (_) => throw StateError('expected error'),
          onError: (Object e) => e,
        );
    expect(
      SourceService.mapError(
        SearchErrorException('test', cause: error),
        'test',
      ).code,
      'DECRYPT_ERROR',
    );
    expect(error.toString(), isNot(contains('secret')));
  });
  test('redirects do not become success or initiate another request', () async {
    server.listen((req) async {
      req.response.statusCode = 302;
      req.response.headers.set('location', 'http://127.0.0.1:1/');
      req.response.write('{}');
      await req.response.close();
    });
    await expectLater(runtime.health(), throwsA(code('RUNTIME_ERROR')));
  });
  test('total timeout bounds a waiting response', () async {
    server.listen((_) {});
    await expectLater(runtime.health(), throwsA(code('TIMEOUT')));
  });
  test('caller cancellation stops a waiting request', () async {
    server.listen((_) {});
    final cancel = CancelToken();
    final result = runtime.health(cancelToken: cancel);
    final assertion = expectLater(result, throwsA(code('CANCELLED')));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancel.cancel();
    await assertion;
  });
  test('malformed and oversized responses fail explicitly', () async {
    var counter = 0;
    server.listen((req) async {
      req.response.write(
        counter++ == 0 ? '<html>broken</html>' : 'x' * (2 * 1024 * 1024 + 1),
      );
      try {
        await req.response.close();
      } catch (_) {}
    });
    await expectLater(runtime.health(), throwsA(code('PARSE_ERROR')));
    await expectLater(runtime.health(), throwsA(code('PARSE_ERROR')));
  });
  test('oversized body and cancelled token never send a request', () async {
    await expectLater(
      runtime.request(
        'adapters/test/resolve',
        method: 'POST',
        body: {'episodeUrl': 'x' * 33000},
      ),
      throwsA(code('INVALID_ARGUMENT')),
    );
    final cancel = CancelToken()..cancel();
    await expectLater(
      runtime.health(cancelToken: cancel),
      throwsA(code('CANCELLED')),
    );
  });
}
