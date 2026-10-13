import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'source_models.dart';

class SourceResolvedMedia {
  const SourceResolvedMedia({
    required this.url,
    this.headers = const {},
    this.format = 'auto',
    this.expiresAt,
  });
  final String url, format;
  final Map<String, String> headers;
  final DateTime? expiresAt;
}

class SourceResolveConfig {
  SourceResolveConfig(this.json);
  final Map<String, dynamic> json;
  ApiRequestConfig get request => ApiRequestConfig.fromJson(
    Map<String, dynamic>.from(json['request'] as Map? ?? const {}),
  );
  void validate() {
    if (!const ['GET', 'POST'].contains(request.method)) {
      throw const SourceException('INVALID_RULE', '解析接口仅支持 GET/POST');
    }
    final uri = Uri.tryParse(request.url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const SourceException('INVALID_RULE', '解析接口必须是 HTTP 地址');
    }
    for (final key in [
      'urlPath',
      'headersPath',
      'formatPath',
      'expiresAtPath',
    ]) {
      final path = json[key];
      if (path != null) RestrictedJsonPath.validate(path as String);
    }
  }

  SourceResolvedMedia parse(String response) {
    validate();
    final document = const ApiRuleStrategy().decodeResponse(response);
    Object? read(String key, String fallback) => RestrictedJsonPath.readFirst(
      document,
      json[key] as String? ?? fallback,
    );
    final url = read('urlPath', r'$.url');
    if (url is! String ||
        !['http', 'https'].contains(Uri.tryParse(url)?.scheme) ||
        Uri.parse(url).host.isEmpty) {
      throw const SourceException('PARSE_ERROR', '解析接口没有返回有效视频地址');
    }
    final rawHeaders = read('headersPath', r'$.headers');
    final expiresRaw = read('expiresAtPath', r'$.expiresAt');
    final expires = expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
    if (expires != null && !expires.isAfter(DateTime.now())) {
      throw const SourceException('EXPIRED', '解析接口返回的视频地址已过期');
    }
    final rawFormat = read('formatPath', r'$.format');
    return SourceResolvedMedia(
      url: url,
      headers: rawHeaders is Map
          ? {
              for (final entry in rawHeaders.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : {},
      format:
          rawFormat == 'hls' ||
              Uri.parse(url).path.toLowerCase().endsWith('.m3u8')
          ? 'hls'
          : 'auto',
      expiresAt: expires,
    );
  }
}
