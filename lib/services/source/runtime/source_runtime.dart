import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import '../source_models.dart';
import 'runtime_endpoint.dart'
    if (dart.library.js_interop) 'runtime_endpoint_web.dart'
    as platform;

const sourceRuntimeHost = 'source-runtime.playra.invalid';

typedef EmbeddedRuntimeRequest =
    Future<String?> Function(
      Map<String, dynamic> request,
      int timeoutMs,
      Future<Object?> cancelled,
    );

/// 保留域名只定位运行契约，真实地址由应用或服务器管理员配置。
class SourceRuntimeClient {
  SourceRuntimeClient({
    String? endpoint,
    this.allowInsecure = const bool.fromEnvironment(
      'PLAYRA_SOURCE_RUNTIME_ALLOW_HTTP',
    ),
    Dio? client,
    EmbeddedRuntimeRequest? embeddedRequest,
    this.timeout = const Duration(seconds: 20),
  }) : endpoint = endpoint ?? platform.defaultRuntimeEndpoint(),
       client = client ?? Dio(BaseOptions(connectTimeout: timeout)),
       _embeddedRequest = embeddedRequest ?? platform.invokeEmbeddedRequest;

  final String endpoint;
  final bool allowInsecure;
  final Dio client;
  final Duration timeout;
  final EmbeddedRuntimeRequest _embeddedRequest;
  final _embeddedPending = <CancelToken>{};
  bool _disposed = false;

  Uri get base {
    if (endpoint.isEmpty) {
      throw const SourceException('RUNTIME_UNAVAILABLE', '尚未配置算法运行服务');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !allowInsecure &&
            !const bool.fromEnvironment('dart.library.js_interop'))) {
      throw const SourceException(
        'INVALID_ARGUMENT',
        '运行服务地址须为 HTTPS，开发 HTTP 需显式启用',
      );
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  static bool accepts(Uri uri, String method) {
    final path = uri.path;
    if (method == 'GET' && ['health', 'adapters'].contains(path)) return true;
    if (const ['adapters/miomedia/sdk', 'adapters/lumina/sdk'].contains(path) &&
        method == 'POST') return true;
    final match = RegExp(
      r'^adapters/[A-Za-z0-9_-]{1,64}/(search|episodes|resolve)$',
    ).firstMatch(path);
    return match != null && method == (match[1] == 'resolve' ? 'POST' : 'GET');
  }

  Future<Map<String, dynamic>> health({CancelToken? cancelToken}) =>
      request('health', cancelToken: cancelToken);

  /// SDK 内容操作独立于完整播放来源；握手和设备密钥由服务管理。
  Future<Map<String, dynamic>> callMioMedia(
    String operation, {
    Map<String, dynamic> payload = const {},
    CancelToken? cancelToken,
  }) => request(
    'adapters/miomedia/sdk',
    method: 'POST',
    body: {'operation': operation, 'payload': payload},
    cancelToken: cancelToken,
  );

  /// 只开放 Lumina 内容与播放业务；环境绑定值和算法始终留在运行宿主。
  Future<Map<String, dynamic>> callLumina(
    String operation, {
    Map<String, dynamic> payload = const {},
    CancelToken? cancelToken,
  }) => request(
    'adapters/lumina/sdk',
    method: 'POST',
    body: {'operation': operation, 'payload': payload},
    cancelToken: cancelToken,
  );

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Object? body,
    CancelToken? cancelToken,
  }) async {
    if (_disposed) throw const SourceException('CANCELLED', '运行服务已关闭');
    if (!accepts(Uri(path: path), method)) {
      throw const SourceException('UNSUPPORTED', '算法运行接口路径或方法不支持');
    }
    if (timeout.inMilliseconds < 1 || timeout > const Duration(seconds: 60)) {
      throw const SourceException('INVALID_ARGUMENT', '运行请求预算须为 1–60000 毫秒');
    }
    if (body != null && utf8.encode(jsonEncode(body)).length > 32768) {
      throw const SourceException('INVALID_ARGUMENT', '运行请求体超过限制');
    }
    if (cancelToken?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    final activeCancel = CancelToken();
    if (cancelToken != null) {
      cancelToken.whenCancel.then((error) => activeCancel.cancel(error));
    }
    Future<Map<String, dynamic>> perform() async {
      try {
        if (endpoint.isEmpty) {
          _embeddedPending.add(activeCancel);
          String? raw;
          try {
            raw = await _embeddedRequest(
              {'path': path, 'method': method, 'query': query, 'body': body},
              timeout.inMilliseconds,
              activeCancel.whenCancel,
            );
          } finally {
            _embeddedPending.remove(activeCancel);
          }
          if (activeCancel.isCancelled) {
            throw const SourceException('CANCELLED', '请求已取消');
          }
          if (raw != null) {
            if (utf8.encode(raw).length > 2 * 1024 * 1024) {
              throw const SourceException('PARSE_ERROR', '算法运行响应超过限制');
            }
            Object? decoded;
            try {
              decoded = jsonDecode(raw);
            } on FormatException {
              throw const SourceException('PARSE_ERROR', '算法运行服务返回了无效 JSON');
            }
            return _acceptResponse(decoded, 200);
          }
        }
        final response = await client.request<ResponseBody>(
          base.resolve(path).toString(),
          queryParameters: query,
          data: body,
          options: Options(
            method: method,
            responseType: ResponseType.stream,
            contentType: 'application/json',
            sendTimeout: timeout,
            receiveTimeout: timeout,
            // 不跟随重定向，避免把运行入口变成任意站点/凭据转发。
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              'X-Kazumi-Request': '1',
              'X-Playra-Timeout-Ms': '${timeout.inMilliseconds}',
            },
          ),
          cancelToken: activeCancel,
        );
        if (cancelToken?.isCancelled == true) {
          throw const SourceException('CANCELLED', '请求已取消');
        }
        final bytes = BytesBuilder(copy: false);
        final stream = response.data;
        if (stream == null) {
          throw const SourceException('PARSE_ERROR', '算法运行响应为空');
        }
        await for (final chunk in stream.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            activeCancel.cancel('response limit');
            throw const SourceException('PARSE_ERROR', '算法运行响应超过限制');
          }
          bytes.add(chunk);
        }
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        } on FormatException {
          throw const SourceException('PARSE_ERROR', '算法运行服务返回了无效 JSON');
        }
        if (activeCancel.isCancelled) {
          throw const SourceException('CANCELLED', '请求已取消');
        }
        return _acceptResponse(decoded, response.statusCode);
      } on DioException catch (error) {
        throw SourceException(
          error.type == DioExceptionType.cancel
              ? 'CANCELLED'
              : [
                  DioExceptionType.connectionTimeout,
                  DioExceptionType.sendTimeout,
                  DioExceptionType.receiveTimeout,
                ].contains(error.type)
              ? 'TIMEOUT'
              : 'RUNTIME_UNAVAILABLE',
          '算法运行服务请求失败',
        );
      }
    }

    // 包括连接与读取的总预算，不能被连续的小块响应无限延长。
    return perform().timeout(
      timeout,
      onTimeout: () {
        activeCancel.cancel('runtime deadline');
        throw const SourceException('TIMEOUT', '算法运行服务请求超时');
      },
    );
  }

  static Map<String, dynamic> _acceptResponse(Object? decoded, int? status) {
    if (decoded is! Map<String, dynamic>) {
      throw const SourceException('PARSE_ERROR', '算法运行响应必须是对象');
    }
    final error = decoded['error'];
    if (error is Map) {
      final code = error['code'];
      final safeCode =
          code is String && RegExp(r'^[A-Z_]{1,64}$').hasMatch(code)
          ? code
          : 'RUNTIME_ERROR';
      throw SourceException(safeCode, '算法运行服务未完成请求（$safeCode）');
    }
    if (status != 200) {
      throw const SourceException('RUNTIME_ERROR', '算法运行服务状态异常');
    }
    return decoded;
  }

  void dispose() {
    _disposed = true;
    for (final cancel in _embeddedPending.toList()) {
      cancel.cancel('Runtime disposed');
    }
    _embeddedPending.clear();
    client.close(force: true);
  }
}

/// 仅拦截显式运行域名；官方规则仍交给原请求器。
class SourceRuntimeExecutor implements RuleRequestExecutor {
  SourceRuntimeExecutor(this.delegate, {SourceRuntimeClient? runtime})
    : _runtime = runtime;
  final RuleRequestExecutor delegate;
  SourceRuntimeClient? _runtime;

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null || uri.host != sourceRuntimeHost) {
      return delegate.execute(request, config, cancelToken: cancelToken);
    }
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasFragment ||
        !uri.path.startsWith('/v1/')) {
      throw const SourceException('INVALID_ARGUMENT', '算法运行标记地址无效');
    }
    final result = await (_runtime ??= SourceRuntimeClient()).request(
      uri.path.substring(4),
      method: request.method,
      query: {...uri.queryParameters, ...request.query},
      body: request.body,
      cancelToken: cancelToken,
    );
    return jsonEncode(result);
  }
}
