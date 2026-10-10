import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'home_catalog.dart';
import 'home_content_algorithm.dart';

enum HomeFeed {
  recommended('推荐'),
  popular('热门'),
  anime('动漫'),
  movies('电影'),
  television('电视剧'),
  variety('综艺'),
  comicDrama('漫剧'),
  animeMovies('动漫电影'),
  season('新番'),
  japanese('日漫'),
  chinese('国漫');

  const HomeFeed(this.label);
  final String label;

  static const primaryCategories = [
    recommended,
    popular,
    anime,
    movies,
    television,
    variety,
    comicDrama,
  ];

  bool get isAnimeCategory =>
      this == anime ||
      this == season ||
      this == japanese ||
      this == chinese ||
      this == animeMovies;

  bool get hasContentSource =>
      this != movies &&
      this != television &&
      this != variety &&
      this != comicDrama;
}

typedef HomeFeedLoader =
    Future<List<BangumiItem>> Function(HomeFeed feed, int offset);

/// 新版仅拥有展示状态；收藏、观看历史和播放入口仍属于原有业务层。
class ModernHomeController extends ChangeNotifier {
  ModernHomeController({
    this.loadFeed = loadBangumiFeed,
    required this.readHistory,
    Stream<void>? historyChanges,
    this.loadCatalog,
    this.loadDetail,
  }) {
    reloadHistory();
    _historySubscription = historyChanges?.listen((_) => reloadHistory());
  }

  final HomeFeedLoader loadFeed;
  final Future<HomeCatalog> Function()? loadCatalog;
  final Future<Map<String, dynamic>> Function(int)? loadDetail;
  HomeCatalog catalog = const HomeCatalog();
  bool catalogLoading = false;
  final Map<int, HomeAiring> schedules = {};
  final Set<int> _scheduled = {};
  final List<int> _scheduleQueue = [];
  int _activeSchedules = 0, _catalogRequest = 0;
  Future<void>? _catalogFuture;
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
  int _featuredBatch = 0;
  static const featuredBatchSize = 4;

  List<BangumiItem> get featuredItems {
    if (_items.isEmpty) return const [];
    final count = _items.length < featuredBatchSize
        ? _items.length
        : featuredBatchSize;
    return List.generate(
      count,
      (i) => _items[(_featuredBatch * featuredBatchSize + i) % _items.length],
    );
  }

  void shuffleFeatured() {
    if (_disposed || _items.length <= featuredBatchSize) return;
    _featuredBatch++;
    notifyListeners();
  }

  HomeAnimeBucket get animeBucket => switch (feed) {
    HomeFeed.season => HomeAnimeBucket.season,
    HomeFeed.japanese => HomeAnimeBucket.japanese,
    HomeFeed.chinese => HomeAnimeBucket.chinese,
    HomeFeed.animeMovies => HomeAnimeBucket.movies,
    _ => HomeAnimeBucket.all,
  };

  List<HomeChannel> get channels =>
      catalog.algorithm?.channels(
        animeBucket,
        mode: feed == HomeFeed.recommended
            ? 'recommended'
            : feed == HomeFeed.popular
            ? 'popular'
            : 'anime',
      ) ??
      [];

  String scheduleLabel(BangumiItem item) {
    final subject = catalog.subjects[item.id];
    if (subject?.isMovie == true) {
      final date = subject!.releaseDate;
      return date == null
          ? '上映待定'
          : '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}上映';
    }
    return schedules[item.id]?.label ?? '时间待定';
  }

  static Future<List<BangumiItem>> loadBangumiFeed(
    HomeFeed feed,
    int offset,
  ) async {
    if (feed == HomeFeed.japanese || feed == HomeFeed.chinese) {
      final tag = feed == HomeFeed.japanese ? '日本' : '中国';
      return HomeCatalog.loadCategory(tag, limit: 24, offset: offset);
    }
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
    _featuredBatch = 0;
    _items = [];
    _offset = 0;
    hasMore = false;
    await _load(reset: true);
  }

  Future<void> refresh() async {
    if (loadCatalog != null) {
      await refreshCatalog();
      if (!_disposed) await _load(reset: true);
      return;
    }
    await Future.wait([
      _load(reset: true),
      if (feed.hasContentSource) refreshCatalog(),
    ]);
  }

  Future<void> refreshCatalog() => _catalogFuture ??= _refreshCatalog()
      .whenComplete(() => _catalogFuture = null);

  Future<void> _refreshCatalog() async {
    if (_disposed || loadCatalog == null) return;
    final request = ++_catalogRequest;
    catalogLoading = true;
    notifyListeners();
    try {
      final result = await loadCatalog!();
      if (_disposed || request != _catalogRequest) return;
      catalog = HomeCatalog(
        chinese: result.failed.contains('chinese')
            ? catalog.chinese
            : result.chinese,
        japanese: result.failed.contains('japanese')
            ? catalog.japanese
            : result.japanese,
        airing: !result.hasStructuredData || result.failed.contains('schedule')
            ? catalog.airing
            : result.airing,
        failed: result.failed,
        subjects: result.hasStructuredData ? result.subjects : catalog.subjects,
        algorithm: result.hasStructuredData
            ? result.algorithm
            : catalog.algorithm,
        source: result.source.entries.isNotEmpty
            ? result.source
            : catalog.source,
      );
      schedules
        ..clear()
        ..addAll(catalog.airing);
      _scheduled.clear();
      _scheduleQueue.clear();
    } catch (_) {
      if (_disposed || request != _catalogRequest) return;
      catalog = HomeCatalog(
        chinese: catalog.chinese,
        japanese: catalog.japanese,
        airing: catalog.airing,
        failed: {'chinese', 'japanese', 'schedule'},
        subjects: catalog.subjects,
        algorithm: catalog.algorithm,
        source: catalog.source,
      );
    } finally {
      if (!_disposed && request == _catalogRequest) {
        catalogLoading = false;
        notifyListeners();
      }
    }
  }

  /// 只补充可见海报的当前放送资料，最多三个并发，不阻塞封面显示。
  void ensureSchedule(int id) {
    if (_disposed ||
        loadDetail == null ||
        !schedules.containsKey(id) ||
        !_scheduled.add(id)) {
      return;
    }
    _scheduleQueue.add(id);
    _drainSchedules();
  }

  void _drainSchedules() {
    while (!_disposed && _activeSchedules < 3 && _scheduleQueue.isNotEmpty) {
      final id = _scheduleQueue.removeAt(0);
      _activeSchedules++;
      unawaited(_fetchSchedule(id, _catalogRequest));
    }
  }

  Future<void> _fetchSchedule(int id, int generation) async {
    try {
      final json = await loadDetail!(id);
      if (_disposed ||
          generation != _catalogRequest ||
          !schedules.containsKey(id)) {
        return;
      }
      schedules[id] = schedules[id]!.withDetail(json);
      notifyListeners();
    } catch (_) {
      // 缺失资料保留“待定”，不影响其他栏目和详情入口。
    } finally {
      _activeSchedules--;
      _drainSchedules();
    }
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed) return;
    final request = ++_request;
    final requestedFeed = feed;
    final offset = reset ? 0 : _offset;
    // 新主分类尚无对应内容源，清空旧结果并使旧请求失效，避免串入动漫。
    if (!requestedFeed.hasContentSource) {
      _items = [];
      loading = false;
      hasMore = false;
      error = null;
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      late final List<BangumiItem> fetched;
      if (loadCatalog != null) {
        if (_catalogFuture != null) await _catalogFuture;
        if (_disposed || request != _request) return;
        if (!catalog.hasStructuredData) {
          error = '暂时无法获取分类数据，请稍后重试';
          return;
        }
        fetched =
            requestedFeed == HomeFeed.recommended ||
                requestedFeed == HomeFeed.popular ||
                requestedFeed == HomeFeed.anime
            ? catalog.algorithm!.balanced(
                popular: requestedFeed == HomeFeed.popular,
              )
            : catalog.select(animeBucket);
      } else {
        fetched = await loadFeed(requestedFeed, offset);
      }
      // 切换分类、再次刷新或销毁页面后，旧请求不能覆盖当前结果。
      if (_disposed || request != _request) return;
      if (reset && fetched.isEmpty) {
        _items = [];
        error = '这个分类暂时没有符合条件的作品';
        return;
      }
      final merged = <int, BangumiItem>{
        if (!reset)
          for (final item in _items) item.id: item,
        for (final item in fetched) item.id: item,
      };
      final added = reset ? merged.length : merged.length - _items.length;
      _items = merged.values.toList();
      if (reset) _featuredBatch = 0;
      if (requestedFeed == HomeFeed.recommended && loadCatalog == null) {
        _items.sort((a, b) => b.ratingScore.compareTo(a.ratingScore));
      }
      _offset = offset + fetched.length;
      hasMore =
          loadCatalog == null &&
          requestedFeed != HomeFeed.season &&
          fetched.length >= 24 &&
          added > 0;
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
