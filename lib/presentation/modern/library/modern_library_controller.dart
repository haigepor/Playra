import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_library_query.dart';

enum LibrarySort {
  recentlyWatched('最近观看', null),
  recentlyChanged('最近变更', CollectSort.recentlyChanged),
  title('番剧名称', CollectSort.title),
  rating('评分最高', CollectSort.rating),
  airDate('开播时间', CollectSort.airDate);

  const LibrarySort(this.label, this.collectionSort);
  final String label;
  final CollectSort? collectionSort;
}

class LibraryEntry {
  const LibraryEntry(this.collection, this.history);
  final CollectedBangumi collection;
  final History? history;
  BangumiItem get item => collection.bangumiItem;
  CollectType get status => CollectType.fromValue(collection.type);
  String get title => CollectLibraryQuery.titleOf(collection);
  String get episodeLabel {
    final value = history;
    if (value == null) return '尚无观看记录';
    final title = value.lastWatchEpisodeName.trim();
    return '上次看到${title.isEmpty ? '第${value.lastWatchEpisode}话' : title}';
  }

  // 零进度也可能是播放器归一化后的近结尾记录，不能据此推断看完。
  String? get positionLabel {
    final value = history;
    final progress = value?.progresses[value.lastWatchEpisode]?.progress;
    if (progress == null || progress <= Duration.zero) return null;
    final seconds = (progress.inSeconds % 60).toString().padLeft(2, '0');
    final minutes = (progress.inMinutes % 60).toString().padLeft(2, '0');
    return progress.inHours > 0
        ? '${progress.inHours}:$minutes:$seconds'
        : '${progress.inMinutes}:$seconds';
  }
}

/// 只维护新版界面的派生状态，收藏写入仍走共享控制器与原有同步流程。
class ModernLibraryController extends ChangeNotifier {
  ModernLibraryController({
    required this.readCollections,
    required this.readHistory,
    this.changeCollection,
    Stream<void>? collectionChanges,
    Stream<void>? historyChanges,
    this.layout = CollectLayout.list,
  }) {
    reloadLocal();
    _collectionSubscription = collectionChanges?.listen((_) => reloadLocal());
    _historySubscription = historyChanges?.listen((_) {
      // 播放进度可能连续写入，合并同一帧附近的变化，避免每条事件重排列表。
      _historyTimer ??= Timer(const Duration(milliseconds: 160), () {
        _historyTimer = null;
        reloadLocal();
      });
    });
  }

  final List<CollectedBangumi> Function() readCollections;
  final List<History> Function() readHistory;
  final Future<void> Function(BangumiItem, CollectType)? changeCollection;
  StreamSubscription<void>? _collectionSubscription, _historySubscription;
  Timer? _historyTimer;
  bool _disposed = false;
  List<CollectedBangumi> _collections = [];
  Map<int, History> _history = {};
  final Set<int> _pendingIds = {};
  CollectType? category = CollectType.watching;
  LibrarySort sort = LibrarySort.recentlyWatched;
  CollectLayout layout;
  String query = '';
  String? error, mutationError;
  bool locked = false;
  bool get hasPendingChanges => _pendingIds.isNotEmpty;
  bool canEdit(int id) => !locked && !_pendingIds.contains(id);
  bool isPending(int id) => _pendingIds.contains(id);
  bool get canSync => !locked && !hasPendingChanges;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void reloadLocal() {
    if (_disposed) return;
    try {
      final collections = readCollections().toList();
      final history = <int, History>{};
      for (final value in readHistory()) {
        if (value.lastWatchEpisode <= 0) continue;
        final current = history[value.bangumiItem.id];
        if (current == null ||
            value.lastWatchTime.isAfter(current.lastWatchTime)) {
          // 取完整记录，不拼接不同来源、线路或线上/离线历史。
          history[value.bangumiItem.id] = value;
        }
      }
      _collections = collections;
      _history = history;
      error = null;
    } catch (_) {
      error = '暂时无法读取追番，点击重试';
    }
    _notify();
  }

  int count(CollectType? type) =>
      CollectLibraryQuery(_collections, '').count(type);

  List<LibraryEntry> get entries {
    final collections = CollectLibraryQuery(
      _collections,
      query,
    ).results(category, sort.collectionSort ?? CollectSort.recentlyChanged);
    if (sort == LibrarySort.recentlyWatched) {
      final order = {
        for (var i = 0; i < collections.length; i++) collections[i].key: i,
      };
      collections.sort((a, b) {
        final aTime = _history[a.bangumiItem.id]?.lastWatchTime;
        final bTime = _history[b.bangumiItem.id]?.lastWatchTime;
        final comparison = aTime == null
            ? (bTime == null ? 0 : 1)
            : (bTime == null ? -1 : bTime.compareTo(aTime));
        return comparison != 0
            ? comparison
            : order[a.key]!.compareTo(order[b.key]!);
      });
    }
    return [
      for (final entry in collections)
        LibraryEntry(entry, _history[entry.bangumiItem.id]),
    ];
  }

  void selectCategory(CollectType? value) {
    if (category == value) return;
    category = value;
    _notify();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _notify();
  }

  void setSort(LibrarySort value) {
    if (sort == value) return;
    sort = value;
    _notify();
  }

  void setLayout(CollectLayout value) {
    if (layout == value) return;
    layout = value;
    _notify();
  }

  void setLocked(bool value) {
    locked = value;
    _notify();
  }

  Future<bool> changeStatus(BangumiItem item, CollectType value) async {
    if (_disposed || !canEdit(item.id) || changeCollection == null) {
      return false;
    }
    _pendingIds.add(item.id);
    mutationError = null;
    _notify();
    try {
      await changeCollection!(item, value);
      if (_disposed) return false;
      reloadLocal();
      // 旧控制器同步失败或用户取消删除时可能正常返回，必须核对真实状态。
      final actual = _collections.where((e) => e.bangumiItem.id == item.id);
      return error == null &&
          (actual.isEmpty
              ? value == CollectType.none
              : actual.single.type == value.value);
    } catch (_) {
      mutationError = '修改收藏状态失败，请稍后重试';
      reloadLocal();
      return false;
    } finally {
      _pendingIds.remove(item.id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _historyTimer?.cancel();
    unawaited(_collectionSubscription?.cancel());
    unawaited(_historySubscription?.cancel());
    super.dispose();
  }
}
