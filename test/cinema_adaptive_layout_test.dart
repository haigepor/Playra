import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/player/sdk_playback_hero.dart';
import 'package:kazumi/presentation/modern/widgets/modern_feature_carousel.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

void main() {
  testWidgets('unavailable media shows status instead of a play action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: ModernHomeScope(
              child: SdkPlaybackHero(
                cover: '',
                backdrop: '',
                title: '作品',
                episodeLabel: '暂无可播放剧集',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无可播放剧集'), findsOneWidget);
    expect(find.byType(PlayraButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 600.0, 800.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('media actions stay visible and usable at $width / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 960);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var plays = 0;
        var details = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ModernHomeScope(
              child: Scaffold(
                body: ListView(
                  children: [
                    SizedBox(
                      height: (width * 9 / 16).clamp(180, 360),
                      child: SdkPlaybackHero(
                        key: const ValueKey('stage'),
                        cover: '',
                        backdrop: '',
                        title: '完整的作品名称',
                        episodeLabel: '播放 第01集',
                        onPlay: () => plays++,
                      ),
                    ),
                    ModernFeatureCarousel(
                      entries: [
                        ModernFeatureEntry(
                          id: 'work',
                          title: '一部有完整长标题和真实详情入口的作品',
                          subtitle: '2026 · 日本 · 动画',
                          cover: '',
                          onTap: () => details++,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final play = find.widgetWithText(PlayraButton, '播放 第01集');
        final rect = tester.getRect(play);
        final stage = tester.getRect(find.byKey(const ValueKey('stage')));
        expect(stage.contains(rect.topLeft), isTrue);
        expect(stage.contains(rect.bottomRight), isTrue);
        expect(rect.height, greaterThanOrEqualTo(48));
        await tester.tap(play);
        expect(plays, 1);
        await tester.ensureVisible(find.text('查看详情'));
        await tester.tap(find.text('查看详情'));
        await tester.pumpAndSettle();
        expect(details, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
