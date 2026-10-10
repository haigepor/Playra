import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

class SourceGateway implements RuleRequestExecutor {
  SourceGateway(this.base, {Dio? client})
    : client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 40),
            ),
          );
  final Uri base;
  final Dio client;
  final Map<String, CookieJar> _cookies = {};
  final Map<String, String> _agents = {};
  final Map<RuleExecutionConfig, String> _providerIds = {};
  void bindSource(RuleExecutionConfig config, String providerId) {
    _providerIds[config] = providerId;
  }

  String _scope = '';

  SourceGateway scoped(String sessionId) {
    final gateway = SourceGateway(base, client: client);
    gateway._scope = sessionId;
    gateway._cookies.addAll(_cookies);
    gateway._agents.addAll(_agents);
    gateway._providerIds.addAll(_providerIds);
    return gateway;
  }

  String _key(String providerName) => '$_scope:${providerName.toLowerCase()}';
  CookieJar _jar(String providerName) =>
      _cookies.putIfAbsent(_key(providerName), CookieJar.new);

  Future<Map<String, String>> playbackHeaders(
    String name,
    String url, {
    String? userAgent,
    String? referer,
  }) async {
    final cookie = (await _jar(name).loadForRequest(
      Uri.parse(url),
    )).map((c) => '${c.name}=${c.value}').join('; ');
    return {
      if ((referer ?? '').isNotEmpty) 'referer': referer!,
      if ((_agents[_key(name)] ?? userAgent ?? '').isNotEmpty)
        'user-agent': _agents[_key(name)] ?? userAgent!,
      if (cookie.isNotEmpty) 'cookie': cookie,
    };
  }

  Future<void> applyVerification(
    String name,
    String url,
    Map<String, dynamic> data,
  ) async {
    final cookies = (data['cookie'] as String? ?? '')
        .split(';')
        .where((s) => s.contains('='))
        .map((s) => Cookie.fromSetCookieValue(s.trim())..path = '/')
        .toList();
    await _jar(name).saveFromResponse(Uri.parse(url), cookies);
    final agent = data['userAgent'];
    if (agent is String && agent.isNotEmpty) _agents[_key(name)] = agent;
  }

  Future<Map<String, dynamic>> browser(
    String operation,
    Map<String, dynamic> data, {
    RuleCancelToken? cancelToken,
  }) async {
    final response = await client.post<Map<String, dynamic>>(
      base.resolve('/api/$operation').toString(),
      data: data,
      options: Options(headers: {'X-Kazumi-Request': '1'}),
      cancelToken: cancelToken,
    );
    return response.data ?? {};
  }

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    RuleCancelToken? cancelToken,
  }) async {
    final providerId = _providerIds[config] ?? config.pluginName;
    final uri = Uri.parse(request.url).replace(
      queryParameters: {
        ...Uri.parse(request.url).queryParameters,
        ...request.query.map((k, v) => MapEntry(k, v.toString())),
      },
    );
    final headers = <String, dynamic>{
      'referer': '${config.baseUrl}/',
      for (final entry in request.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    if (request.includeCookies) {
      headers.addAll(await playbackHeaders(providerId, uri.toString()));
    }
    if (request.method == 'POST') {
      if (request.bodyType == ApiBodyType.json) {
        headers['content-type'] = 'application/json';
      }
      if (request.bodyType == ApiBodyType.form) {
        headers['content-type'] = 'application/x-www-form-urlencoded';
      }
    }
    try {
      final response = await client.request<String>(
        base
            .resolve('/api/proxy')
            .replace(queryParameters: {'url': uri.toString()})
            .toString(),
        data: request.method == 'POST' ? request.body : null,
        options: Options(
          method: request.method,
          responseType: ResponseType.plain,
          contentType: headers['content-type'] as String?,
          headers: {
            'X-Kazumi-Request': '1',
            'X-Kazumi-Headers': base64Url.encode(
              utf8.encode(jsonEncode(headers)),
            ),
          },
        ),
        cancelToken: cancelToken,
      );
      final rawCookies = response.headers.value('x-kazumi-set-cookie');
      if (rawCookies != null) {
        final values =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(base64Url.normalize(rawCookies)),
                  ),
                )
                as List;
        await _jar(providerId).saveFromResponse(
          uri,
          values.cast<String>().map(Cookie.fromSetCookieValue).toList(),
        );
      }
      return response.data ?? '';
    } on DioException catch (error) {
      throw NetworkException(
        type: error.type == DioExceptionType.cancel
            ? NetworkExceptionType.cancel
            : error.type == DioExceptionType.badResponse
            ? NetworkExceptionType.badResponse
            : NetworkExceptionType.connectionError,
        message: '来源网关请求失败',
        statusCode: error.response?.statusCode,
        rawError: error,
      );
    }
  }

  void dispose() => client.close(force: true);
}
