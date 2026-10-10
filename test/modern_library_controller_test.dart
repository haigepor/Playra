import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/library/modern_library_controller.dart';

BangumiItem item(int id, String title) => BangumiItem.fromJson({
  'id': id,
  'name': title,
  'images': <String, String>{},
  'rating': {},
});

void main() {
  test('最近观看不使用收藏变更时间，保留最近记录完整来源', () {
    final first = item(1, '一');
    final second = item(2, '二');
    final latest = History(
      first,
      7,
      '来源B',
      DateTime(2026, 10, 11),
      '/b',
      '第七话',
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: '/episode/b',
    );
    final controller = ModernLibraryController(
      readCollections: () => [
        CollectedBangumi(second, DateTime(2026, 10, 12), 1),
        CollectedBangumi(first, DateTime(2020), 1),
      ],
      readHistory: () => [
        History(first, 3, '来源A', DateTime(2026, 10, 1), '/a', ''),
        latest,
        History(second, 1, '来源C', DateTime(2026, 10, 10), '/c', ''),
      ],
    );
    addTearDown(controller.dispose);
    expect(controller.entries.map((e) => e.item.id), [1, 2]);
    expect(controller.entries.first.history, same(latest));
    expect(
      controller.entries.first.history!.entryKind,
      HistoryEntryKind.offline,
    );
    controller.setSort(LibrarySort.recentlyChanged);
    expect(controller.entries.map((e) => e.item.id), [2, 1]);
  });

  test('搜索别名和状态筛选不改变全局状态计数，无效状态不显示', () {
    final first = item(1, '甲')..alias = ['Alpha Hero'];
    final controller = ModernLibraryController(
      readCollections: () => [
        CollectedBangumi(first, DateTime(2026), 1),
        CollectedBangumi(item(2, '乙'), DateTime(2026), 2),
        CollectedBangumi(item(3, '无效'), DateTime(2026), 0),
      ],
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    controller.setQuery(' alpha HERO ');
    expect(controller.entries.single.item.id, 1);
    expect(controller.count(null), 2);
    expect(controller.count(CollectType.planToWatch), 1);
    controller.selectCategory(CollectType.planToWatch);
    expect(controller.entries, isEmpty);
    controller.setQuery('');
    expect(controller.entries.single.item.id, 2);
  });

  test('零进度只展示剧集，不推断看完或百分比', () {
    final bangumi = item(1, '甲');
    final history = History(bangumi, 7, '来源', DateTime(2026), '/a', '')
      ..progresses[7] = Progress(7, 0, 0);
    final controller = ModernLibraryController(
      readCollections: () => [CollectedBangumi(bangumi, DateTime(2026), 1)],
      readHistory: () => [history],
    );
    addTearDown(controller.dispose);
    expect(controller.entries.single.episodeLabel, '上次看到第7话');
    expect(controller.entries.single.positionLabel, isNull);
    history.progresses[7]!.progress = const Duration(minutes: 12, seconds: 34);
    controller.reloadLocal();
    expect(controller.entries.single.positionLabel, '12:34');
  });

  test('收藏变更立即刷新，历史事件合并后刷新，销毁后不再更新', () async {
    final collections = StreamController<void>.broadcast(sync: true);
    final histories = StreamController<void>.broadcast(sync: true);
    final records = <CollectedBangumi>[];
    final watches = <History>[];
    final controller = ModernLibraryController(
      readCollections: () => records,
      readHistory: () => watches,
      collectionChanges: collections.stream,
      historyChanges: histories.stream,
    );
    records.add(CollectedBangumi(item(1, '甲'), DateTime(2026), 1));
    collections.add(null);
    expect(controller.entries.length, 1);
    watches.add(
      History(records.first.bangumiItem, 2, '来源', DateTime(2026), '/a', '第二话'),
    );
    histories.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(controller.entries.single.episodeLabel, '上次看到第二话');
    records.clear();
    collections.add(null);
    expect(controller.entries, isEmpty);
    controller.dispose();
    histories.add(null);
    await collections.close();
    await histories.close();
  });

  test('远端写入静默失败不提前改变状态，重复点击只提交一次', () async {
    final record = CollectedBangumi(item(1, '甲'), DateTime(2026), 1);
    final write = Completer<void>();
    var calls = 0;
    final controller = ModernLibraryController(
      readCollections: () => [record],
      readHistory: () => [],
      changeCollection: (_, type) {
        calls++;
        return write.future;
      },
    );
    addTearDown(controller.dispose);
    final pending = controller.changeStatus(
      record.bangumiItem,
      CollectType.watched,
    );
    expect(controller.canEdit(record.bangumiItem.id), isFalse);
    expect(
      await controller.changeStatus(record.bangumiItem, CollectType.watched),
      isFalse,
    );
    write.complete();
    expect(await pending, isFalse);
    expect(calls, 1);
    expect(controller.entries.single.status, CollectType.watching);
    expect(controller.canEdit(record.bangumiItem.id), isTrue);
  });

  test('真实写入与删除刷新，异常后释放操作锁', () async {
    final records = [CollectedBangumi(item(1, '甲'), DateTime(2026), 1)];
    var fail = false;
    final controller = ModernLibraryController(
      readCollections: () => records,
      readHistory: () => [],
      changeCollection: (_, type) async {
        if (fail) throw StateError('offline');
        if (type == CollectType.none) {
          records.clear();
        } else {
          records.first.type = type.value;
        }
      },
    );
    addTearDown(controller.dispose);
    expect(
      await controller.changeStatus(
        records.first.bangumiItem,
        CollectType.watched,
      ),
      isTrue,
    );
    controller.selectCategory(null);
    expect(controller.entries.single.status, CollectType.watched);
    fail = true;
    expect(
      await controller.changeStatus(
        records.first.bangumiItem,
        CollectType.watching,
      ),
      isFalse,
    );
    expect(controller.mutationError, isNotNull);
    expect(controller.hasPendingChanges, isFalse);
    fail = false;
    expect(
      await controller.changeStatus(
        records.first.bangumiItem,
        CollectType.none,
      ),
      isTrue,
    );
    expect(controller.entries, isEmpty);
  });
}
