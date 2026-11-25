import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
    data = await Directory.systemTemp.createTemp('playra-background-test-');
    Hive.init(data.path);
    await GStorage.init();
  });
  setUp(() async => GStorage.settings.clear());
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });

  Future<void> showProfile(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.dark),
        home: const ProfilePage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  CupertinoSwitch backgroundSwitch(WidgetTester tester) => tester.widget(
    find.descendant(
      of: find.ancestor(of: find.text('后台播放'), matching: find.byType(ListTile)),
      matching: find.byType(CupertinoSwitch),
    ),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform 默认关闭且仅显式切换时写入', (tester) async {
      await tester.runAsync(() async {
        await showProfile(tester, platform);
        await tester.scrollUntilVisible(find.text('后台播放'), 160);
        await tester.pumpAndSettle();
        expect(backgroundSwitch(tester).value, isFalse);
        expect(
          GStorage.settings.containsKey(SettingsKeys.backgroundPlayback.name),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('后台播放'));
        await tester.pumpAndSettle();
        await GStorage.settings.flush();
        expect(GStorage.getSetting(SettingsKeys.backgroundPlayback), isTrue);
        expect(backgroundSwitch(tester).value, isTrue);
        expect(tester.takeException(), isNull);
      });
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('已有值保留，切换后重新进入仍保留', (tester) async {
    await tester.runAsync(() async {
      await GStorage.putSetting(SettingsKeys.backgroundPlayback, true);
      await showProfile(tester, TargetPlatform.android);
      await tester.scrollUntilVisible(find.text('后台播放'), 160);
      await tester.pumpAndSettle();
      expect(backgroundSwitch(tester).value, isTrue);
      expect(GStorage.getSetting(SettingsKeys.backgroundPlayback), isTrue);
      await tester.tap(find.text('后台播放'));
      await tester.pumpAndSettle();
      await GStorage.settings.flush();
      expect(GStorage.getSetting(SettingsKeys.backgroundPlayback), isFalse);
      await tester.pumpWidget(const SizedBox());
      await showProfile(tester, TargetPlatform.android);
      await tester.scrollUntilVisible(find.text('后台播放'), 160);
      await tester.pumpAndSettle();
      expect(backgroundSwitch(tester).value, isFalse);
    });
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('桌面不显示入口且不改已有值', (tester) async {
    await tester.runAsync(
      () => GStorage.putSetting(SettingsKeys.backgroundPlayback, true),
    );
    await showProfile(tester, TargetPlatform.windows);
    await tester.scrollUntilVisible(find.text('音量与亮度手势'), 160);
    expect(find.text('后台播放'), findsNothing);
    expect(GStorage.getSetting(SettingsKeys.backgroundPlayback), isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
