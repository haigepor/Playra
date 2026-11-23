import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_client.dart';
import 'package:kazumi/features/sources/clicli/clicli_config.dart';
import 'package:kazumi/features/sources/core/media_source.dart';

class ApiAdapter implements HttpClientAdapter {
  ApiAdapter(this.reply);

  final Map<String, Object?> Function(RequestOptions) reply;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(reply(options)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  if (!CliCliConfig.isConfigured) {
    test(
      'missing configuration is reported before sending a request',
      () async {
        final client = CliCliClient();
        addTearDown(client.close);
        await expectLater(
          client.callData('/video/modules', {}),
          throwsA(
            isA<MediaSourceException>()
                .having((e) => e.kind, 'kind', MediaSourceErrorKind.unsupported)
                .having((e) => e.message, 'message', '内容源尚未配置，请联系应用提供方'),
          ),
        );
      },
    );
  }

  const path = '/video/modules';
  final expired = <String, Object?>{
    'code': 4020,
    'msg': '加密会话过期，请重新协商',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  final negotiated = <String, Object?>{
    'code': 200,
    'data': {'deviceSecret': List.filled(64, 'a').join(), 'keyVersion': 2},
  };

  test('HTTP 200 with code 4020 negotiates and returns retried data', () async {
    var requests = 0;
    final adapter = ApiAdapter((request) {
      if (request.path == CliCliConfig.pathNegotiate) return negotiated;
      requests++;
      return requests == 1
          ? expired
          : {
              'code': 200,
              'data': {'title': '真实结果'},
            };
    });
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final client = CliCliClient(dio: dio);

    expect(await client.callData(path, {}), {'title': '真实结果'});
    expect(adapter.paths, [path, CliCliConfig.pathNegotiate, path]);
    expect(client.negotiated, isTrue);
    expect(client.keyVersion, 2);
  });

  test('a still-expired response stops after one session recovery', () async {
    final adapter = ApiAdapter((request) {
      return request.path == CliCliConfig.pathNegotiate ? negotiated : expired;
    });
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final client = CliCliClient(dio: dio);

    await expectLater(
      client.callData(path, {}),
      throwsA(isA<MediaSourceException>().having((e) => e.code, 'code', 4020)),
    );
    expect(adapter.paths, [path, CliCliConfig.pathNegotiate, path]);
  });

  test('expired login is reported without session negotiation', () async {
    final adapter = ApiAdapter((_) => {'code': 4012, 'msg': 'token expired'});
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final client = CliCliClient(dio: dio);

    await expectLater(
      client.callData(path, {}),
      throwsA(
        isA<MediaSourceException>()
            .having((e) => e.kind, 'kind', MediaSourceErrorKind.authentication)
            .having((e) => e.message, 'message', '登录状态已失效'),
      ),
    );
    expect(adapter.paths, [path]);
  });
}
