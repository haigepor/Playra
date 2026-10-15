import 'dart:async';
import 'dart:io';
import 'package:ech_http/ech_http.dart';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/network/bangumi_ech_resolver.dart';

/// Web 与 Android 共用 ECH 配置；仅转发固定 Bangumi 公共域名。
Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8946 : int.parse(args.single);
  final bootstrap = EchClient();
  final client = EchClient(
    resolver: BangumiEchResolver.create(bootstrap),
    maxRequestBytes: 65536,
    maxResponseBytes: 8 * 1024 * 1024,
    maxConcurrentRequests: 12,
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  var active = 0;
  Future<void> handle(HttpRequest request) async {
    final abort = Completer<void>();
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    request.response.done.then((_) => cancel(), onError: (_) => cancel());
    Timer? deadline;
    var acquired = false;
    try {
      final target = Uri.tryParse(request.uri.queryParameters['url'] ?? '');
      final localHost = Uri.tryParse(
        'http://${request.headers.value('host')}',
      )?.host;
      if (['127.0.0.1', 'localhost'].contains(localHost) &&
          request.uri.path == '/health' && request.method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"service":"playra-bangumi-ech","apiVersion":"1"}');
        return;
      }
      if (!['127.0.0.1', 'localhost'].contains(localHost) ||
          request.headers.value('x-kazumi-request') != '1' ||
          request.uri.path != '/relay' ||
          target == null ||
          target.scheme != 'https' ||
          !BangumiEchResolver.hosts.contains(target.host) ||
          target.userInfo.isNotEmpty ||
          target.hasFragment ||
          target.port != 443 ||
          !['GET', 'POST', 'HEAD'].contains(request.method) ||
          (request.method == 'POST' &&
              (target.host != 'api.bgm.tv' ||
                  target.path != '/v0/search/subjects'))) {
        request.response.statusCode = 400;
        return;
      }
      if (active >= 12) {
        request.response.statusCode = 503;
        return;
      }
      active++;
      acquired = true;
      deadline = Timer(const Duration(seconds: 35), cancel);
      final body = <int>[];
      await for (final chunk in request) {
        body.addAll(chunk);
        if (body.length > 65536) {
          request.response.statusCode = 413;
          return;
        }
      }
      final outgoing =
          http.AbortableRequest(
              request.method,
              target,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..bodyBytes = body;
      for (final name in ['accept', 'content-type', 'user-agent']) {
        final value = request.headers.value(name);
        if (value != null) outgoing.headers[name] = value;
      }
      final response = await client.send(outgoing);
      request.response.statusCode = response.statusCode;
      for (final name in ['content-type', 'cache-control']) {
        final value = response.headers[name];
        if (value != null) request.response.headers.set(name, value);
      }
      // 不自动跨域跳转或转发 Cookie，响应体由 EchClient 限制解压后大小。
      await request.response.addStream(response.stream);
    } catch (_) {
      try {
        request.response.statusCode = 502;
      } catch (_) {}
    } finally {
      deadline?.cancel();
      cancel();
      if (acquired) active--;
      await request.response.close();
    }
  }

  server.listen((request) => unawaited(handle(request)));
  stdout.writeln('Bangumi Web ECH bridge: http://127.0.0.1:$port');
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    client.close();
    bootstrap.close();
    exit(0);
  });
}
