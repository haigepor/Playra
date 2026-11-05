/// 图床直连失败后的公共镜像回退。
///
/// 片源站点的封面图床常见两类问题：域名被 DNS 污染（实测
/// `vip.dytt-img.com` 被解析到 `31.13.94.10`）或被本地网络阻断；
/// 原图在境外仍然可访问。wsrv.nl 由服务端取图，能绕过客户端的
/// DNS/链路问题。只作为直连失败后的第二跳，不改变正常直连行为。
abstract final class ImageMirror {
  static const host = 'wsrv.nl';

  static bool canMirror(Uri uri) {
    if (!_isHttp(uri) || uri.host.isEmpty) return false;
    if (uri.host == host || uri.host.endsWith('.$host')) return false;
    return !_isLocalHost(uri.host);
  }

  static Uri rewrite(Uri uri) {
    return Uri.https(host, '/', {
      'url': uri.host + uri.path + (uri.hasQuery ? '?${uri.query}' : ''),
      // wsrv 默认只保留动图首帧；GIF 需要显式关闭该行为。
      if (uri.path.toLowerCase().endsWith('.gif')) 'n': '-1',
    });
  }

  static bool _isHttp(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    final match = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (match == null) return false;
    final first = int.parse(match[1]!);
    final second = int.parse(match[2]!);
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 169 && second == 254);
  }
}
