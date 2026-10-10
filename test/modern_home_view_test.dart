import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'modern_home_controller_test.dart' show item;

Future<void> mountHome(
  WidgetTester tester,
  ModernHomeController controller, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  VoidCallback? onSearch,
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
    'search, history, theme, details and resume preserve callbacks and identity',
    (tester) async {
      var searches = 0, histories = 0, themes = 0;
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
        onHistory: () => histories++,
        onTheme: () => themes++,
        onDetails: (id) => details = id,
        onResume: (entry) => resumed = entry,
      );
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-history')));
      await tester.tap(find.byKey(const ValueKey('home-theme')));
      await tester.tap(find.byKey(const ValueKey('home-featured-details')));
      await tester.ensureVisible(
        find.byKey(ValueKey('home-resume-${history.key}')),
      );
      await tester.tap(find.byKey(ValueKey('home-resume-${history.key}')));
      expect(searches, 1);
      expect(histories, 1);
      expect(themes, 1);
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
