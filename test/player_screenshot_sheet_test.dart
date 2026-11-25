import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/pages/player/player_screenshot_sheet.dart';
import 'package:kazumi/shell/shell_theme.dart';

final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==',
);

Future<void> _capture(PlayerScreenshotController controller, int index) async {
  await controller.capture(
    capturePng: () async => _pixel,
    title: '截图测试作品',
    episode: '第 $index 集',
    position: Duration(seconds: index),
    isCurrent: () => true,
  );
}

Future<void> _open(
  WidgetTester tester,
  PlayerScreenshotController controller, {
  required Size size,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildShellTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showPlayerScreenshotSheet(context, controller: controller),
            child: const Text('打开截图'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开截图'));
  await tester.pumpAndSettle();
}

void main() {
  for (final caseData in [
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(320, 480), 2.0),
    (const Size(760, 260), 2.0),
    (const Size(390, 844), 1.0),
    (const Size(760, 360), 1.5),
    (const Size(1280, 800), 1.5),
  ]) {
    testWidgets('screenshot dialog fits ${caseData.$1} scale ${caseData.$2}', (
      tester,
    ) async {
      final controller = PlayerScreenshotController();
      addTearDown(controller.dispose);
      await _capture(controller, 1);
      await _capture(controller, 2);
      await _open(tester, controller, size: caseData.$1, scale: caseData.$2);
      expect(find.text('截图'), findsOneWidget);
      expect(find.byTooltip('返回播放'), findsOneWidget);
      expect(find.byTooltip('放大查看'), findsOneWidget);
      expect(find.byTooltip('管理截图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('short landscape keeps screenshot actions reachable', (
    tester,
  ) async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    await _capture(controller, 1);
    await _open(tester, controller, size: const Size(760, 260), scale: 2);
    await tester.ensureVisible(find.text('保存所选'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('保存所选')).bottom, lessThanOrEqualTo(260));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone can select thumbnails, select all and remove', (
    tester,
  ) async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    await _capture(controller, 1);
    await _capture(controller, 2);
    await _open(tester, controller, size: const Size(390, 844));
    expect(controller.selectedCount, 0);
    await tester.tap(find.byTooltip('选择第 2 张'));
    await tester.pump();
    expect(controller.selectedCount, 1);
    expect(find.byTooltip('取消选择第 2 张'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(controller.selectedCount, 2);
    await tester.tap(find.text('移除所选'));
    await tester.pumpAndSettle();
    expect(controller.candidates, isEmpty);
    expect(find.text('暂无待处理截图'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop keeps preview navigation, selection and zoom', (
    tester,
  ) async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    await _capture(controller, 1);
    await _capture(controller, 2);
    await _open(tester, controller, size: const Size(1280, 800));
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('选择这张'));
    await tester.pump();
    expect(controller.isSelected(controller.candidates.first), isTrue);
    await tester.tap(find.byTooltip('放大查看'));
    await tester.pump();
    expect(find.byTooltip('还原大小'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('saving locks close and retains cancelled candidates', (
    tester,
  ) async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    await _capture(controller, 1);
    await _open(tester, controller, size: const Size(390, 844));
    await tester.tap(find.byTooltip('选择第 1 张'));
    await tester.pump();
    final destination = Completer<String?>();
    final saving = controller.save(
      chooseDestination: () => destination.future,
      write: (_, _) async {},
    );
    await tester.pump();
    expect(controller.saving, isTrue);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    destination.complete(null);
    await saving;
    await tester.pump();
    expect(controller.candidates, hasLength(1));
    expect(controller.selectedCount, 1);
    expect(controller.message, contains('已取消保存'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
