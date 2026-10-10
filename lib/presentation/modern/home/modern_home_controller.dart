import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';

enum HomeFeed {
  recommended('推荐'),
  popular('热门'),
  season('新番');

  const HomeFeed(this.label);
  final String label;
}

typedef HomeFeedLoader =
    Future<List<BangumiItem>> Function(HomeFeed feed, int offset);

/// 新版仅拥有展示状态；收藏、观看历史和播放入口仍属于原有业务层。
class ModernHomeController extends ChangeNotifier {
  ModernHomeController({
    this.loadFeed = loadBangumiFeed,
    required this.readHistory,
    Stream<void>? historyChanges,
  }) {
    reloadHistory();
    _historySubscription = historyChanges?.listen((_) => reloadHistory());
  }

  final HomeFeedLoader loadFeed;
  final List<History> Function() readHistory;
  StreamSubscription<void>? _historySubscription;
  HomeFeed feed = HomeFeed.recommended;
  List<BangumiItem> _items = [];
  List<History> _recent = [];
  List<BangumiItem> get items => List.unmodifiable(_items);
  List<History> get recent => List.unmodifiable(_recent);
  bool loading = false;
  bool hasMore = false;
  String? error;
  int _offset = 0;
  int _request = 0;
  bool _disposed = false;

  static Future<List<BangumiItem>> loadBangumiFeed(
    HomeFeed feed,
    int offset,
  ) async {
    if (feed == HomeFeed.season) {
      return (await BangumiApi.getCalendar()).expand((day) => day).toList()
        ..sort((a, b) => b.airDate.compareTo(a.airDate));
    }
    return BangumiAcceleration.current == BangumiAcceleration.mirror
        ? BangumiApi.getBangumiMirrorPopularSubjects(offset: offset)
        : BangumiApi.getBangumiTrendsList(offset: offset);
  }

  void reloadHistory() {
    if (_disposed) return;
    final seen = <int>{};
    final sorted = [...readHistory()]
      ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    _recent = sorted
        .where((entry) => seen.add(entry.bangumiItem.id))
        .take(10)
        .toList();
    notifyListeners();
  }

  Future<void> selectFeed(HomeFeed next) async {
    if (_disposed || next == feed) return;
    feed = next;
    _items = [];
    _offset = 0;
    hasMore = false;
    await refresh();
  }

  Future<void> refresh() => _load(reset: true);
  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed) return;
    final request = ++_request;
    final requestedFeed = feed;
    final offset = reset ? 0 : _offset;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final fetched = await loadFeed(requestedFeed, offset);
      // 切换分类、再次刷新或销毁页面后，旧请求不能覆盖当前结果。
      if (_disposed || request != _request) return;
      if (reset && fetched.isEmpty) {
        error = '暂时无法获取番剧，请检查网络后重试';
        return;
      }
      final merged = <int, BangumiItem>{
        if (!reset)
          for (final item in _items) item.id: item,
        for (final item in fetched) item.id: item,
      };
      final added = reset ? merged.length : merged.length - _items.length;
      _items = merged.values.toList();
      if (requestedFeed == HomeFeed.recommended) {
        _items.sort((a, b) => b.ratingScore.compareTo(a.ratingScore));
      }
      _offset = offset + fetched.length;
      hasMore =
          requestedFeed != HomeFeed.season && fetched.length >= 24 && added > 0;
    } catch (_) {
      if (!_disposed && request == _request) error = '加载失败，请稍后重试';
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _historySubscription?.cancel();
    super.dispose();
  }
}
