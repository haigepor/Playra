import 'dart:async';

import 'package:flutter/foundation.dart';

import '../content_search.dart' show ContentGroup;
import 'whisklet_catalog.dart';
import 'whisklet_models.dart';

/// 首页风格频道：与上游 `tid` 一一对应（1 电影 / 2 电视剧 / 4 动漫 /
/// 5 综艺 / 21 短剧 / 22 AI 漫剧 / 20 电视直播）。
enum HomeStyle {
  movie('电影', 1, ContentGroup.screen),
  series('电视剧', 2, ContentGroup.series),
  anime('动漫', 4, ContentGroup.anime),
  variety('综艺', 5, ContentGroup.screen),
  shortDrama('短剧', 21, ContentGroup.series),
  aiComic('AI漫剧', 22, ContentGroup.comicDrama),
  live('电视直播', 20, ContentGroup.screen);

  const HomeStyle(this.label, this.tid, this.group);
  final String label;
  final int tid;
  final ContentGroup group;

  static HomeStyle? ofTid(int tid) {
    for (final style in values) {
      if (style.tid == tid) return style;
    }
    return null;
  }
}

/// 第二内容源（Whisklet）的目录状态：风格频道分页 + 热门合成 + 推荐分栏。
///
/// 动漫优先使用 Lumina，本控制器只在「动漫」需要副源货架时提供 `HomeStyle.anime`，
/// 其条目不参与首页首屏排序。
class WhiskletHomeController extends ChangeNotifier {
  WhiskletHomeController({WhiskletCatalog? catalog})
    : catalog = catalog ?? WhiskletCatalog();

  final WhiskletCatalog catalog;
  final Map<HomeStyle, List<WhiskletWork>> _items = {};
  final Map<HomeStyle, int> _page = {}, _pages = {};
  final Set<HomeStyle> _loading = {}, _failed = {};

  List<WhiskletShelf> shelves = const [];
  List<WhiskletWork> hot = const [];
  String? hotError, shelfError;
  bool hotLoading = false, shelfLoading = false;
  bool _disposed = false;

  List<WhiskletWork> of(HomeStyle style) => _items[style] ?? const [];
  bool loading(HomeStyle style) => _loading.contains(style);
  bool failed(HomeStyle style) => _failed.contains(style);
  bool hasMore(HomeStyle style) =>
      _failed.contains(style) == false &&
      (_page[style] ?? 0) < (_pages[style] ?? 0);

  Future<void> loadHot({bool refresh = false}) async {
    if (_disposed || hotLoading) return;
    if (!refresh && hot.isNotEmpty) return;
    hotLoading = true;
    hotError = null;
    _notify();
    try {
      hot = await catalog.hot();
      if (hot.isEmpty) hotError = 'EMPTY';
    } catch (_) {
      hotError = 'HOT';
    } finally {
      hotLoading = false;
      _notify();
    }
  }

  Future<void> loadShelves({bool refresh = false}) async {
    if (_disposed || shelfLoading) return;
    if (!refresh && shelves.isNotEmpty) return;
    shelfLoading = true;
    shelfError = null;
    _notify();
    try {
      shelves = await catalog.shelves();
      if (shelves.isEmpty) shelfError = 'EMPTY';
    } catch (_) {
      shelfError = 'RECOMMEND';
    } finally {
      shelfLoading = false;
      _notify();
    }
  }

  Future<void> loadStyle(HomeStyle style, {bool refresh = false}) async {
    if (_disposed || _loading.contains(style)) return;
    if (!refresh && (_items[style]?.isNotEmpty ?? false)) return;
    _loading.add(style);
    _failed.remove(style);
    if (refresh) {
      _items[style] = const [];
      _page.remove(style);
      _pages.remove(style);
    }
    _notify();
    try {
      final result = await catalog.browse(style.tid, 1);
      _items[style] = result.items;
      _page[style] = result.page;
      _pages[style] = result.pages;
    } catch (_) {
      _failed.add(style);
    } finally {
      _loading.remove(style);
      _notify();
    }
  }

  Future<void> loadMore(HomeStyle style) async {
    if (_disposed || _loading.contains(style) || !hasMore(style)) return;
    _loading.add(style);
    _notify();
    try {
      final result = await catalog.browse(style.tid, (_page[style] ?? 1) + 1);
      _items[style] = <int, WhiskletWork>{
        for (final work in [...of(style), ...result.items]) work.id: work,
      }.values.toList();
      _page[style] = result.page;
      _pages[style] = result.pages;
    } catch (_) {
      _failed.add(style);
    } finally {
      _loading.remove(style);
      _notify();
    }
  }

  void retry(HomeStyle style) {
    _failed.remove(style);
    unawaited(loadStyle(style, refresh: true));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    catalog.close();
    super.dispose();
  }
}
