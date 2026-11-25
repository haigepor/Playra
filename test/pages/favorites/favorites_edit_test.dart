import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/pages/favorites/favorites_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;

  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-favorites-test-');
    Hive.init(data.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });
  setUp(() async {
    await FavoriteStorage.clearAll();
    for (var i = 1; i <= 2; i++) {
      await FavoriteStorage.toggle(
        FavoriteRecord(
          sourceId: 'source',
          mediaId: '$i',
          title: '作品$i',
          cover: '',
          updatedAt: DateTime(2025, 1, i),
        ),
      );
    }
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: tester.view.physicalSize / tester.view.devicePixelRatio,
            textScaler: TextScaler.linear(scale),
          ),
          child: FavoritesPage(onDiscover: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('追番状态提示来自收藏时记录', (tester) async {
    await tester.runAsync(() async {
      await FavoriteStorage.toggle(
        FavoriteRecord(
          sourceId: 'source',
          mediaId: '3',
          title: '作品3',
          cover: '',
          subtitle: '更新至 12 集',
          updatedAt: DateTime(2025, 1, 3),
        ),
      );
      await pumpPage(tester);
      expect(find.text('更新状态为收藏时记录，可能不是最新'), findsOneWidget);
      expect(find.text('更新至 12 集'), findsOneWidget);
      await GStorage.favorites.flush();
    });
  });

  testWidgets('编辑模式逐个移除，最后回到空态', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);
      expect(find.text('2 部作品'), findsOneWidget);
      expect(find.byTooltip('移除作品1'), findsNothing);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsOneWidget);
      await tester.tap(find.byTooltip('移除作品1'));
      await tester.pumpAndSettle();
      expect(FavoriteStorage.isFavorite('source', '1'), isFalse);
      expect(find.text('1 部作品'), findsOneWidget);
      await tester.tap(find.byTooltip('移除作品2'));
      await tester.pumpAndSettle();
      expect(find.text('还没有追番'), findsOneWidget);
      expect(find.text('去发现'), findsNothing);
      expect(find.text('完成'), findsNothing);
      await GStorage.favorites.flush();
    });
  });

  testWidgets('完成退出编辑，清空必须确认', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('移除作品1'), findsNothing);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('清空全部追番？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(FavoriteStorage.getAll(), hasLength(2));
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      final cleared = Completer<void>();
      final favorites = FavoriteStorage.listenable();
      void onFavoritesChanged() {
        if (FavoriteStorage.getAll().isEmpty && !cleared.isCompleted) {
          cleared.complete();
        }
      }

      favorites.addListener(onFavoritesChanged);
      try {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('清空'),
          ),
        );
        await tester.pumpAndSettle();
        await cleared.future.timeout(const Duration(seconds: 5));
      } finally {
        favorites.removeListener(onFavoritesChanged);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(FavoriteStorage.getAll(), isEmpty);
      expect(find.text('还没有追番'), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 700), const Size(1024, 768)]) {
      testWidgets('编辑页 $brightness $size 大字体', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpPage(tester, brightness: brightness, scale: 2);
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('移除作品2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
