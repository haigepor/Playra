import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/pages/player/kazumi_original_transport.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item_panel.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';
import 'package:kazumi/pages/player/player_progress_bar.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;

  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-player-integration-');
    Hive.init(data.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });

  for (final config
      in <
        ({
          String name,
          Size size,
          double scale,
          bool compact,
          TargetPlatform platform,
        })
      >[
        (
          name: 'wide landscape',
          size: const Size(844, 390),
          scale: 1,
          compact: false,
          platform: TargetPlatform.android,
        ),
        (
          name: 'compact 320dp',
          size: const Size(320, 640),
          scale: 1,
          compact: true,
          platform: TargetPlatform.android,
        ),
        (
          name: 'compact large text',
          size: const Size(320, 640),
          scale: 2,
          compact: true,
          platform: TargetPlatform.android,
        ),
        (
          name: 'iOS compact large text',
          size: const Size(320, 640),
          scale: 2,
          compact: true,
          platform: TargetPlatform.iOS,
        ),
      ]) {
    testWidgets('real panel: ${config.name}', (tester) async {
      debugDefaultTargetPlatformOverride = config.platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = config.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final animation = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 1),
        value: 1,
      );
      final focus = FocusNode();
      final player = PlayerController(ShaderAssetService(), AudioController());
      player.panel.showVideoController = true;
      final session = PlaybackSession(
        title: '星海旅途',
        roads: [
          PlaybackRoad(
            name: '主线路',
            episodes: const [PlaybackEpisode(title: '第 1 集', url: '')],
          ),
        ],
      );
      var reviews = 0;
      var skips = 0;
      var pipRequests = 0;
      void noop() {}
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: config.size,
              textScaler: TextScaler.linear(config.scale),
            ),
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  PlayerItemPanel(
                    playerController: player,
                    videoPageController: session,
                    fillsWindow: true,
                    onBackPressed: noop,
                    setPlaybackSpeed: (_) async {},
                    handleFullscreen: noop,
                    handlePortraitFullscreen: noop,
                    enterAndroidPictureInPicture: () async => pipRequests++,
                    handleScreenShot: noop,
                    showScreenshotCandidates: () => reviews++,
                    onNextEpisode: noop,
                    onToggleLock: () =>
                        player.panel.lockPanel = !player.panel.lockPanel,
                    handleProgressBarDragStart: noop,
                    handleProgressBarDragUpdate: (_) {},
                    handleProgressBarDragEnd: (_) {},
                    handleProgressBarSeek: (_) async {},
                    handleSuperResolutionChange: (_) async {},
                    panelVisibilityController: animation,
                    keyboardFocus: focus,
                    acquirePlayerPanelHold: () =>
                        PlayerPanelHold(onRelease: noop),
                    onMenuVisibilityChanged: (_) {},
                    skipOP: () => skips++,
                    pauseForTimedShutdown: noop,
                    disableAnimations: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final transport = tester.widget<KazumiOriginalTransport>(
        find.byType(KazumiOriginalTransport),
      );
      expect(transport.compact, config.compact);
      expect(find.byType(PlayerProgressBar), findsOneWidget);
      final forward = find.byTooltip('快进80秒，长按修改时间');
      expect(forward, findsOneWidget);
      await tester.tap(forward);
      expect(skips, 1);
      if (!config.compact) {
        await tester.longPress(forward);
        await tester.pumpAndSettle();
        expect(find.text('跳过秒数'), findsOneWidget);
        await tester.enterText(
          find.byType(EditableText),
          '99999999999999999999999',
        );
        await tester.tap(find.text('确定'));
        await tester.pump();
        expect(find.text('跳过秒数'), findsOneWidget);
        expect(player.playback.buttonSkipTime, 80);
        await tester.enterText(find.byType(EditableText), '17');
        await tester.runAsync(() async {
          await tester.tap(find.text('确定'));
          expect(player.playback.buttonSkipTime, 17);
          await GStorage.settings.flush();
          player.setButtonForwardTime(80);
          await GStorage.settings.flush();
        });
        await tester.pumpAndSettle();
        expect(player.playback.buttonSkipTime, 80);
      }
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('播放'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );
      await player.screenshots.capture(
        capturePng: () async => Uint8List.fromList([1, 2, 3]),
        title: '作品',
        episode: '第 1 集',
        position: Duration.zero,
        isCurrent: () => true,
      );
      await tester.pump();
      expect(find.byTooltip('挑选截图 · 1 张'), findsOneWidget);
      if (config.platform == TargetPlatform.android) {
        expect(find.byTooltip('画中画'), findsOneWidget);
        await tester.tap(find.byTooltip('画中画'));
        expect(pipRequests, 1);
      } else {
        expect(find.byTooltip('画中画'), findsNothing);
        expect(pipRequests, 0);
      }
      await tester.tap(find.byTooltip('挑选截图 · 1 张'));
      expect(reviews, 1);
      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      if (!config.compact) {
        expect(find.byTooltip('锁定面板'), findsOneWidget);
        await tester.tap(find.byTooltip('锁定面板'));
        await tester.pump();
        expect(find.byTooltip('解锁面板'), findsOneWidget);
        await tester.tap(find.byTooltip('解锁面板'));
        await tester.pump();
        expect(player.panel.lockPanel, isFalse);
      }
      expect(find.byTooltip('更多选项'), findsOneWidget);
      await tester.tap(find.byTooltip('更多选项'));
      await tester.pumpAndSettle();
      expect(find.text('定时关闭'), findsWidgets);
      await tester.ensureVisible(find.text('视频详情').last);
      await tester.tap(find.text('视频详情').last);
      await tester.pumpAndSettle();
      expect(find.text('播放信息'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭播放信息'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      session.dispose();
      animation.dispose();
      focus.dispose();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    });
  }
}
