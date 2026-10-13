import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/widgets/modern_feature_carousel.dart';

void main() {
  test('modern theme does not inherit green modal surfaces', () {
    final base = ThemeData(colorSchemeSeed: Colors.green);
    final modern = modernHomeTheme(base, forceDark: true);
    expect(
      modern.colorScheme.surfaceContainerHigh,
      modern.colorScheme.surfaceContainerLow,
    );
    expect(
      modern.dialogTheme.backgroundColor,
      modern.colorScheme.surfaceContainerLow,
    );
    expect(modern.inputDecorationTheme.filled, isTrue);
  });

  Widget carousel({
    bool reduce = false,
    bool ticker = true,
    double scale = 1,
    VoidCallback? onOpen,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 844),
        disableAnimations: reduce,
        textScaler: TextScaler.linear(scale),
      ),
      child: ModernHomeScope(
        child: Scaffold(
          body: TickerMode(
            enabled: ticker,
            child: ModernFeatureCarousel(
              entries: [
                for (var i = 0; i < 6; i++)
                  ModernFeatureEntry(
                    id: '$i',
                    title: '一部很长名称的推荐作品第 $i 季',
                    subtitle: '科幻 · 悬疑 · 电影',
                    cover: '',
                    onTap: onOpen ?? () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'carousel advances and pauses with reduced motion and hidden tabs',
    (tester) async {
      await tester.pumpWidget(carousel());
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      await tester.pumpWidget(carousel(ticker: false));
      await tester.pump(const Duration(seconds: 12));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      await tester.pumpWidget(carousel(reduce: true));
      await tester.pump(const Duration(seconds: 12));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'indicator hit areas switch slides and latest click wins without opening detail',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpWidget(carousel(onOpen: () => opened++));
      final pageView = tester.widget<PageView>(find.byType(PageView));
      final second = find.byKey(const ValueKey('feature-indicator-1'));
      // 点圆点下方的留白仍应切页，不能穿透到海报或详情按钮。
      await tester.tapAt(tester.getCenter(second) + const Offset(0, 12));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pageView.controller!.page, greaterThan(0));
      expect(pageView.controller!.page, lessThan(1));
      await tester.tap(find.byKey(const ValueKey('feature-indicator-4')));
      await tester.pumpAndSettle();
      expect(pageView.controller!.page, 4);
      expect(opened, 0);
      await tester.tap(find.byKey(const ValueKey('feature-indicator-4')));
      await tester.pumpAndSettle();
      expect(pageView.controller!.page, 4);
      await tester.pumpWidget(carousel(reduce: true));
      await tester.tap(find.byKey(const ValueKey('feature-indicator-0')));
      await tester.pump();
      expect(pageView.controller!.page, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'indicator follows partial drag before the selected page changes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(carousel());
      final marker = find.byKey(
        const ValueKey('feature-carousel-active-indicator'),
      );
      final initialCenter = tester.getCenter(marker).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-90, 0));
      await tester.pump();
      final partialCenter = tester.getCenter(marker).dx;
      expect(partialCenter, greaterThan(initialCenter));
      expect(partialCenter, lessThan(initialCenter + 22));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'carousel fits narrow screen and two times text; swipe remains usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(carousel(reduce: true, scale: 2));
      final layoutError = tester.takeException();
      if (layoutError is FlutterError) debugPrint(layoutError.toStringDeep());
      expect(layoutError, isNull);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
