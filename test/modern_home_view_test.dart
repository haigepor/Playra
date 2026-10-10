import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'modern_home_controller_test.dart' show item;
import 'package:kazumi/presentation/modern/home/home_catalog.dart';

Future<void> mountHome(
  WidgetTester tester,
  ModernHomeController controller, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  VoidCallback? onSearch,
  VoidCallback? onCalendar,
  ValueChanged<String>? onBrowse,
  VoidCallback? onHistory,
  VoidCallback? onTheme,
  ValueChanged<History>? onResume,
  ValueChanged<int>? onDetails,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ModernHomeView(
        controller: controller,
        onSearch: onSearch ?? () {},
        onCalendar: onCalendar ?? () {},
        onBrowse: onBrowse ?? (_) {},
        onHistory: onHistory ?? () {},
        onToggleTheme: onTheme ?? () {},
        onDetails: (subject) => onDetails?.call(subject.id),
        onResume: onResume ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'category rails scroll independently and expose more and corner metadata',
    (tester) async {
      String? opened;
      final controller = ModernHomeController(
        loadFeed: (_, _) async => List.generate(24, item),
        readHistory: () => [],
        loadCatalog: () async => HomeCatalog(
          chinese: List.generate(10, (i) => item(i + 100)),
          japanese: List.generate(10, (i) => item(i + 200)),
          airing: {0: const HomeAiring(6, '21:05')},
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(tester, controller, onBrowse: (tag) => opened = tag);
      final rail = find.byKey(const PageStorageKey('home-channel-main'));
      final poster = find.byKey(const ValueKey('home-poster-0'));
      final rating = tester.getTopLeft(
        find.byKey(const ValueKey('home-rating-0')),
      );
      final airing = tester.getBottomRight(
        find.byKey(const ValueKey('home-airing-0')),
      );
      expect(rating, tester.getTopLeft(poster));
      expect(airing.dy, greaterThan(rating.dy + 100));
      expect(airing.dx, greaterThan(rating.dx + 80));
      final time = tester.widget<Text>(
        find.byKey(const ValueKey('home-airing-0')),
      );
      expect(time.data, '周六 | 21:05');
      expect(time.style!.backgroundColor, isNull);
      expect(time.style!.shadows, isNull);
      expect(
        find.byTooltip('资料收录的放送安排（原播出地时间），非播放源更新时间；未收录时显示待定。'),
        findsNothing,
      );
      expect(Theme.of(tester.element(poster)).brightness, Brightness.dark);
      expect(tester.widget<InkWell>(poster).hoverColor, Colors.transparent);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('home-cover-scale-0'))),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('home-cover-scale-0')),
            )
            .scale,
        greaterThan(1),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('home-cover-scale-0')),
            )
            .scale,
        1,
      );
      await mouse.removePointer();
      final scrollable = find
          .descendant(of: rail, matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(rail, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(before),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-more-chinese')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('home-more-chinese')));
      expect(opened, '中国');
      expect(find.text('左右滑动'), findsNothing);
      expect(find.byKey(const ValueKey('home-load-more')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact channels support dragging the selector and omit pagination',
    (tester) async {
      final controller = ModernHomeController(
        loadFeed: (feed, _) async =>
            List.generate(24, (i) => item(i + feed.index * 100)),
        readHistory: () => [],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(tester, controller);
      expect(find.text('找到今天的心动番剧'), findsNothing);
      expect(find.byKey(const ValueKey('home-load-more')), findsNothing);
      final start = tester.getCenter(
        find.byKey(const ValueKey('home-feed-recommended')),
      );
      final end = tester.getCenter(
        find.byKey(const ValueKey('home-feed-season')),
      );
      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();
      expect(controller.feed, HomeFeed.season);
      expect(
        find.byKey(const PageStorageKey('home-channel-main')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      testWidgets('loaded home at $size, dark=$dark, enlarged text', (
        tester,
      ) async {
        final history = History(item(9), 3, 'test', DateTime(2026), '', '');
        history.progresses[3] = Progress(3, 0, 503000);
        final controller = ModernHomeController(
          loadFeed: (_, _) async => List.generate(6, item),
          readHistory: () => [history],
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        await mountHome(tester, controller, size: size, scale: 1.6, dark: dark);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-poster-0')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-poster-0')), findsWidgets);
      });
    }
  }

  testWidgets(
    'search, calendar, details and resume preserve callbacks and identity',
    (tester) async {
      var searches = 0, calendars = 0;
      int? details;
      History? resumed;
      final history = History(item(9), 3, 'test', DateTime(2026), '', '');
      history.progresses[3] = Progress(3, 0, 503000);
      final controller = ModernHomeController(
        loadFeed: (_, _) async => [item(1)],
        readHistory: () => [history],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(
        tester,
        controller,
        onSearch: () => searches++,
        onCalendar: () => calendars++,
        onDetails: (id) => details = id,
        onResume: (entry) => resumed = entry,
      );
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-calendar')));
      await tester.tap(find.byKey(const ValueKey('home-featured-details')));
      await tester.ensureVisible(
        find.byKey(ValueKey('home-resume-${history.key}')),
      );
      await tester.tap(find.byKey(ValueKey('home-resume-${history.key}')));
      expect(searches, 1);
      expect(calendars, 1);
      expect(find.byKey(const ValueKey('home-history')), findsNothing);
      expect(find.byKey(const ValueKey('home-theme')), findsNothing);
      expect(details, 1);
      expect(resumed, same(history));
      expect(find.text('第 3 集 · 8:23'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feed selection loads new subjects and retry recovers an empty response',
    (tester) async {
      var empty = true;
      final controller = ModernHomeController(
        loadFeed: (feed, _) async => empty ? [] : [item(feed.index + 1)],
        readHistory: () => [],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(tester, controller);
      expect(find.text('暂时无法获取番剧，请检查网络后重试'), findsOneWidget);
      empty = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-featured')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-feed-season')));
      await tester.pumpAndSettle();
      expect(controller.items.single.id, 3);
      expect(controller.hasMore, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
