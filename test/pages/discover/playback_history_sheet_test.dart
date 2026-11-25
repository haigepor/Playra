import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/discover_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;

  HistoryRecord record({
    required String id,
    required String title,
    int duration = 120000,
    int position = 30000,
    String episode = '第 3 集',
  }) => HistoryRecord(
    sourceId: 'source',
    mediaId: id,
    title: title,
    cover: '',
    roadCode: 'road',
    roadName: '线路',
    episode: 3,
    episodeTitle: episode,
    positionMs: position,
    durationMs: duration,
    updatedAt: DateTime(2025, 1, int.parse(id)),
  );

  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-history-test-');
    Hive.init(data.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });
  setUp(() async => HistoryStorage.clearAll());

  Future<void> openSheet(
    WidgetTester tester, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlaybackHistory(context),
                child: const Text('打开历史'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
  }

  testWidgets('真实进度和时长，缺少时长不显示虚构进度', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '有时长'));
      await HistoryStorage.save(
        record(id: '2', title: '未知时长', duration: 0, position: 9000),
      );
      await openSheet(tester);
      expect(find.text('00:30 / 02:00'), findsOneWidget);
      expect(find.text('00:09'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, closeTo(.25, .001));
      expect(find.byTooltip('移除有时长'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('手机底部弹层和平板居中弹窗使用独立布局', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '测试作品'));
      await openSheet(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byTooltip('关闭播放历史'), findsOneWidget);
    });
  });

  testWidgets('平板历史弹窗居中且宽度受限', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '测试作品'));
      await openSheet(tester, size: const Size(1200, 800));
      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      final rect = tester.getRect(
        find.byKey(const ValueKey('playback-history-surface')),
      );
      expect(rect.width, lessThanOrEqualTo(800));
      expect(rect.center.dx, closeTo(600, 1));
      expect(rect.center.dy, closeTo(400, 1));
      expect(find.byTooltip('移除测试作品'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('负值不显示错误时间或伪进度', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '异常记录', position: -1));
      await openSheet(tester);
      expect(find.text('异常记录'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('逐项移除、取消及确认清空', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '第一部'));
      await HistoryStorage.save(record(id: '2', title: '第二部'));
      await openSheet(tester);
      await tester.tap(find.byTooltip('移除第一部'));
      await tester.pumpAndSettle();
      await GStorage.history.flush();
      expect(HistoryStorage.get('source', '1'), isNull);
      expect(find.text('第二部'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('清空播放历史？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(HistoryStorage.getAll(), hasLength(1));
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      final completer = Completer<void>();
      final history = HistoryStorage.listenable();
      void changed() {
        if (HistoryStorage.getAll().isEmpty && !completer.isCompleted) {
          completer.complete();
        }
      }

      history.addListener(changed);
      try {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('清空'),
          ),
        );
        await tester.pumpAndSettle();
        await completer.future.timeout(const Duration(seconds: 5));
      } finally {
        history.removeListener(changed);
      }
      await tester.pumpAndSettle();
      expect(find.text('还没有播放记录'), findsOneWidget);
      expect(HistoryStorage.getAll(), isEmpty);
    });
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 700), const Size(1024, 768)]) {
      testWidgets('历史弹层 $brightness $size 双倍字号', (tester) async {
        await tester.runAsync(() async {
          const title = '特别长的作品名称用于检测历史记录的标题必须在一行省略不能覆盖移除按钮';
          await HistoryStorage.save(
            record(
              id: '1',
              title: title,
              episode: '特别长的单集标题应该能够在狭窄屏幕上正确省略而不是溢出',
            ),
          );
          await openSheet(tester, brightness: brightness, size: size, scale: 2);
          final titleWidget = tester.widget<Text>(find.text(title));
          expect(titleWidget.maxLines, 1);
          expect(titleWidget.overflow, TextOverflow.ellipsis);
          expect(find.byTooltip('移除$title'), findsOneWidget);
          expect(find.text('25%'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  testWidgets('选择记录关闭弹层并按原媒体 ID 续播', (tester) async {
    await tester.runAsync(() async {
      await HistoryStorage.save(record(id: '1', title: '续播作品'));
      final module = createModule(
        register: (routes) {
          routes.route(
            '/',
            child: (context, state) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPlaybackHistory(context),
                  child: const Text('打开历史'),
                ),
              ),
            ),
          );
          routes.route(
            '/detail',
            child: (context, state) {
              final key = state.arguments as MediaKey;
              return Scaffold(body: Text('详情 ${key.sourceId} ${key.mediaId}'));
            },
          );
        },
      );
      await tester.pumpWidget(
        ModularApp(
          module: module,
          child: Builder(
            builder: (context) => MaterialApp.router(
              theme: buildShellTheme(Brightness.dark),
              routerConfig: ModularApp.routerConfigOf(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('续播作品'));
      await tester.pumpAndSettle();
      expect(find.text('详情 source 1'), findsOneWidget);
      expect(find.text('播放历史'), findsNothing);
    });
  });
}
