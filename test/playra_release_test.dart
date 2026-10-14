import 'dart:async';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:kazumi/pages/about/about_page.dart';
import 'package:kazumi/pages/about/about_module.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/onboarding/steps/update_source_step.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/profile/modern_profile_view.dart';
import 'package:kazumi/presentation/modern/profile/profile_sync_state.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _My extends Fake implements MyController {
  @override
  Future<bool> checkUpdate({String type = 'manual'}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_release_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    if (!directory.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        ) ||
        !directory.path.contains('playra_release_test_')) {
      throw StateError('Unexpected test directory');
    }
    await directory.delete(recursive: true);
  });
  test('only stable Playra versions participate in updates', () {
    expect(AppBrand.releaseVersion('playra/v2.3.9'), '2.3.9');
    for (final tag in [
      '2.3.9',
      'upstream/2.3.9',
      'v2.3.9',
      'playra/v2.3.9-beta',
      'playra/vbad',
    ]) {
      expect(AppBrand.releaseVersion(tag), isNull);
    }
    expect(ApiEndpoints.latestApp, contains('/haigepor/Playra/'));
    expect(ApiEndpoints.latestAppMirror, ApiEndpoints.latestApp);
  });

  testWidgets('production profile hides laboratory while diagnostic keeps it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final enabled in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModernProfileView(
              stats: const WatchStats(),
              sync: const ProfileSyncState(bangumi: '未连接', webDav: '未配置'),
              version: '2.3.8',
              onOpen: (_) {},
              onDiscover: () {},
              showDeveloperTools: enabled,
            ),
          ),
        ),
      );
      expect(find.text('组件实验室'), enabled ? findsOneWidget : findsNothing);
      expect(find.text('Playra · 2.3.8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'About remains readable at 320px and enlarged text; update is single flight',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0;
      final pending = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1100),
              textScaler: TextScaler.linear(1.6),
            ),
            child: AboutPage(
              onCheckUpdate: () {
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Playra'), findsOneWidget);
      expect(find.text('源代码'), findsNothing);
      expect(find.text('Telegram'), findsNothing);
      expect(find.text('版本记录'), findsNothing);
      expect(find.text('许可与致谢'), findsNothing);
      expect(find.text('应用信息'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
      await tester.ensureVisible(find.text('检查更新'));
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      expect(find.text('正在检查…'), findsWidgets);
      await tester.tap(find.text('正在检查…').last);
      expect(calls, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('检查更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('旧许可和致谢深链展示 Playra，本地帮助可返回', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final path in ['legal', 'credits']) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ModularApp(
          module: createModule(
            register: (root) {
              root.addSingleton<MyController>(() => _My());
              root.module(
                createModule(
                  path: '/settings',
                  register: (settings) => settings.module(aboutModule),
                ),
              );
            },
          ),
          initialRoute: '/settings/about/$path',
          child: Builder(
            builder: (context) => MaterialApp.router(
              theme: ThemeData(platform: TargetPlatform.iOS),
              routerConfig: ModularApp.routerConfigOf(context),
              builder: (_, child) => ModernSettingsScope(child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Playra'), findsOneWidget);
      expect(find.text('许可与致谢'), findsNothing);
      expect(find.textContaining('github.com'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
      await tester.ensureVisible(find.text('使用帮助'));
      await tester.tap(find.text('使用帮助'));
      await tester.pumpAndSettle();
      expect(find.text('发现与播放'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('Playra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('更新引导使用产品文案，不展示仓库平台', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateSourceStep(
            useGithubUpdate: true,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsNothing);
    expect(find.text('自动检查'), findsOneWidget);
    await tester.tap(find.text('手动更新'));
    expect(selected, false);
    expect(tester.takeException(), isNull);
  });
}
