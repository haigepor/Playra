import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/pages/plugin_editor/rule_management_widgets.dart';
import 'package:kazumi/presentation/modern/settings/modern_back_button.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/pages/settings/settings_page.dart';
import 'package:kazumi/presentation/interface_style.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/services/storage/storage.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _FormPage extends StatefulWidget {
  const _FormPage();
  @override
  State<_FormPage> createState() => _FormState();
}

class _FormState extends State<_FormPage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('测试外观'),
    body: ListView(
      children: [
        const TextField(
          key: ValueKey('draft'),
          decoration: InputDecoration(labelText: '保留草稿'),
        ),
        TextButton(
          onPressed: () => setState(() => count++),
          child: Text('计数 $count'),
        ),
        TextButton(
          onPressed: () => context.pushNamed('/settings/theme/display'),
          child: const Text('进入下级'),
        ),
      ],
    ),
  );
}

Module fixture() => createModule(
  register: (root) {
    root.module(
      createModule(
        path: '/settings',
        register: (c) {
          c.route(
            '/',
            child: (context, state) => SettingsAppearanceHost(
              child: SettingsPage(location: state.uri.path),
            ),
            children: (sub) {
              sub.route('/', child: (_, _) => const SettingsIndexPage());
              sub.route('/theme', child: (_, _) => const _FormPage());
              sub.route(
                '/theme/display',
                child: (_, _) => const SettingsDetailScaffold(
                  title: Text('测试下级'),
                  body: Text('下级内容'),
                ),
              );
            },
          );
        },
      ),
    );
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_settings_test_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((p) => p.isNotEmpty).last,
      startsWith('playra_settings_test_'),
    );
    await directory.delete(recursive: true);
  });

  Future<void> size(
    WidgetTester tester,
    double width, {
    double height = 844,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('新版分组连续，旧版圆角分行和基础主题保留', (tester) async {
    Future<void> pump(bool enabled) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        home: ModernSettingsScope(
          enabled: enabled,
          child: const Scaffold(
            body: SettingsSection(
              title: Text('分组'),
              tiles: [
                SettingsTile(title: Text('第一项')),
                SettingsTile(title: Text('第二项')),
              ],
            ),
          ),
        ),
      ),
    );
    await pump(false);
    expect(find.byType(SplitListRow), findsNWidgets(2));
    expect(
      Theme.of(tester.element(find.text('第一项'))).brightness,
      Brightness.light,
    );
    await pump(true);
    expect(find.byType(SplitListRow), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('第一项')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xff11141c));
    expect(theme.colorScheme.primary, const Color(0xffa7b7ff));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 760.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('同步介绍、操作按钮和空状态适配 $width 字号 $scale', (tester) async {
        await size(tester, width);
        var count = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: ModernSettingsScope(
                child: Scaffold(
                  body: SyncPageBody(
                    children: [
                      const SyncPageIntro(
                        icon: Icons.cloud_outlined,
                        title: '多设备同步',
                        description: '在不同设备之间同步追番、历史与规则',
                      ),
                      const SyncFeedback(message: '尚未连接，请完成配置后进行同步'),
                      const RulePageIntro(
                        title: '规则仓库',
                        description: '管理来源与规则，选择适合自己的播放来源',
                        icon: Icons.extension_outlined,
                      ),
                      GeneralEmptyState(
                        icon: Icons.history,
                        title: '还没有观看记录',
                        actions: [
                          StateActionButton.tonal(
                            onPressed: () => count++,
                            text: '去发现番剧',
                            icon: Icons.explore_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('去发现番剧'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('去发现番剧'));
        expect(count, 1);
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      });
    }
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('控件宽度 $width 字号 $scale，无溢出且交互可用', (tester) async {
        await size(tester, width);
        bool toggled = false;
        double speed = 1;
        String mode = 'a';
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: ModernSettingsScope(
                child: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, update) => SettingsList(
                      sections: [
                        SettingsSection(
                          title: const Text('设置分组'),
                          tiles: [
                            SettingsTile.switchTile(
                              title: const Text('自动连播'),
                              description: const Text('当前视频播放完毕后自动播放下一集'),
                              leading: Icons.history_rounded,
                              initialValue: toggled,
                              onToggle: (v) =>
                                  update(() => toggled = v ?? !toggled),
                            ),
                            SettingsSliderTile(
                              title: const Text('默认倍速'),
                              value: speed,
                              valueLabel: '$speed 倍',
                              min: .5,
                              max: 2,
                              divisions: 3,
                              onChanged: (v) => update(() => speed = v),
                            ),
                            SettingsDropdownTile<String>(
                              title: const Text('较长的设置名称'),
                              value: mode,
                              options: const {'a': '非常长的当前选项说明', 'b': '第二个选项'},
                              onChanged: (v) => update(() => mode = v),
                            ),
                          ],
                        ),
                        SettingsSection(
                          title: const Text('表单'),
                          tiles: [
                            const Padding(
                              padding: EdgeInsets.all(14),
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: '服务器地址',
                                  hintText: 'https://example.com/dav/',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('自动连播'));
        await tester.pumpAndSettle();
        expect(toggled, isTrue);
        expect(
          tester.getSize(find.byType(Switch)).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(toggled, isFalse);
        await tester.ensureVisible(find.byType(Slider));
        expect(
          tester.getSize(find.byType(Slider)).height,
          greaterThanOrEqualTo(48),
        );
        await tester.drag(find.byType(Slider), const Offset(50, 0));
        await tester.pumpAndSettle();
        expect(speed, greaterThan(1));
        await tester.ensureVisible(find.text('较长的设置名称'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('较长的设置名称'));
        await tester.pumpAndSettle();
        expect(find.text('第二个选项'), findsOneWidget);
        await tester.tap(find.text('第二个选项'));
        await tester.pumpAndSettle();
        expect(mode, 'b');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final modern in [true, false]) {
    testWidgets('返回按钮保留回调和旧版，modern=$modern', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ModernSettingsScope(
            enabled: modern,
            child: Scaffold(
              appBar: SysAppBar(
                title: const Text('子页面'),
                leading: BackButton(onPressed: () => count++),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (modern) {
        expect(find.byType(ModernBackButton), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        expect(
          tester.getSize(find.byTooltip('返回')).height,
          greaterThanOrEqualTo(48),
        );
      } else {
        expect(find.byType(ModernBackButton), findsNothing);
        expect(find.byType(BackButton), findsOneWidget);
      }
      await tester.tap(modern ? find.byTooltip('返回') : find.byType(BackButton));
      expect(count, 1);
      expect(tester.takeException(), isNull);
    });
  }

  Future<InterfaceStyleController> mount(
    WidgetTester tester, {
    double width = 390,
    String route = '/settings/',
  }) async {
    await size(tester, width);
    final style = InterfaceStyleController(
      supportsModern: true,
      savedStyle: 'modern',
      writeStyle: (_) async {},
    );
    await tester.pumpWidget(
      ModularApp(
        module: fixture(),
        initialRoute: route,
        provide: (scoped) =>
            scoped.addChangeNotifier<InterfaceStyleController>(() => style),
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: ModularApp.routerConfigOf(context),
            theme: ThemeData(colorSchemeSeed: Colors.green),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return style;
  }

  testWidgets('全部设置保留十二个入口及分组，进入和返回保持暗色', (tester) async {
    await mount(tester);
    for (final label in [
      '播放',
      '资源',
      '应用',
      '其他',
      '播放设置',
      '弹幕设置',
      '操作设置',
      '规则管理',
      '下载设置',
      '外观设置',
      '界面设置',
      '同步设置',
      '网络设置',
      '更新设置',
      '存储与日志',
      '关于',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.ensureVisible(find.text('外观设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    expect(find.text('测试外观'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('测试外观'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byType(ModernBackButton));
    await tester.pumpAndSettle();
    expect(find.text('测试外观'), findsNothing);
    expect(find.text('外观设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽窄切换、下级返回和新旧样式切换保留页面草稿', (tester) async {
    final style = await mount(tester, route: '/settings/theme');
    await tester.enterText(find.byKey(const ValueKey('draft')), '未保存草稿');
    await tester.tap(find.text('计数 0'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 844);
    await tester.pumpAndSettle();
    expect(find.text('未保存草稿'), findsOneWidget);
    expect(find.text('计数 1'), findsOneWidget);
    await tester.tap(find.text('进入下级'));
    await tester.pumpAndSettle();
    expect(find.text('测试下级'), findsOneWidget);
    final paneBack = find.descendant(
      of: find.byType(SettingsDetailScaffold),
      matching: find.byType(ModernBackButton),
    );
    expect(paneBack, findsOneWidget);
    await tester.tap(paneBack);
    await tester.pumpAndSettle();
    expect(find.text('计数 1'), findsOneWidget);
    await style.setStyle(InterfaceStyle.legacy);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('计数 1'))).brightness,
      Brightness.light,
    );
    expect(find.text('未保存草稿'), findsOneWidget);
    await style.setStyle(InterfaceStyle.modern);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('计数 1'))).brightness,
      Brightness.dark,
    );
    expect(find.text('未保存草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
