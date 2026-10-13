import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';

enum CalendarSort { schedule, popularity, rating }

typedef ScheduleLoader =
    Future<SeasonScheduleSnapshot> Function(
      DateTime season, {
      required bool force,
      required CancelToken cancelToken,
    });
typedef ScheduleEnricher =
    Future<ScheduleEntry> Function(
      ScheduleEntry entry, {
      required bool force,
      required CancelToken cancelToken,
    });
typedef CalendarPreferenceWriter =
    Future<void> Function({
      required bool watchingOnly,
      required bool hideWatched,
      required bool hideAbandoned,
    });

class ModernCalendarController extends ChangeNotifier {
  ModernCalendarController({
    required ScheduleLoader load,
    required Map<int, CollectType> Function() readCollections,
    required List<History> Function() readHistory,
    ScheduleEnricher? enrich,
    CalendarPreferenceWriter? writePreferences,
    Stream<void>? collectionChanges,
    Stream<void>? historyChanges,
    DateTime Function()? clock,
    this.watchingOnly = false,
    this.hideWatched = false,
    this.hideAbandoned = false,
  }) : _load = load,
       _enrich = enrich,
       _readCollections = readCollections,
       _readHistory = readHistory,
       _writePreferences = writePreferences,
       _clock = clock ?? DateTime.now {
    season = calendarSeason(_clock());
    weekday = _clock().weekday;
    reloadLocal();
    _collectionSubscription = collectionChanges?.listen((_) => reloadLocal());
    _historySubscription = historyChanges?.listen((_) => reloadLocal());
    _todayTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => updateToday(),
    );
  }
  final ScheduleLoader _load;
  final ScheduleEnricher? _enrich;
  final Map<int, CollectType> Function() _readCollections;
  final List<History> Function() _readHistory;
  final CalendarPreferenceWriter? _writePreferences;
  final DateTime Function() _clock;
  StreamSubscription<void>? _collectionSubscription, _historySubscription;
  Timer? _todayTimer, _detailTimer;
  CancelToken? _request;
  var _version = 0, _activeDetails = 0;
  var _disposed = false, _followToday = true, _forceDetails = false;
  bool _visible = true;
  final _detailQueue = <ScheduleEntry>[];
  final _detailSeen = <String>{};
  final _detailResults = <String, ScheduleEntry>{};
  Map<int, CollectType> _collections = {};
  Map<int, History> _history = {};

  late DateTime season;
  late int weekday;
  SeasonScheduleSnapshot? snapshot;
  bool loading = false, watchingOnly, hideWatched, hideAbandoned;
  ScheduleRegion region = ScheduleRegion.all;
  CalendarSort sort = CalendarSort.schedule;
  String? error;
  int get today => _clock().weekday;
  bool get currentSeason => season == calendarSeason(_clock());
  bool get isToday => currentSeason && weekday == today;
  bool get hasFilters =>
      watchingOnly ||
      hideWatched ||
      hideAbandoned ||
      region != ScheduleRegion.all;
  String get seasonLabel => '${season.year} · ${season.month}月';
  CollectType collectionFor(int id) => _collections[id] ?? CollectType.none;
  History? historyFor(int id) => _history[id];

  void reloadLocal() {
    if (_disposed) return;
    _collections = _readCollections();
    _history = {};
    for (final record in _readHistory()) {
      final previous = _history[record.bangumiItem.id];
      if (previous == null ||
          previous.lastWatchTime.isBefore(record.lastWatchTime)) {
        _history[record.bangumiItem.id] = record;
      }
    }
    notifyListeners();
  }

  bool _accept(ScheduleEntry entry) {
    final collected = collectionFor(entry.item.id);
    return (!watchingOnly || collected == CollectType.watching) &&
        (!hideWatched || collected != CollectType.watched) &&
        (!hideAbandoned || collected != CollectType.abandoned) &&
        (region == ScheduleRegion.all || entry.region == region);
  }

  List<ScheduleEntry> dayEntries([int? day]) =>
      _select((entry) => entry.weekday == (day ?? weekday));
  List<ScheduleEntry> get pendingEntries =>
      _select((entry) => entry.weekday == null);
  List<ScheduleEntry> _select(bool Function(ScheduleEntry) condition) {
    final entries = (snapshot?.entries ?? const <ScheduleEntry>[])
        .where((entry) => condition(entry) && _accept(entry))
        .toList();
    entries.sort(_compare);
    return entries;
  }

  int _compare(ScheduleEntry a, ScheduleEntry b) {
    int result;
    if (sort == CalendarSort.rating) {
      result = b.item.ratingScore.compareTo(a.item.ratingScore);
    } else if (sort == CalendarSort.popularity) {
      result = (b.watchers ?? b.item.votes).compareTo(
        a.watchers ?? a.item.votes,
      );
    } else {
      result = (a.time ?? '99:99').compareTo(b.time ?? '99:99');
    }
    if (result == 0) {
      result = (b.watchers ?? b.item.votes).compareTo(
        a.watchers ?? a.item.votes,
      );
    }
    if (result == 0) result = b.item.votes.compareTo(a.item.votes);
    return result == 0 ? a.item.id.compareTo(b.item.id) : result;
  }

  void selectWeekday(int value) {
    if (value < 1 || value > 7 || value == weekday) return;
    weekday = value;
    _followToday = false;
    notifyListeners();
  }

  Future<void> selectSeason(DateTime value) async {
    final selected = calendarSeason(value);
    if (selected == season) return;
    _followToday = false;
    season = selected;
    snapshot = null;
    await refresh(force: false);
  }

  Future<void> goToday() async {
    _followToday = true;
    weekday = today;
    if (!currentSeason) {
      season = calendarSeason(_clock());
      snapshot = null;
      await refresh(force: false);
    } else {
      notifyListeners();
    }
  }

  void updateToday() {
    if (_disposed) return;
    if (_followToday && currentSeason) weekday = today;
    notifyListeners();
  }

  Future<void> refresh({bool force = true}) async {
    final version = ++_version;
    _request?.cancel('日历请求已被替换');
    final token = _request = CancelToken();
    _detailTimer?.cancel();
    // 取消上一批提交后释放计时器，下一批详情才能重新安排提交。
    _detailTimer = null;
    _detailQueue.clear();
    _detailSeen.clear();
    _detailResults.clear();
    _forceDetails = force;
    loading = true;
    error = null;
    reloadLocal();
    try {
      final result = await _load(season, force: force, cancelToken: token);
      if (_disposed || version != _version || token.isCancelled) return;
      snapshot = result;
    } catch (_) {
      if (_disposed || version != _version || token.isCancelled) return;
      error = snapshot == null ? '暂时无法获取放送日历' : '刷新失败，保留上次的放送安排';
    } finally {
      if (!_disposed && version == _version) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setFilters({
    bool? watchingOnly,
    bool? hideWatched,
    bool? hideAbandoned,
    ScheduleRegion? region,
    CalendarSort? sort,
  }) async {
    this.watchingOnly = watchingOnly ?? this.watchingOnly;
    this.hideWatched = hideWatched ?? this.hideWatched;
    this.hideAbandoned = hideAbandoned ?? this.hideAbandoned;
    this.region = region ?? this.region;
    this.sort = sort ?? this.sort;
    notifyListeners();
    if (_writePreferences != null &&
        (watchingOnly != null ||
            hideWatched != null ||
            hideAbandoned != null)) {
      try {
        await _writePreferences(
          watchingOnly: this.watchingOnly,
          hideWatched: this.hideWatched,
          hideAbandoned: this.hideAbandoned,
        );
      } catch (_) {
        if (!_disposed) {
          error = '筛选设置未能保存';
          notifyListeners();
        }
      }
    }
  }

  Future<void> clearFilters() => setFilters(
    watchingOnly: false,
    hideWatched: false,
    hideAbandoned: false,
    region: ScheduleRegion.all,
  );

  /// 仅由已构建的可见卡片排队；详情失败不使整个日历失败。
  void queueDetail(ScheduleEntry entry) {
    if (_disposed ||
        _enrich == null ||
        loading ||
        _request == null ||
        entry.detailsLoaded) {
      return;
    }
    if (_detailSeen.add('${entry.weekday}:${entry.item.id}')) {
      _detailQueue.add(entry);
      _pumpDetails();
    }
  }

  void _pumpDetails() {
    while (!_disposed &&
        _visible &&
        _activeDetails < 3 &&
        _detailQueue.isNotEmpty) {
      final entry = _detailQueue.removeAt(0);
      final version = _version;
      final token = _request!;
      _activeDetails++;
      unawaited(
        _enrich!(entry, force: _forceDetails, cancelToken: token)
            .then((result) {
              if (_disposed || version != _version || token.isCancelled) return;
              _detailResults['${entry.weekday}:${entry.item.id}'] = result;
              _detailTimer ??= Timer(
                const Duration(milliseconds: 180),
                _flushDetails,
              );
            })
            .catchError((Object _) {})
            .whenComplete(() {
              _activeDetails--;
              _pumpDetails();
            }),
      );
    }
  }

  void setVisible(bool visible) {
    _visible = visible;
    if (visible) _pumpDetails();
  }

  void _flushDetails() {
    _detailTimer = null;
    if (_disposed || snapshot == null || _detailResults.isEmpty) return;
    final seen = <String>{};
    final updated = <ScheduleEntry>[];
    for (final entry in snapshot!.entries) {
      final next = _detailResults['${entry.weekday}:${entry.item.id}'] ?? entry;
      if (seen.add('${next.weekday}:${next.item.id}')) updated.add(next);
    }
    snapshot = snapshot!.withEntries(updated);
    _detailResults.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request?.cancel('离开放送日历');
    _todayTimer?.cancel();
    _detailTimer?.cancel();
    _collectionSubscription?.cancel();
    _historySubscription?.cancel();
    super.dispose();
  }
}
