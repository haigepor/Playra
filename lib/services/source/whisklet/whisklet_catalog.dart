import 'package:dio/dio.dart' show CancelToken;

import '../source_models.dart' show SourceException;
import 'whisklet_client.dart';
import 'whisklet_models.dart';

/// 目录层：只做「上游方法 → 片目/线路」的映射，不持有页面状态。
class WhiskletCatalog {
  WhiskletCatalog({WhiskletClient? client})
    : client = client ?? WhiskletClient();
  final WhiskletClient client;
  final _infoCache = <int, Map<String, dynamic>>{};

  /// 热播位：5 个榜单分类各取首屏，按源顺序轮转交错。
  ///
  /// 上游 `rank_list` 只返回榜名、没有条目接口，因此热门由分类首屏合成；
  /// 这不是「七天榜」，文案不能写成统计窗口。
  static const hotCategories = [2, 1, 4, 5, 21];

  /// 详情 `vod_info` 原始载荷（选集/线路/简介共用一次网络往返）。
  /// 详情偶发限频短响应会缺 `vod_info`，不缓存失败形态。
  Future<Map<String, dynamic>> info(int id, {CancelToken? cancel}) async {
    final cached = _infoCache[id];
    if (cached != null) return cached;
    final response = await client.detail(id, cancel: cancel);
    final data = response['data'];
    final value = data is Map ? data['vod_info'] : null;
    if (value is! Map) {
      throw const SourceException('PROTOCOL', '作品资料不可用');
    }
    final info = Map<String, dynamic>.from(value);
    if (_infoCache.length > 24) _infoCache.remove(_infoCache.keys.first);
    _infoCache[id] = info;
    return info;
  }

  Future<WhiskletPage> browse(
    int category,
    int page, {
    CancelToken? cancel,
  }) async {
    final response = await client.videoList(category, page, cancel: cancel);
    return WhiskletPage(
      items: WhiskletWork.list(response['data']),
      page: WhiskletWork.count(response['page'], page),
      pages: WhiskletWork.count(response['pagecount'], page),
    );
  }

  Future<List<WhiskletShelf>> shelves({CancelToken? cancel}) async {
    final response = await client.recommend(cancel: cancel);
    final groups = response['data'] is Map
        ? (response['data'] as Map)['videos']
        : null;
    if (groups is! List) {
      throw const SourceException('PROTOCOL', '推荐片目不完整');
    }
    return [
      for (final group in groups)
        if (group is Map && group['vlist'] is List)
          WhiskletShelf(
            WhiskletWork.plain(group['name']),
            WhiskletWork.list(group['vlist']),
          ),
    ].where((shelf) => shelf.items.isNotEmpty).toList();
  }

  Future<List<WhiskletWork>> hot({CancelToken? cancel}) async {
    final boards = await Future.wait([
      for (final category in hotCategories) browse(category, 1, cancel: cancel),
    ]);
    final merged = <int, WhiskletWork>{};
    final seen = <int>{};
    // 轮转交错：每个分类轮流贡献一条，避免首页被单一风格整段占满。
    for (var index = 0; ; index++) {
      var added = false;
      for (final board in boards) {
        if (index >= board.items.length) continue;
        final work = board.items[index];
        if (seen.add(work.id)) merged[work.id] = work;
        added = true;
      }
      if (!added) break;
    }
    return merged.values.toList();
  }

  /// 详情线路：`vod_url_with_player` 每条线一个 `#` 分隔的选集表，
  /// `parse_api` 非空表示该线要经解析器换直链。
  Future<List<WhiskletLine>> lines(int id, {CancelToken? cancel}) async {
    final info = await this.info(id, cancel: cancel);
    return linesFrom(info);
  }

  List<WhiskletLine> linesFrom(Map<String, dynamic> info) {
    final rows = info['vod_url_with_player'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && WhiskletWork.plain(row['code']).isNotEmpty)
          WhiskletLine(
            code: WhiskletWork.plain(row['code']),
            name: WhiskletWork.plain(row['name']),
            parseApi: WhiskletWork.plain(row['parse_api']),
            episodes: _episodes(WhiskletWork.plain(row['url'])),
          ),
    ];
  }

  static List<WhiskletEpisode> _episodes(String table) {
    final items = <WhiskletEpisode>[];
    for (final entry in table.split('#')) {
      final split = entry.indexOf(r'$');
      if (split <= 0 || split == entry.length - 1) continue;
      final name = WhiskletWork.plain(entry.substring(0, split));
      final token = entry.substring(split + 1).trim();
      if (token.isEmpty) continue;
      final number = RegExp(
        r'^(?:第\s*)?(\d+)(?:\s*[集话話])?$',
      ).firstMatch(name)?.group(1);
      items.add(WhiskletEpisode(name, token, int.tryParse(number ?? '')));
    }
    return items;
  }

  void close() => client.close();
}
