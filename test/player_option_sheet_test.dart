import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_option_sheet.dart';

void main() {
  testWidgets('episode options fit and remain selectable with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    int? chosen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showRoadEpisodes(
                  context,
                  roadName: '主线路',
                  episodes: const [
                    PlayerOption(123, '123', detail: '特别篇 上'),
                    PlayerOption(
                      124,
                      '124',
                      detail: '需要会员 · 特别篇 下',
                      enabled: false,
                    ),
                  ],
                  onBack: () {},
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('特别篇 上'), findsOneWidget);
    expect(find.text('需要会员 · 特别篇 下'), findsOneWidget);
    await tester.tap(find.text('124'));
    await tester.pump();
    expect(chosen, isNull);
    await tester.tap(find.text('123'));
    await tester.pumpAndSettle();
    expect(chosen, 123);
  });

  testWidgets('disabled shortcut cannot close or select the sheet', (
    tester,
  ) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPlayerOptions<int>(
                  context,
                  title: '更多选项',
                  shortcuts: const [
                    PlayerOption(1, '截图', icon: Icons.camera, enabled: false),
                    PlayerOption(2, '锁定面板', icon: Icons.lock),
                  ],
                  options: const [],
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();
    expect(find.text('更多选项'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('锁定面板'));
    await tester.pumpAndSettle();
    expect(result, 2);
  });

  for (final size in [const Size(320, 700), const Size(700, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('player options work at $size and text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        int? chosen;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      chosen = await showPlayerOptions<int>(
                        context,
                        title: '定时关闭',
                        selected: 0,
                        options: const [
                          PlayerOption(0, '不开启'),
                          PlayerOption(15, '15 分钟'),
                          PlayerOption(30, '30 分钟'),
                          PlayerOption(60, '60 分钟'),
                          PlayerOption(-1, '自定义'),
                        ],
                      );
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.text('定时关闭'), findsOneWidget);
        await tester.ensureVisible(find.text('30 分钟'));
        await tester.tap(find.text('30 分钟'));
        await tester.pumpAndSettle();
        expect(chosen, 30);
        expect(tester.takeException(), isNull);
      });

      testWidgets('speed controls work at $size and text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        double? chosen;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      chosen = await showPlayerSpeed(context, const [
                        0.5,
                        1.0,
                        1.25,
                        1.5,
                        2.0,
                      ], 1.0);
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.text('倍速'), findsOneWidget);
        await tester.ensureVisible(find.text('1.25×'));
        await tester.tap(find.text('1.25×'));
        await tester.pumpAndSettle();
        expect(chosen, 1.25);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
