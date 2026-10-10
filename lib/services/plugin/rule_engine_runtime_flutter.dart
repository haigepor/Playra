import 'package:dio/dio.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'rule_engine.dart';
import 'rule_engine_models.dart';

RuleRequestExecutor createRuleRequestExecutor() =>
    PlatformRuleRequestExecutor();
void logRuleWarning(String message, {Object? error, StackTrace? stackTrace}) =>
    KazumiLogger().w(message, error: error, stackTrace: stackTrace);
void logRuleInfo(String message) => KazumiLogger().i(message);

class PlatformRuleRequestExecutor implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    final cookieHeader = request.includeCookies
        ? await _cookieHeaderFor(config.pluginName, request.url)
        : '';
    final verifiedUserAgent = cookieHeader.isNotEmpty
        ? PluginCookieManager.instance.userAgentFor(config.pluginName)
        : null;
    // Header names are lowercased so a rule-supplied 'User-Agent' collides
    // with ours instead of being sent as a second, conflicting header.
    final headers = <String, dynamic>{
      'referer': '${config.baseUrl}/',
      if (cookieHeader.isNotEmpty) 'cookie': cookieHeader,
      for (final entry in request.headers.entries)
        entry.key.toLowerCase(): entry.value,
      // Clearance cookies are bound to the User-Agent they were issued to,
      // so the verified UA overrides the rule's own; sending a different one
      // would make the site serve the challenge page again.
      'user-agent': ?verifiedUserAgent,
    };
    if (request.method == 'POST') {
      switch (request.bodyType) {
        case ApiBodyType.json:
          headers.putIfAbsent('content-type', () => 'application/json');
          break;
        case ApiBodyType.form:
          headers.putIfAbsent(
            'content-type',
            () => 'application/x-www-form-urlencoded',
          );
          break;
      }
    }
    return PluginSiteClient.instance.requestText(
      request.url,
      method: request.method,
      headers: headers,
      queryParameters: request.query,
      data: request.method == 'POST' ? request.body : null,
      cancelToken: cancelToken,
    );
  }

  Future<String> _cookieHeaderFor(String pluginName, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    try {
      final cookies = await PluginCookieManager.instance.loadForRequest(
        pluginName,
        uri,
      );
      return cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (_) {
      return '';
    }
  }
}
