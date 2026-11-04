import 'package:flutter/material.dart';

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
    return (this * MediaQuery.of(context).devicePixelRatio).round();
  }
}
