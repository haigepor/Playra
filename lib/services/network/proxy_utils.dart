/// 代理相关的工具函数
class ProxyUtils {
  // 防止实例化
  ProxyUtils._();

  /// 解析代理 URL，返回 (主机, 端口)
  ///
  /// 支持的格式:
  /// - http://127.0.0.1:7890
  /// - 127.0.0.1:7890
  static (String, int)? parseProxyUrl(String url) {
    url = url.trim();
    if (url.isEmpty) return null;

    if (RegExp(r'\s').hasMatch(url)) return null;
    final uri = Uri.tryParse(url.contains('://') ? url : 'http://$url');
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    if (uri.port < 1 || uri.port > 65535) return null;
    return (uri.host, uri.port);
  }

  /// 获取格式化的代理 URL（用于 mpv）
  static String? getFormattedProxyUrl(String url) {
    final parsed = parseProxyUrl(url);
    if (parsed == null) return null;
    return 'http://${parsed.$1}:${parsed.$2}';
  }

  /// 验证代理 URL 是否有效
  static bool isValidProxyUrl(String url) {
    return parseProxyUrl(url) != null;
  }
}
