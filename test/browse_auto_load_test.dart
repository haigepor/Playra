import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_browse.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'modern_home_controller_test.dart' show item;
import 'modern_home_view_test.dart' show mountHome;

Map<String, dynamic> moviePage(int page) => {
  'data': {
    'videos': List.generate(
      20,
      (i) => {
        'id': '${(page - 1) * 20 + i + 1}',
        'title': '电影${(page - 1) * 20 + i}',
        'categoryName': '电影大全',
      },
    ),
    'pageinfo': {'total': 40},
  },
};

void main() {
  testWidgets('more page returns through the Navigator that opened it', (
    tester,
  ) async {
    final service = MioMediaService(request: (_, _, _) async => moviePage(1));
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MioBrowsePage(
                    service: service,
                    categoryId: '42',
                    onDetails: (_) {},
                  ),
                ),
              ),
              child: const Text('打开电影'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开电影'));
    await tester.pumpAndSettle();
    expect(find.byType(MioBrowsePage), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(MioBrowsePage), findsNothing);
    expect(find.text('打开电影'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'anime next-page failure retains data and retries the same page',
    () async {
      var fail = true;
      final pages = <int>[];
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
          final page = payload['pageIndex'] as int;
          pages.add(page);
          if (page == 2 && fail) throw StateError('offline');
          return {
            'data': {
              'videos': List.generate(
                12,
                (i) => {'id': '${(page - 1) * 12 + i}', 'title': '动漫$i'},
              ),
              'pageInfo': {'total': 24},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap(warmOtherChannels: false);
      await home.loadMoreIn('all');
      expect(home.items, hasLength(12));
      expect(home.pageFailedIn('all'), isTrue);
      expect(home.hasMoreIn('all'), isTrue);
      fail = false;
      await home.loadMoreIn('all');
      expect(pages, [1, 2, 2]);
      expect(home.items, hasLength(24));
      expect(home.pageFailedIn('all'), isFalse);
      expect(home.hasMoreIn('all'), isFalse);
    },
  );

  testWidgets('film auto paging pauses after error until manual retry', (
    tester,
  ) async {
    final requests = <int>[];
    var fail = true;
    final service = MioMediaService(
      request: (_, payload, _) async {
        final page = payload['pageIndex'] as int;
        requests.add(page);
        if (page == 2 && fail) throw StateError('offline');
        return moviePage(page);
      },
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MioBrowsePage(
          service: service,
          categoryId: '42',
          kind: MioKind.movie,
          onDetails: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.flingFrom(
      const Offset(400, 300),
      const Offset(0, -5000),
      4000,
    );
    await tester.pumpAndSettle();
    await tester.flingFrom(
      const Offset(400, 300),
      const Offset(0, -1000),
      1500,
    );
    await tester.pumpAndSettle();
    expect(requests, [1, 2]);
    fail = false;
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 2]);
    expect(find.text('加载失败，请重试'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('film more loads next page once at bottom and stops at end', (
    tester,
  ) async {
    final requests = <int>[];
    final pending = Completer<Map<String, dynamic>>();
    final service = MioMediaService(
      request: (_, payload, _) async {
        final page = payload['pageIndex'] as int;
        requests.add(page);
        return page == 1 ? moviePage(page) : pending.future;
      },
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MioBrowsePage(
          service: service,
          categoryId: '42',
          kind: MioKind.movie,
          onDetails: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, [1]);
    await tester.flingFrom(
      const Offset(400, 300),
      const Offset(0, -5000),
      4000,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(requests, [1, 2]);
    await tester.flingFrom(const Offset(400, 300), const Offset(0, -500), 1000);
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, [1, 2], reason: '加载期间滚动不能重复请求同一页');
    pending.complete(moviePage(2));
    await tester.pumpAndSettle();
    await tester.flingFrom(
      const Offset(400, 300),
      const Offset(0, -6000),
      4000,
    );
    await tester.pumpAndSettle();
    expect(requests, [1, 2]);
    expect(find.text('电影39'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('film more does not build all offscreen posters', (tester) async {
    final service = MioMediaService(request: (_, _, _) async => moviePage(1));
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MioBrowsePage(
          service: service,
          categoryId: '42',
          kind: MioKind.movie,
          onDetails: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MioPoster).evaluate().length, lessThan(20));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('anime more sheet loads next page by scrolling', (tester) async {
    final offsets = <int>[];
    final next = Completer<List<BangumiItem>>();
    final home = ModernHomeController(
      readHistory: () => [],
      loadFeed: (_, offset) async {
        offsets.add(offset);
        if (offset == 0) return List.generate(24, item);
        return next.future;
      },
    );
    addTearDown(home.dispose);
    await home.refresh();
    await mountHome(tester, home);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-more-anime')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('home-more-anime')));
    await tester.pumpAndSettle();
    final grid = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.fling(grid, const Offset(0, -5000), 4000);
    await tester.pump(const Duration(seconds: 1));
    expect(offsets, [0, 24]);
    next.complete(List.generate(24, (i) => item(i + 24)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
