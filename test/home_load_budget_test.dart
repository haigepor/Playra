import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/presentation/modern/home/home_anime_card.dart';
import 'package:kazumi/presentation/modern/home/home_display_session.dart';
import 'package:kazumi/presentation/modern/home/home_frame_updates.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/home_catalog.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';

void main() {
  testWidgets(
    'one source burst rebuilds content once and publishes latest state',
    (tester) async {
      final source = ValueNotifier(0);
      final updates = HomeFrameUpdates([source]);
      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListenableBuilder(
            listenable: updates,
            builder: (_, _) {
              builds++;
              return Text('${source.value}');
            },
          ),
        ),
      );
      for (var i = 1; i <= 100; i++) {
        source.value = i;
      }
      expect(builds, 1);
      await tester.pump();
      expect(builds, 2);
      expect(find.text('100'), findsOneWidget);
      source.value++;
      await tester.pumpWidget(const SizedBox.shrink());
      updates.dispose();
      source.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'schedule completion and history changes do not notify the whole home',
    () async {
      final detail = Completer<Map<String, dynamic>>();
      final home = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => [],
        loadCatalog: () async => const HomeCatalog(airing: {1: HomeAiring(1)}),
        loadDetail: (_) => detail.future,
      );
      addTearDown(home.dispose);
      await home.refreshCatalog();
      var root = 0, card = 0, history = 0;
      home.addListener(() => root++);
      home.scheduleChanges(1).addListener(() => card++);
      home.historyUpdates.addListener(() => history++);
      home.ensureSchedule(1);
      detail.complete({
        'infobox': [
          {'key': '放送时间', 'value': '21:05'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      home.reloadHistory();
      expect(root, 0);
      expect(card, 1);
      expect(history, 1);
      expect(home.schedules[1]!.time, '21:05');
    },
  );

  test(
    'home pagination keeps a small fixed window and ranks reuse its head',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = LuminaService(
        request: (op, payload, _) async {
          if (op == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '日漫'},
                ],
              },
            };
          }
          if (op == 'banners') {
            return {
              'data': {'banners': []},
            };
          }
          requests.add(payload);
          final size = payload['pageSize'] as int;
          final page = payload['pageIndex'] as int;
          return {
            'data': {
              'videos': List.generate(
                size,
                (i) => {'id': '${(page - 1) * size + i + 1}', 'title': '作品$i'},
              ),
              'pageInfo': {'total': 40},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap(warmOtherChannels: false);
      expect(home.items, hasLength(12));
      final rank = await service.catalog('1', size: 10);
      expect(rank.items.map((v) => v.id), home.items.take(10).map((v) => v.id));
      expect(requests, hasLength(1));
      await home.loadMoreIn('all');
      expect(requests.map((r) => r['pageSize']), [12, 12]);
      expect(home.items.map((v) => v.id), List.generate(24, (i) => '${i + 1}'));
    },
  );

  test('a display snapshot is reused until new identities are appended', () {
    final session = HomeDisplaySession();
    HomeAnimeCard card(String id) =>
        HomeAnimeCard(id: id, title: id, cover: '', onTap: () {});
    final first = session.append('main', [card('1')]);
    expect(identical(session.append('main', [card('1')]), first), isTrue);
    final next = session.append('main', [card('2'), card('1')]);
    expect(next.map((c) => c.id), ['1', '2']);
    expect(first.map((c) => c.id), ['1']);
    expect(() => next.add(card('3')), throwsUnsupportedError);
  });

  testWidgets('static loading placeholders do not keep scheduling frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 220,
            child: ContentSkeleton(animate: false, child: SkeletonPosterCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
