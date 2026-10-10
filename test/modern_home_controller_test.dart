import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/home_catalog.dart';

BangumiItem item(int id) => BangumiItem(
  id: id,
  type: 2,
  name: 'Anime $id',
  nameCn: '番剧 $id',
  summary: '',
  airDate: '',
  airWeekday: 1,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 8,
  votes: 1,
  votesCount: [],
  info: '',
);

void main() {
  test(
    'one failed category retains its data without blocking other categories',
    () async {
      var fail = false;
      final controller = ModernHomeController(
        loadFeed: (_, _) async => [item(1)],
        readHistory: () => [],
        loadCatalog: () async => fail
            ? HomeCatalog(japanese: [item(4)], failed: {'chinese'})
            : HomeCatalog(chinese: [item(2)], japanese: [item(3)]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      fail = true;
      await controller.refreshCatalog();
      expect(controller.catalog.chinese.single.id, 2);
      expect(controller.catalog.japanese.single.id, 4);
      expect(controller.catalog.failed, {'chinese'});
      expect(controller.items.single.id, 1);
    },
  );
  test(
    'visible airing requests are deduplicated, bounded and ignored after refresh',
    () async {
      final requests = <int, Completer<Map<String, dynamic>>>{};
      final controller = ModernHomeController(
        loadFeed: (_, _) async => [item(1)],
        readHistory: () => [],
        loadCatalog: () async => HomeCatalog(
          airing: {for (var i = 1; i <= 5; i++) i: const HomeAiring(6)},
        ),
        loadDetail: (id) =>
            (requests[id] = Completer<Map<String, dynamic>>()).future,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      for (var i = 1; i <= 5; i++) {
        controller.ensureSchedule(i);
        controller.ensureSchedule(i);
      }
      controller.ensureSchedule(99);
      expect(requests.length, 3);
      await controller.refreshCatalog();
      for (final pending in requests.values) {
        pending.complete({
          'infobox': [
            {'key': '放送时间', 'value': '21:05'},
          ],
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(controller.schedules[1]!.time, isNull);
      expect(requests.length, 3);
    },
  );
  test(
    'switching feeds ignores a late result from the previous feed',
    () async {
      final first = Completer<List<BangumiItem>>();
      final controller = ModernHomeController(
        loadFeed: (feed, offset) => feed == HomeFeed.recommended
            ? first.future
            : Future.value([item(2)]),
        readHistory: () => [],
      );
      addTearDown(controller.dispose);
      final initial = controller.refresh();
      await controller.selectFeed(HomeFeed.popular);
      first.complete([item(1)]);
      await initial;
      expect(controller.items.map((e) => e.id), [2]);
      expect(controller.loading, isFalse);
    },
  );

  test(
    'pagination advances by raw results and stops on duplicate-only pages',
    () async {
      final offsets = <int>[];
      final controller = ModernHomeController(
        loadFeed: (feed, offset) async {
          offsets.add(offset);
          return List.generate(24, (i) => item(i));
        },
        readHistory: () => [],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.loadMore();
      await controller.loadMore();
      expect(offsets, [0, 24]);
      expect(controller.items.length, 24);
      expect(controller.hasMore, isFalse);
    },
  );

  test('failed refresh preserves data and can be retried', () async {
    var fail = false;
    final controller = ModernHomeController(
      loadFeed: (feed, offset) async {
        if (fail) throw StateError('network down');
        return [item(1)];
      },
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    fail = true;
    await controller.refresh();
    expect(controller.items.single.id, 1);
    expect(controller.error, isNotNull);
    fail = false;
    await controller.refresh();
    expect(controller.error, isNull);
  });

  test(
    'history changes show newest entry per subject and clear immediately',
    () async {
      final changes = StreamController<void>.broadcast(sync: true);
      var history = [
        History(item(1), 1, 'a', DateTime(2026, 1, 1), '', ''),
        History(item(2), 2, 'b', DateTime(2026, 1, 3), '', ''),
        History(item(1), 3, 'c', DateTime(2026, 1, 2), '', ''),
      ];
      final controller = ModernHomeController(
        loadFeed: (feed, offset) async => [],
        readHistory: () => history,
        historyChanges: changes.stream,
      );
      expect(controller.recent.map((e) => e.lastWatchEpisode), [2, 3]);
      history = [];
      changes.add(null);
      expect(controller.recent, isEmpty);
      controller.dispose();
      await changes.close();
    },
  );

  test(
    'dispose prevents async notification and releases history subscription',
    () async {
      final pending = Completer<List<BangumiItem>>();
      final changes = StreamController<void>.broadcast(sync: true);
      final controller = ModernHomeController(
        loadFeed: (feed, offset) => pending.future,
        readHistory: () => [],
        historyChanges: changes.stream,
      );
      final request = controller.refresh();
      controller.dispose();
      pending.complete([item(1)]);
      await request;
      expect(changes.hasListener, isFalse);
      await changes.close();
    },
  );
}
