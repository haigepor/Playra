import 'package:dio/dio.dart';
import 'source_models.dart';

/// Android/Windows 可连接本机服务，Web 使用所在预览站点的同源地址。
class SourceHttpClient {
  SourceHttpClient(String baseUrl, {Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 45),
            ),
          );
  final Dio _client;
  Future<void>? _session;
  String? _sessionId;
  Future<void> openSession() => _session ??= _openSession();
  Future<void> _openSession() async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/sessions',
      );
      _sessionId = response.data!['id'] as String;
    } catch (_) {
      _session = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    SourceContext? context,
    bool session = true,
  }) async {
    if (session) await openSession();
    context?.checkActive();
    try {
      final response = await _client.request<Map<String, dynamic>>(
        path,
        queryParameters: query,
        data: body,
        cancelToken: context?.cancelToken,
        options: Options(
          method: method,
          receiveTimeout: context?.timeout,
          validateStatus: (_) => true,
          headers: {if (session) 'X-Kazumi-Session': _sessionId},
        ),
      );
      final result = response.data ?? {};
      final error = result['error'];
      if (error is Map) {
        throw SourceException(
          error['code'] as String? ?? 'HTTP_ERROR',
          error['message'] as String? ?? '接口请求失败',
          providerId: error['providerId'] as String?,
        );
      }
      if ((response.statusCode ?? 500) >= 400) {
        throw const SourceException('HTTP_ERROR', '接口请求失败');
      }
      return result;
    } on DioException catch (error) {
      throw SourceException(
        error.type == DioExceptionType.cancel ? 'CANCELLED' : 'HTTP_ERROR',
        '接口请求失败',
      );
    }
  }

  String _source(String id) => '/api/v1/sources/${Uri.encodeComponent(id)}';
  Future<Map<String, dynamic>> sources({String? domain}) => _call(
    'GET',
    '/api/v1/sources',
    session: false,
    query: {'domain': ?domain},
  );
  Future<Map<String, dynamic>> categories(String id) =>
      _call('GET', '${_source(id)}/categories');
  Future<Map<String, dynamic>> health(String id) =>
      _call('GET', '${_source(id)}/health');
  Future<Map<String, dynamic>> search(
    String keyword, {
    String? providerId,
    String? domain,
    int page = 1,
    int pageSize = 20,
    SourceContext? context,
  }) {
    SourcePage.validate(page, pageSize);
    return _call(
      'GET',
      providerId == null ? '/api/v1/search' : '${_source(providerId)}/search',
      query: {
        'q': keyword,
        'page': page,
        'pageSize': pageSize,
        'domain': ?domain,
      },
      context: context,
    );
  }

  Future<Map<String, dynamic>> contents(
    String id, {
    String category = 'all',
    int page = 1,
    int pageSize = 20,
    SourceContext? context,
  }) => _call(
    'GET',
    '${_source(id)}/contents',
    query: {'category': category, 'page': page, 'pageSize': pageSize},
    context: context,
  );
  Future<Map<String, dynamic>> content(String id, String contentId) =>
      _call('GET', '${_source(id)}/contents/${Uri.encodeComponent(contentId)}');
  Future<Map<String, dynamic>> lines(
    String id,
    String contentId, {
    SourceContext? context,
  }) => _call(
    'GET',
    '${_source(id)}/contents/${Uri.encodeComponent(contentId)}/lines',
    context: context,
  );
  Future<Map<String, dynamic>> resolve({
    required String providerId,
    required String contentId,
    required String lineId,
    required String episodeId,
  }) => _call(
    'POST',
    '/api/v1/playback/resolutions',
    body: {
      'providerId': providerId,
      'contentId': contentId,
      'lineId': lineId,
      'episodeId': episodeId,
    },
  );
  Future<Map<String, dynamic>> resolution(String id) =>
      _call('GET', '/api/v1/playback/resolutions/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> cancelResolution(String id) => _call(
    'DELETE',
    '/api/v1/playback/resolutions/${Uri.encodeComponent(id)}',
  );
  Future<Map<String, dynamic>> challenge(String providerId, String keyword) =>
      _call(
        'POST',
        '/api/v1/challenges',
        body: {'providerId': providerId, 'keyword': keyword},
      );
  Future<Map<String, dynamic>> challengeStatus(String id) =>
      _call('GET', '/api/v1/challenges/${Uri.encodeComponent(id)}');
  Future<Map<String, dynamic>> submitChallenge(String id, String code) => _call(
    'POST',
    '/api/v1/challenges/${Uri.encodeComponent(id)}/submissions',
    body: {'code': code},
  );
  Future<Map<String, dynamic>> cancelChallenge(String id) =>
      _call('DELETE', '/api/v1/challenges/${Uri.encodeComponent(id)}');
  void dispose() => _client.close(force: true);
}
