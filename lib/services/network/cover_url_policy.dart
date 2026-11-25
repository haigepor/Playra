import 'package:kazumi/request/core/network_config.dart';

/// Shared URL normalization, domain-specific header routing, and short-lived
/// failure memory for cover/banner/artwork image loading.
class CoverUrlPolicy {
  CoverUrlPolicy._();

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const String doubanReferer = 'https://movie.douban.com/';

  static const Duration failedTtl = Duration(minutes: 10);

  static const Set<String> _httpsMediaDomains = <String>{
    'doubanio.com',
    'douban.com',
    'iqiyipic.com',
    'qiyipic.com',
    'qpic.cn',
    'hdslb.com',
    'bilivideo.com',
    '360buyimg.com',
    'ykimg.com',
    'gtimg.com',
    'sinaimg.cn',
  };

  static final Map<String, DateTime> _failedAt = <String, DateTime>{};
  static final Set<String> _loggedUrls = <String>{};
  static int _failedRevision = -1;

  /// Normalizes a raw cover URL:
  /// - trims whitespace and upgrades protocol-relative `//` URLs to `https://`
  /// - rewrites retired `qnmob*.doubanio.com` and JS-challenge
  ///   `img9.doubanio.com` hosts to `img2.doubanio.com`
  /// - upgrades known anti-hotlink CDNs from `http:` to `https:`
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final candidate = trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return '';
    }

    final host = uri.host.toLowerCase();
    var nextHost = uri.host;
    var nextQuery = uri.hasQuery ? uri.query : null;

    if (host == 'qnmob.doubanio.com' ||
        host == 'qnmob2.doubanio.com' ||
        host == 'qnmob3.doubanio.com') {
      nextHost = 'img2.doubanio.com';
      // Retired qnmob URLs carry legacy Qiniu imageView2 query parameters.
      if (nextQuery != null && nextQuery.startsWith('imageView2/')) {
        nextQuery = null;
      }
    } else if (host == 'img9.doubanio.com') {
      // img9 frequently responds with an obfuscated JS challenge HTML page
      // instead of image bytes, while img1/img2/img3 serve the image directly.
      nextHost = 'img2.doubanio.com';
    }

    var nextScheme = uri.scheme;
    if (nextScheme == 'http' && _matchesAnyDomain(host, _httpsMediaDomains)) {
      nextScheme = 'https';
    }

    if (nextScheme == uri.scheme &&
        nextHost == uri.host &&
        nextQuery == (uri.hasQuery ? uri.query : null)) {
      return uri.toString();
    }

    return Uri(
      scheme: nextScheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: nextHost,
      port: uri.hasPort && !(nextScheme == 'https' && uri.port == 80)
          ? uri.port
          : null,
      path: uri.path,
      query: nextQuery,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  /// Returns CDN-appropriate HTTP headers for [url].
  ///
  /// Only Douban hosts receive `movie.douban.com` as Referer; other CDNs such
  /// as `iqiyipic.com` reject foreign referers with HTTP 403.
  static Map<String, String> headersFor(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (_matchesDomain(host, 'doubanio.com') ||
        _matchesDomain(host, 'douban.com')) {
      return const <String, String>{
        'User-Agent': userAgent,
        'Referer': doubanReferer,
      };
    }
    if (_matchesDomain(host, 'hdslb.com') ||
        _matchesDomain(host, 'bilivideo.com')) {
      return const <String, String>{
        'User-Agent': userAgent,
        'Referer': 'https://www.bilibili.com/',
      };
    }
    if (_matchesDomain(host, 'sinaimg.cn') ||
        _matchesDomain(host, 'weibo.cn')) {
      return const <String, String>{
        'User-Agent': userAgent,
        'Referer': 'https://weibo.com/',
      };
    }
    return const <String, String>{'User-Agent': userAgent};
  }

  /// Whether [normalizedUrl] failed recently under the current network config.
  static bool isRecentlyFailed(String normalizedUrl, {DateTime? now}) {
    if (normalizedUrl.isEmpty) return true;
    _syncNetworkRevision();
    final recorded = _failedAt[normalizedUrl];
    if (recorded == null) return false;
    final current = now ?? DateTime.now();
    if (current.difference(recorded) > failedTtl) {
      _failedAt.remove(normalizedUrl);
      _loggedUrls.remove(normalizedUrl);
      return false;
    }
    return true;
  }

  /// Records a failed load for [normalizedUrl] so scrolling and rebuilds do not
  /// flood dead origins with repeated identical requests.
  static void markFailed(String normalizedUrl, {DateTime? now}) {
    if (normalizedUrl.isEmpty) return;
    _syncNetworkRevision();
    _failedAt[normalizedUrl] = now ?? DateTime.now();
  }

  /// Returns true at most once per failed [normalizedUrl] per failure window so
  /// debug logs are not flooded across list rebuilds.
  static bool shouldLogFailure(String normalizedUrl) {
    _syncNetworkRevision();
    return _loggedUrls.add(normalizedUrl);
  }

  /// Clears remembered cover failures (for example after proxy changes or tests).
  static void clearFailedCache() {
    _failedAt.clear();
    _loggedUrls.clear();
    _failedRevision = NetworkConfig.revision;
  }

  static void _syncNetworkRevision() {
    final rev = NetworkConfig.revision;
    if (_failedRevision != rev) {
      _failedAt.clear();
      _loggedUrls.clear();
      _failedRevision = rev;
    }
  }

  static bool _matchesAnyDomain(String host, Set<String> domains) {
    for (final domain in domains) {
      if (_matchesDomain(host, domain)) return true;
    }
    return false;
  }

  static bool _matchesDomain(String host, String domain) {
    return host == domain || host.endsWith('.$domain');
  }
}
