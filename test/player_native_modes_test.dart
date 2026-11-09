import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/services/platform/video_fullscreen_mode.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';

class UnusedDownload implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LocalDanmaku extends PlayerDanmakuController {
  LocalDanmaku()
    : super(isLocalPlayback: () => true, downloadController: UnusedDownload());
  @override
  double get timelineOffsetSeconds => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rapid fullscreen rotation and back apply in request order', (
    tester,
  ) async {
    final applied = <VideoFullscreenMode>[];
    final first = Completer<void>();
    final controller = VideoFullscreenController(
      applyFullscreen: (mode) async {
        applied.add(mode);
        if (applied.length == 1) await first.future;
      },
    );
    late BuildContext routeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            routeContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    controller.attach(ModalRoute.of(routeContext)!);
    final enter = controller.setMode(VideoFullscreenMode.landscape);
    final rotate = controller.setMode(VideoFullscreenMode.portrait);
    final exit = Navigator.of(routeContext).maybePop();
    await tester.pump();
    expect(applied, [VideoFullscreenMode.landscape]);
    first.complete();
    await enter;
    await rotate;
    await exit;
    await controller.close();
    expect(applied, [
      VideoFullscreenMode.landscape,
      VideoFullscreenMode.portrait,
      VideoFullscreenMode.none,
      VideoFullscreenMode.none,
    ]);
    expect(controller.mode, VideoFullscreenMode.none);
  });
  testWidgets('failed orientation request does not block restoring the route', (
    tester,
  ) async {
    final applied = <VideoFullscreenMode>[];
    final controller = VideoFullscreenController(
      applyFullscreen: (mode) async {
        applied.add(mode);
        if (mode == VideoFullscreenMode.landscape) {
          throw StateError('platform rejected');
        }
      },
    );
    late BuildContext routeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            routeContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    controller.attach(ModalRoute.of(routeContext)!);
    await expectLater(
      controller.setMode(VideoFullscreenMode.landscape),
      throwsStateError,
    );
    await controller.setMode(VideoFullscreenMode.portrait);
    await controller.close();
    expect(applied, [
      VideoFullscreenMode.landscape,
      VideoFullscreenMode.portrait,
      VideoFullscreenMode.none,
    ]);
  });
  test('outgoing view cannot dispose the incoming PiP handler', () {
    final previous = Object(), current = Object();
    void register(Object owner) => PipUtils.initPipHandler(
      owner: owner,
      onAction: (_) async {},
      onModeChanged: (_) {},
    );
    register(previous);
    register(current);
    PipUtils.disposePipHandler(previous);
    expect(PipUtils.androidPIPInited, isTrue);
    PipUtils.disposePipHandler(current);
    expect(PipUtils.androidPIPInited, isFalse);
  });
  test(
    'danmaku emits once per source second and toggle invalidates delayed items',
    () {
      final controller = LocalDanmaku();
      controller.danDanmakus[3] = [
        DanmakuEntry(
          message: 'test',
          time: 3,
          type: 1,
          color: Colors.white,
          source: 'local',
        ),
      ];
      controller.setDanmakuEnabled(true);
      final generation = controller.scheduledDanmakuGeneration;
      expect(
        controller.takeDanmakusForPlaybackPosition(
          const Duration(milliseconds: 3100),
        ),
        hasLength(1),
      );
      expect(
        controller.takeDanmakusForPlaybackPosition(
          const Duration(milliseconds: 3600),
        ),
        isEmpty,
      );
      controller.setDanmakuEnabled(false);
      controller.setDanmakuEnabled(true);
      expect(controller.scheduledDanmakuGeneration, greaterThan(generation));
      expect(
        controller.takeDanmakusForPlaybackPosition(
          const Duration(milliseconds: 3600),
        ),
        hasLength(1),
      );
    },
  );
  test(
    'desktop PiP restores original bounds and on-top state after aspect changes',
    () async {
      const channel = MethodChannel('window_manager');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'getBounds' => {
                'x': 40.0,
                'y': 60.0,
                'width': 1050.0,
                'height': 720.0,
              },
              'isAlwaysOnTop' => true,
              'isMaximized' => false,
              'isFullScreen' => false,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await PipUtils.enterDesktopPIPWindow();
      await PipUtils.enterDesktopPIPWindow(width: 9, height: 16);
      await PipUtils.exitDesktopPIPWindow();
      expect(
        calls.lastWhere((c) => c.method == 'setBounds').arguments,
        containsPair('x', 40.0),
      );
      expect(
        calls.lastWhere((c) => c.method == 'setAlwaysOnTop').arguments,
        containsPair('isAlwaysOnTop', true),
      );
      final sizes = calls
          .where((c) => c.method == 'setBounds')
          .map((c) => c.arguments as Map)
          .where((m) => m.containsKey('width'));
      expect(sizes.last, containsPair('width', 1050.0));
      expect(sizes.last, containsPair('height', 720.0));
    },
  );
}
