import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/browser.dart';
import 'package:kazumi/request/core/network_config.dart';

HttpClientAdapter createNetworkAdapter(NetworkConfig config) =>
    _GatewayAdapter();

class _GatewayAdapter implements HttpClientAdapter {
  final _browser = BrowserHttpClientAdapter();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final target = options.uri;
    final uri = Uri.base
        .resolve('/api/proxy')
        .replace(queryParameters: {'url': target.toString()});
    final headers = options.headers.map(
      (key, value) => MapEntry(key, value?.toString()),
    );
    final forwarded = options.copyWith(
      path: uri.toString(),
      baseUrl: '',
      queryParameters: {},
      headers: {
        'X-Kazumi-Request': '1',
        'X-Kazumi-Headers': base64Url.encode(utf8.encode(jsonEncode(headers))),
        if (options.contentType != null) 'Content-Type': options.contentType,
      },
    );
    final response = await _browser.fetch(
      forwarded,
      requestStream,
      cancelFuture,
    );
    final cookies = response.headers['x-kazumi-set-cookie'];
    if (cookies != null && cookies.isNotEmpty) {
      response.headers['set-cookie'] =
          (jsonDecode(
                    utf8.decode(
                      base64Url.decode(base64Url.normalize(cookies.first)),
                    ),
                  )
                  as List)
              .cast<String>();
    }
    return response;
  }

  @override
  void close({bool force = false}) => _browser.close(force: force);
}
