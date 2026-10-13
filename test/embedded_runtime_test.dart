import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/runtime/embedded_runtime.dart';
import 'package:kazumi/services/source/runtime/source_runtime.dart';
import 'package:kazumi/services/source/source_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.predidit.kazumi/source-runtime');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'unconfigured native request uses embedded JSON instead of an external URL',
    () async {
      final runtime = SourceRuntimeClient(
        endpoint: '',
        embeddedRequest: (request, budget, cancelled) async {
          expect(request['path'], 'health');
          return jsonEncode({
            'data': {'embedded': true},
          });
        },
      );
      expect((await runtime.health())['data']['embedded'], true);
      runtime.dispose();
    },
  );
  test(
    'embedded safe errors and malformed responses follow HTTP semantics',
    () async {
      final runtime = SourceRuntimeClient(
        endpoint: '',
        embeddedRequest: (_, _, _) async => '{"error":{"code":"BUSY"}}',
      );
      await expectLater(
        runtime.health(),
        throwsA(isA<SourceException>().having((e) => e.code, 'code', 'BUSY')),
      );
      runtime.dispose();
      final malformed = SourceRuntimeClient(
        endpoint: '',
        embeddedRequest: (_, _, _) async => 'not-json',
      );
      await expectLater(
        malformed.health(),
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
      malformed.dispose();
    },
  );
  test(
    'platform call transports only fixed JSON and real string IDs',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'request');
            final args = call.arguments as Map;
            final body = jsonDecode(args['payloadJson'])['body'];
            expect(body['payload']['videoId'], '9007199254740993');
            expect(args.containsKey('module'), false);
            return '{"data":{"ok":true}}';
          });
      final cancel = CancelToken();
      final response = await invokeEmbeddedRuntime(
        {
          'path': 'adapters/miomedia/sdk',
          'method': 'POST',
          'query': {},
          'body': {
            'operation': 'detail',
            'payload': {'videoId': '9007199254740993'},
          },
        },
        20000,
        cancel.whenCancel,
      );
      expect(jsonDecode(response!)['data']['ok'], true);
    },
  );
  test(
    'cancellation returns immediately and sends a native cancel message',
    () async {
      final pending = Completer<String>();
      final cancelledId = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancel') {
              cancelledId.complete((call.arguments as Map)['requestId']);
              return null;
            }
            return pending.future;
          });
      final cancel = CancelToken();
      final request = invokeEmbeddedRuntime(
        {'path': 'health', 'method': 'GET', 'query': {}, 'body': null},
        1000,
        cancel.whenCancel,
      );
      cancel.cancel();
      await expectLater(
        request,
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'CANCELLED'),
        ),
      );
      expect(await cancelledId.future, isNotEmpty);
      pending.complete('{"data":{}}');
    },
  );
}
