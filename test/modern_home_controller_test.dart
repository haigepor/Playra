import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';

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
