import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/request/core/bangumi_request_policy.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';

class BangumiAccelerationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 浏览器由本地网关连接官方 API；公共镜像的搜索 POST 目前返回 401。
    // 保留原生镜像行为，避免浏览器搜索依赖第三方镜像授权。
    if (ApiEndpoints.bangumiPublicApiHosts.contains(options.uri.host) &&
        BangumiAcceleration.current == BangumiAcceleration.mirror &&
        options.extra[bangumiAccelerationOverride] == null &&
        options.method != 'POST') {
      final uri = options.uri;
      options.path =
          ApiEndpoints.bangumiMirrorDomain +
          uri.path +
          (uri.hasQuery ? '?${uri.query}' : '');
      options.queryParameters = {};
    }
    handler.next(options);
  }
}

/// Web 通过浏览器 TLS 栈发出请求，不能加载 ECH 的本地动态库。
class BangumiEchAdapter implements HttpClientAdapter {
  BangumiEchAdapter({
    required HttpClientAdapter fallback,
    required NetworkConfig config,
  }) : _fallback = fallback;
  final HttpClientAdapter _fallback;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _fallback.fetch(options, requestStream, cancelFuture);
  @override
  void close({bool force = false}) => _fallback.close(force: force);
}
