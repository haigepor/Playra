import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/pages/profile/profile_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;

  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-profile-test-');
    Hive.init(data.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.history.clear();
    await GStorage.favorites.clear();
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });

  Future<void> showProfile(
    WidgetTester tester,
    Size size,
    Brightness brightness, {
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(brightness),
        home: const ProfilePage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 700), const Size(1024, 768)]) {
      testWidgets('设置卡片 $brightness $size 大字体不溢出', (tester) async {
        await showProfile(tester, size, brightness, scale: 2);
        expect(find.text('跟随系统'), findsOneWidget);
        expect(find.text('浅色'), findsOneWidget);
        expect(find.text('深色'), findsOneWidget);
        for (final label in ['播放设置', '网络与存储', '关于 Playra']) {
          await tester.scrollUntilVisible(find.text(label), 200);
          expect(find.text(label), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('主题选择持久化，播放开关仍可操作', (tester) async {
    await tester.runAsync(() async {
      await showProfile(tester, const Size(390, 844), Brightness.dark);
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      await GStorage.settings.flush();
      expect(GStorage.getSetting(SettingsKeys.themeMode), 'light');
      await tester.scrollUntilVisible(find.text('断点续播'), 160);
      final initial = GStorage.getSetting(SettingsKeys.playResume);
      await tester.tap(find.text('断点续播'));
      await tester.pumpAndSettle();
      await GStorage.settings.flush();
      expect(GStorage.getSetting(SettingsKeys.playResume), !initial);
    });
  });

  testWidgets('错误代理地址保留原值并显示校验提示', (tester) async {
    await tester.runAsync(() async {
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      await GStorage.putSetting(SettingsKeys.proxyUrl, '127.0.0.1:7890');
    });
    await showProfile(tester, const Size(390, 844), Brightness.dark);
    await tester.scrollUntilVisible(find.text('网络与存储'), 180);
    await tester.tap(find.text('网络与存储'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('代理地址'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'not-a-proxy');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('应用'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('请输入主机:端口，端口范围 1–65535'), findsOneWidget);
    expect(GStorage.getSetting(SettingsKeys.proxyUrl), '127.0.0.1:7890');
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空播放历史必须确认，取消时保留数据', (tester) async {
    await tester.runAsync(
      () => HistoryStorage.save(
        HistoryRecord(
          sourceId: 's',
          mediaId: '1',
          title: '测试作品',
          cover: '',
          roadCode: 'main',
          roadName: '线路',
          episode: 1,
          episodeTitle: '第一集',
          positionMs: 1000,
          durationMs: 10000,
          updatedAt: DateTime(2025),
        ),
      ),
    );
    await showProfile(tester, const Size(390, 844), Brightness.dark);
    await tester.scrollUntilVisible(find.text('网络与存储'), 180);
    await tester.tap(find.text('网络与存储'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('清空'), 180);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空播放历史？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(HistoryStorage.getAll(), hasLength(1));
  });
}
