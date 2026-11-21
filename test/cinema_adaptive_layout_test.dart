import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_banner.dart';
import 'package:kazumi/pages/discover/home_layout.dart';

void main() {
  for (final width in [320.0, 360.0, 600.0, 800.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('featured work opens at $width dp and scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 960);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const work = MediaBanner(
          id: 'work',
          title: '一部有完整长标题和真实详情入口的作品',
          imageUrl: '',
        );
        MediaBanner? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeBannerCarousel(
                layout: HomeLayoutMetrics.resolve(Size(width, 960)),
                banners: const [work],
                onTap: (banner) => opened = banner,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.bySemanticsLabel(work.title);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        await tester.tap(action);
        expect(opened, same(work));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
