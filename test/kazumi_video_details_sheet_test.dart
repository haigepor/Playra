import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/kazumi_video_details_sheet.dart';
import 'package:media_kit/media_kit.dart';

Future<void> openSheet(
  WidgetTester tester,
  PlayerDebugController debug, {
  Size size = const Size(800, 600),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showKazumiVideoDetailsSheet(context, debug: debug),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (size, scale) in [
    (const Size(320, 480), 2.0),
    (const Size(760, 260), 2.0),
    (const Size(1280, 800), 1.0),
  ]) {
    testWidgets('fits $size with text scale $scale', (tester) async {
      await openSheet(
        tester,
        PlayerDebugController(),
        size: size,
        scale: scale,
      );
      expect(find.text('播放信息'), findsOneWidget);
      expect(find.text('等待画面'), findsOneWidget);
      await tester.tap(find.text('日志'));
      await tester.pumpAndSettle();
      expect(find.text('还没有运行日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'updates real summaries and hides native secrets when displayed and copied',
    (tester) async {
      const secret = 'https://example.test/video?token=secret';
      final debug = PlayerDebugController();
      debug.playerWidth = 1920;
      debug.playerHeight = 1080;
      debug.playerVideoBitrate = '1234.0';
      debug.playerPlaylist = '条目数：1，当前序号：1';
      debug.playerVideoParams = '尺寸：1920 × 1080，旋转：0°';
      debug.recordLog(
        const PlayerLog(prefix: secret, level: 'error', text: secret),
      );
      debug.playerLog.add(
        secret,
      ); // An unexpected raw entry is also fail-closed.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openSheet(tester, debug);
      expect(find.text('1920 × 1080'), findsOneWidget);
      expect(find.text('1234.0'), findsOneWidget);
      expect(find.text('条目数：1，当前序号：1'), findsOneWidget);
      debug.playerWidth = 1280;
      await tester.pump();
      expect(find.text('1280 × 1080'), findsOneWidget);
      await tester.tap(find.text('日志'));
      await tester.pumpAndSettle();
      expect(find.textContaining(secret), findsNothing);
      expect(find.text('播放器日志（内容已隐藏）'), findsOneWidget);
      await tester.tap(find.text('复制全部'));
      await tester.pump();
      expect(copied, contains('错误'));
      expect(copied, isNot(contains(secret)));
    },
  );
}
