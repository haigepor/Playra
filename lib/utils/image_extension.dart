import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 检测当前是否运行在 Flutter Widget 测试绑定下，避免测试中无限骨架动画导致 `pumpAndSettle` 超时。
bool get isFlutterTestBinding => WidgetsBinding.instance.runtimeType
    .toString()
    .contains('TestWidgetsFlutterBinding');

const Map<String, String> _migratedImageHosts = {
  'viptulz.com': 'img.lzipic.com',
  'img.lzzyimg.com': 'img.lzipic.com',
  'pic.lzzypic.com': 'img.lzipic.com',
  'vip.dytt-img.com': 'img.dytt-tupian.com',
  'vod.dyttimage.com': 'img.dytt-tupian.com',
  'img.image8899.net': 'tupian.ffeiimg.com',
  'img.image8899.com': 'tupian.ffeiimg.com',
  'img.ffzy888.com': 'tupian.ffeiimg.com',
  'pic1.imgyzzy.com': 'pic3.yzzyimg.online',
  'pic3.yzzyimages.com': 'pic3.yzzyimg.online',
  'pic.yzzyimg.com': 'pic3.yzzyimg.online',
  'img.bwcgee.cn': 'img.qwapp.top',
};

const Set<String> _baiduProxyBfzyHosts = {
  'bftuvip.com',
  'img.bfzypic.com',
};

const Set<String> _deadImageHosts = {
  'dbzy3.com',
  'snzypic.com',
  'pic.findjs.top',
  'www.subaibaiys.com',
  'subaibaiys.com',
  'ims.99meiju.cn',
  '99meiju.cn',
};

final RegExp _ampEntity = RegExp(r'&(?:amp;)+');

/// 规范化图片地址：修复协议前缀、反转义 `&amp;` 并将已迁移的采集站旧图床域名重写为可用域名。
String normalizeImageUrl(String raw) {
  var text = raw.trim().replaceAll(_ampEntity, '&');
  if (text.isEmpty) return '';
  if (text.startsWith('mac://')) {
    text = 'https://${text.substring(6)}';
  } else if (text.startsWith('//')) {
    text = 'https:$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
    return '';
  }
  final host = uri.host.toLowerCase();
  if (_baiduProxyBfzyHosts.contains(host) && uri.path.isNotEmpty) {
    return 'https://gimg0.baidu.com/gimg/app=2001&n=0&g=0n&fmt=webp&src=img.bfzypic.com${uri.path}';
  }
  final replacementHost = _migratedImageHosts[host];
  if (replacementHost != null) {
    return uri.replace(scheme: 'https', host: replacementHost).toString();
  }
  return text;
}

/// 判断图片地址是否位于已停服下线的死链图床域名。
bool isDeadImageHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return _deadImageHosts.contains(host);
}

final Map<String, String> _fallbackCoverCache = {};
final Set<String> _fallbackCoverResolvedEmpty = {};
final Map<String, Future<String?>> _fallbackCoverInFlight = {};
final RegExp _doubanPosterRegex = RegExp(
  r'https://img\d\.doubanio\.com/view/photo/[^"\x27\s>]+',
);

String? cachedFallbackCoverForTitle(String? title) {
  final key = _cleanLookupTitle(title);
  if (key.isEmpty) return null;
  return _fallbackCoverCache[key];
}

bool hasTriedFallbackCoverForTitle(String? title) {
  final key = _cleanLookupTitle(title);
  if (key.isEmpty) return true;
  return _fallbackCoverCache.containsKey(key) ||
      _fallbackCoverResolvedEmpty.contains(key);
}

String _cleanLookupTitle(String? title) {
  if (title == null) return '';
  return title
      .replaceAll(RegExp(r'[(（【\[].*?[)）】\]]'), '')
      .replaceAll(RegExp(r'\s+(?:国语|粤语|高清|HD|BD|正片|中字).*$'), '')
      .trim();
}

Future<String?> _fetchMaoyanCover(String key) async {
  try {
    final uri = Uri.https('m.maoyan.com', '/ajax/search', {
      'kw': key,
      'cityId': '1',
      'stype': '-1',
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
            'Referer': 'https://m.maoyan.com/',
          },
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final movies = decoded is Map ? decoded['movies'] : null;
    final list = movies is Map ? movies['list'] : null;
    if (list is! List || list.isEmpty) return null;
    Map? chosen;
    for (final entry in list) {
      if (entry is Map &&
          entry['nm']?.toString().trim() == key &&
          (entry['img']?.toString().isNotEmpty ?? false)) {
        chosen = entry;
        break;
      }
    }
    chosen ??= list.whereType<Map>().firstWhere(
      (e) => e['img']?.toString().isNotEmpty ?? false,
      orElse: () => const {},
    );
    final rawImg = chosen['img']?.toString().trim() ?? '';
    if (rawImg.isEmpty) return null;
    return normalizeImageUrl(rawImg.replaceAll('/w.h/', '/'));
  } catch (_) {
    return null;
  }
}

Future<String?> _fetchDoubanHtmlSearchCover(String key) async {
  try {
    final uri = Uri.https('www.douban.com', '/search', {
      'cat': '1002',
      'q': key,
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
            'Referer': 'https://www.douban.com/',
          },
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final match = _doubanPosterRegex.firstMatch(body)?.group(0)?.trim() ?? '';
    return match.isNotEmpty ? match : null;
  } catch (_) {
    return null;
  }
}

Future<String?> _fetchDoubanSuggestCover(String key) async {
  try {
    final uri = Uri.https('movie.douban.com', '/j/subject_suggest', {'q': key});
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
            'Referer': 'https://movie.douban.com/',
          },
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;
    Map? chosen;
    for (final entry in decoded) {
      if (entry is Map &&
          entry['title']?.toString().trim() == key &&
          (entry['img']?.toString().isNotEmpty ?? false)) {
        chosen = entry;
        break;
      }
    }
    chosen ??= decoded.whereType<Map>().firstWhere(
      (e) => e['img']?.toString().isNotEmpty ?? false,
      orElse: () => const {},
    );
    final img = chosen['img']?.toString().trim() ?? '';
    return img.isNotEmpty ? img : null;
  } catch (_) {
    return null;
  }
}

/// 当源站封面域名失效或 404 时，按片名从公开检索接口（猫眼 + 豆瓣双源）回退获取高清海报并缓存。
Future<String?> resolveFallbackCoverByTitle(String? rawTitle) {
  final key = _cleanLookupTitle(rawTitle);
  if (key.isEmpty || isFlutterTestBinding) {
    return Future.value(null);
  }
  final cached = _fallbackCoverCache[key];
  if (cached != null) {
    return Future.value(cached);
  }
  if (_fallbackCoverResolvedEmpty.contains(key)) {
    return Future.value(null);
  }
  return _fallbackCoverInFlight.putIfAbsent(key, () async {
    try {
      final url =
          await _fetchMaoyanCover(key) ??
          await _fetchDoubanHtmlSearchCover(key) ??
          await _fetchDoubanSuggestCover(key);
      if (url != null && url.isNotEmpty) {
        _fallbackCoverCache[key] = url;
        return url;
      }
      _fallbackCoverResolvedEmpty.add(key);
    } finally {
      _fallbackCoverInFlight.remove(key);
    }
    return null;
  });
}

/// 按图床域名注入图片请求头。
///
/// 豆瓣系图床对无 UA/Referer 的请求直接拒绝（真机实测 418/403，
/// 带 UA + `Referer: https://www.douban.com/` 后 200）。
/// 其余域名刻意不加任何头：腾讯系 CDN 历史上对带 Referer 的请求回 404，
/// 能加载的域名不改变行为。UA 固定单个值，保证缓存键与命中稳定。
Map<String, String> httpHeadersForImageUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.endsWith('doubanio.com') || host.endsWith('douban.com')) {
    return const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      'Referer': 'https://www.douban.com/',
    };
  }
  return const {};
}

extension ImageExtension on num {
  int cacheSize(BuildContext context) {
    if (!isFinite) return 0;
    return (this * MediaQuery.of(context).devicePixelRatio).round();
  }
}
