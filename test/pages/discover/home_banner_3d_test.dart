import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_banner.dart';
import 'package:kazumi/pages/discover/home_layout.dart';

const _banners = [
  MediaBanner(id: 'one', title: 'First banner', imageUrl: ''),
  MediaBanner(id: 'two', title: 'Second banner', imageUrl: ''),
  MediaBanner(id: 'three', title: 'Third banner', imageUrl: ''),
];

Widget _harness({
  required HomeLayoutMetrics layout,
  required ValueChanged<MediaBanner> onTap,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  List<MediaBanner> banners = _banners,
  bool Function(MediaBanner)? canOpen,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: layout.isPhone ? const Size(400, 800) : const Size(900, 1200),
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: layout.isPhone ? 400 : 900,
            child: HomeBannerCarousel(
              layout: layout,
              banners: banners,
              onTap: onTap,
              canOpen: canOpen,
            ),
          ),
        ),
      ),
    ),
  );
}

double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

void main() {
  testWidgets('non-actionable banner does not trigger a fake action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _harness(
        layout: HomeLayoutMetrics.phone,
        banners: const [MediaBanner(id: 'none', title: '无链接', imageUrl: '')],
        canOpen: (_) => false,
        onTap: (_) => taps++,
      ),
    );
    await tester.tap(find.byType(PageView));
    expect(taps, 0);
  });

  testWidgets('phone carousel follows a swipe and taps the displayed card', (
    tester,
  ) async {
    MediaBanner? tapped;
    await tester.pumpWidget(
      _harness(layout: HomeLayoutMetrics.phone, onTap: (item) => tapped = item),
    );
    expect(find.text('First banner'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    expect(tapped, same(_banners.first));

    final initialPage = _page(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();
    expect(_page(tester), greaterThan(initialPage));
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(HomeBannerCarousel),
        matching: find.byType(Transform),
      ),
    );
    expect(transforms, isNotEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Second banner'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    expect(tapped, same(_banners[1]));
  });

  testWidgets('phone carousel keeps both adjacent depth-stack cards visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(layout: HomeLayoutMetrics.phone, onTap: (_) {}),
    );
    final viewport = tester.getRect(find.byType(PageView));
    final left = tester.getRect(find.byKey(const ValueKey('banner-depth-card-0')));
    final center = tester.getRect(find.byKey(const ValueKey('banner-depth-card-1')));
    final right = tester.getRect(find.byKey(const ValueKey('banner-depth-card-2')));
    expect(left.left, lessThan(center.left));
    expect(right.right, greaterThan(center.right));
    expect(left.overlaps(viewport), isTrue);
    expect(right.overlaps(viewport), isTrue);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('First banner'), findsOneWidget);
  });

  testWidgets('carousel caps displayed banners to 5 items by default', (
    tester,
  ) async {
    final many = List.generate(
      9,
      (i) => MediaBanner(id: 'b$i', title: 'Banner $i', imageUrl: ''),
    );
    await tester.pumpWidget(
      _harness(layout: HomeLayoutMetrics.phone, banners: many, onTap: (_) {}),
    );
    expect(find.text('01'), findsOneWidget);
    // Swipe left once to wrap backwards from 01 -> 05 (not 09).
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('05'), findsOneWidget);
    expect(find.text('Banner 4'), findsOneWidget);
  });

  testWidgets('hot reload rebuilds the page controller safely', (tester) async {
    await tester.pumpWidget(
      _harness(layout: HomeLayoutMetrics.phone, onTap: (_) {}),
    );
    final reassemble = tester.binding.reassembleApplication();
    await tester.pump();
    await reassemble;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('First banner'), findsOneWidget);
  });

  testWidgets('phone carousel automatically advances with animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(layout: HomeLayoutMetrics.phone, onTap: (_) {}),
    );
    final initialPage = _page(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_page(tester), greaterThan(initialPage));
    expect(_page(tester), lessThan(initialPage + 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Second banner'), findsOneWidget);
  });

  for (final accessible in [false, true]) {
    testWidgets(
      'reduced motion disables automatic advance (${accessible ? 'accessible navigation' : 'disable animations'})',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            layout: HomeLayoutMetrics.phone,
            onTap: (_) {},
            disableAnimations: !accessible,
            accessibleNavigation: accessible,
          ),
        );
        await tester.pump(const Duration(seconds: 13));
        expect(find.text('First banner'), findsOneWidget);
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Second banner'), findsOneWidget);
      },
    );
  }

  for (final layout in [
    HomeLayoutMetrics.tabletPortrait,
    HomeLayoutMetrics.tabletLandscape,
  ]) {
    testWidgets(
      'tablet ${layout.kind.name} retains carousel layout and interaction',
      (tester) async {
        MediaBanner? tapped;
        tester.view.physicalSize = const Size(1200, 1400);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _harness(layout: layout, onTap: (item) => tapped = item),
        );
        final pageView = tester.widget<PageView>(find.byType(PageView));
        expect(pageView.controller!.viewportFraction, layout.heroFraction);
        expect(find.text('First banner'), findsOneWidget);
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Second banner'), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[1]));
      },
    );
  }

  for (final layout in [
    HomeLayoutMetrics.phone,
    HomeLayoutMetrics.tabletPortrait,
    HomeLayoutMetrics.tabletLandscape,
  ]) {
    testWidgets('${layout.kind.name} wraps manually in both directions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      MediaBanner? tapped;
      await tester.pumpWidget(
        _harness(layout: layout, onTap: (item) => tapped = item),
      );
      Future<void> swipe(double dx, MediaBanner expected) async {
        await tester.drag(find.byType(PageView), Offset(dx, 0));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(expected));
      }

      await swipe(350, _banners[2]);
      await swipe(-350, _banners[0]);
      await swipe(-350, _banners[1]);
      await swipe(-350, _banners[2]);
      await swipe(-350, _banners[0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${layout.kind.name} automatically wraps forward without reversing',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        addTearDown(tester.view.resetPhysicalSize);
        MediaBanner? tapped;
        await tester.pumpWidget(
          _harness(layout: layout, onTap: (item) => tapped = item),
        );
        for (final banner in [_banners[1], _banners[2]]) {
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tapAt(tester.getCenter(find.byType(PageView)));
          expect(tapped, same(banner));
        }
        final beforeWrap = _page(tester);
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          _page(tester),
          greaterThan(beforeWrap),
          reason: 'Wrap must animate forward to the adjacent card',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[0]));
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[1]));
      },
    );

    testWidgets(
      '${layout.kind.name} handles a single banner and changed data',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        addTearDown(tester.view.resetPhysicalSize);
        MediaBanner? tapped;
        Widget build(List<MediaBanner> banners) => _harness(
          layout: layout,
          banners: banners,
          onTap: (item) => tapped = item,
        );
        await tester.pumpWidget(build([_banners[0]]));
        await tester.pump(const Duration(seconds: 13));
        await tester.drag(find.byType(PageView), const Offset(-350, 0));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[0]));
        await tester.pumpWidget(build([_banners[2], _banners[1]]));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[2]));
        await tester.drag(find.byType(PageView), const Offset(-350, 0));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[1]));
        await tester.pumpWidget(build([_banners[0]]));
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[0]));
        await tester.pump(const Duration(seconds: 13));
        await tester.tapAt(tester.getCenter(find.byType(PageView)));
        expect(tapped, same(_banners[0]));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
