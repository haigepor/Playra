import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/my/watch_stats.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/my/my_page.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';
import 'package:kazumi/presentation/modern/pages/profile_page.dart';
import 'package:kazumi/presentation/modern/profile/modern_profile_view.dart';
import 'package:kazumi/presentation/modern/profile/profile_sync_state.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';

const local = ProfileSyncState(bangumi: '未连接 · 连接后可同步追番', webDav: '未配置');
ProfileSyncState state({
  bool connecting = false,
  bool token = false,
  bool error = false,
  bool verified = false,
  bool enabled = false,
  bool configured = false,
  bool davEnabled = false,
  bool content = false,
}) => ProfileSyncState.from(
  connecting: connecting,
  hasToken: token,
  connectionError: error,
  verified: verified,
  bangumiEnabled: enabled,
  username: '已验证用户',
  webDavConfigured: configured,
  webDavEnabled: davEnabled,
  webDavHasContent: content,
);

class _Histories implements IHistoryRepository {
  final events = StreamController<void>.broadcast();
  List<History> records = [];
  @override
  Stream<void> get changes => events.stream;
  @override
  List<History> getAllHistories() => records;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads implements IDownloadRepository {
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => events.stream;
  @override
  List<DownloadRecord> getAllRecords() => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shield implements IDanmakuShieldRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

History history(String rule, List<int> episodes) =>
    History(
        BangumiItem.fromJson({
          'id': 123,
          'name': '测试番剧',
          'rating': <String, dynamic>{},
          'images': <String, String>{},
        }),
        1,
        rule,
        DateTime(2026),
        '',
        '',
      )
      ..progresses.addAll({
        for (final episode in episodes) episode: Progress(episode, 0, 100),
      });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_profile_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    final root = directory.absolute.path;
    expect(root.startsWith(Directory.systemTemp.absolute.path), isTrue);
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('playra_profile_test_'),
    );
    await directory.delete(recursive: true);
  });
  test('连接状态按验证结果和开关展示，配置不意味着同步成功', () {
    expect(state(connecting: true).bangumi, '正在验证连接');
    expect(state(error: true).bangumi, local.bangumi);
    expect(
      state(token: true, error: true, verified: true).bangumi,
      '连接异常 · 点击检查',
    );
    expect(state(token: true).bangumi, '待验证 · 打开设置检查连接');
    expect(state(token: true).username, isEmpty);
    expect(state(token: true, verified: true).bangumi, '已连接 · 同步关闭');
    expect(
      state(token: true, verified: true, enabled: true).bangumi,
      '已连接 · 追番同步已开启',
    );
    expect(state(token: true, verified: true).username, '已验证用户');
    expect(state(token: true, verified: true, error: true).username, isEmpty);
    expect(state().webDav, '未配置');
    expect(state(configured: true).webDav, '已配置 · 同步关闭');
    expect(state(configured: true, davEnabled: true).webDav, '待选择同步内容');
    expect(
      state(configured: true, davEnabled: true, content: true).webDav,
      '已开启 · 查看同步设置',
    );
  });

  test('统计保留跨规则去重及所有状态下载任务的原有口径', () {
    final records = [
      DownloadRecord(123, '测试', '', '规则', {
        for (var status = 0; status < 6; status++)
          status + 1: DownloadEpisode(
            status + 1,
            '',
            0,
            status,
            0,
            0,
            0,
            '',
            '',
            '',
            null,
            '',
            0,
            '',
          ),
      }, DateTime(2026)),
    ];
    final stats = WatchStats.from(
      histories: [
        history('a', [1, 2]),
        history('b', [2, 3]),
      ],
      downloadRecords: records,
    );
    expect(stats.watchedBangumiCount, 1);
    expect(stats.watchedEpisodeCount, 3);
    expect(stats.downloadTaskCount, 6);
  });

  Future<void> pumpView(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    WatchStats stats = const WatchStats(),
    ValueChanged<String>? onOpen,
    VoidCallback? onDiscover,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
          ),
          child: ModernHomeScope(
            child: Scaffold(
              body: ModernProfileView(
                stats: stats,
                sync: const ProfileSyncState(
                  bangumi: '已连接 · 追番同步已开启',
                  webDav: '已开启 · 查看同步设置',
                  username: '长用户名长用户名长用户名长用户名长用户名长用户名',
                ),
                version: '测试版本',
                onOpen: onOpen ?? (_) {},
                onDiscover: onDiscover ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 760.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('宽度 $width 字号 $scale，零记录及长数字无溢出，末项可到达', (tester) async {
        await pumpView(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('去发现番剧'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('组件实验室'), 180);
        expect(tester.takeException(), isNull);
        await pumpView(
          tester,
          width: width,
          scale: scale,
          stats: const WatchStats(
            watchedBangumiCount: 12345678,
            watchedEpisodeCount: 987654321,
            downloadTaskCount: 6,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('987654321'), findsOneWidget);
        expect(find.text('6 集任务'), findsOneWidget);
        expect(find.text('去发现番剧'), findsNothing);
      });
    }
  }

  testWidgets('我的底栏保持暗色，顶部和底部安全区各消费一次', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: ModernShell(
            selectedIndex: 3,
            selectDestination: (_) {},
            outlet: ModernHomeScope(
              child: ModernProfileView(
                stats: const WatchStats(),
                sync: local,
                version: 'test',
                onOpen: (_) {},
                onDiscover: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.byKey(const ValueKey('modern-navigation'));
    expect(Theme.of(tester.element(nav)).brightness, Brightness.dark);
    expect(
      Theme.of(tester.element(nav)).navigationBarTheme.backgroundColor,
      const Color(0xff1b202c),
    );
    expect(tester.getTopLeft(find.byTooltip('全部设置')).dy, 24);
    expect(tester.getBottomRight(nav).dy, 810);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏矮窗口保留滚动及设置动作', (tester) async {
    await pumpView(tester, width: 844, height: 390, scale: 2);
    await tester.scrollUntilVisible(find.text('组件实验室'), 180);
    expect(find.byTooltip('全部设置').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制器替换释放旧订阅，卸载释放新订阅', (tester) async {
    final oldHistory = _Histories();
    final oldDownload = _Downloads();
    final newHistory = _Histories();
    final newDownload = _Downloads();
    final oldController = MyController(oldHistory, oldDownload, _Shield());
    final newController = MyController(newHistory, newDownload, _Shield());
    Future<void> mount(MyController controller) => tester.pumpWidget(
      MaterialApp(
        home: TabDestinationScope(
          selectDestination: (_) {},
          child: ModernProfilePage(
            controller: controller,
            readSyncState: () => local,
          ),
        ),
      ),
    );
    await mount(oldController);
    expect(oldHistory.events.hasListener, isTrue);
    await mount(newController);
    expect(oldHistory.events.hasListener, isFalse);
    expect(oldDownload.events.hasListener, isFalse);
    expect(newHistory.events.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(newHistory.events.hasListener, isFalse);
    expect(newDownload.events.hasListener, isFalse);
    for (final events in [
      oldHistory.events,
      oldDownload.events,
      newHistory.events,
      newDownload.events,
    ]) {
      await events.close();
    }
  });

  testWidgets('所有入口按契约派发，发现动作独立', (tester) async {
    String? opened;
    var discovered = false;
    await pumpView(
      tester,
      onOpen: (path) => opened = path,
      onDiscover: () => discovered = true,
    );
    await tester.tap(find.text('去发现番剧'));
    expect(discovered, isTrue);
    await tester.tap(find.byTooltip('全部设置'));
    expect(opened, '/settings/');
    for (final entry in const [
      ('历史记录', '/settings/history/'),
      ('离线缓存', '/settings/download/'),
      ('播放规则', '/settings/plugin/'),
      ('外观设置', '/settings/theme'),
      ('播放设置', '/settings/player'),
      ('弹幕设置', '/settings/danmaku/'),
      ('页面版本', '/settings/interface'),
      ('Bangumi 追番同步', '/settings/bangumi/'),
      ('WebDAV 多设备同步', '/settings/webdav/'),
      ('全部同步设置', '/settings/sync'),
      ('存储管理', '/settings/storage'),
      ('关于应用', '/settings/about/'),
      ('组件实验室', '/ui/components'),
    ]) {
      await tester.ensureVisible(find.text(entry.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1));
      expect(opened, entry.$2);
    }
    expect(find.text('Playra · 测试版本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('覆盖、返回、共享新旧版及恢复时监听成对释放且统计更新', (tester) async {
    final histories = _Histories();
    final downloads = _Downloads();
    final controller = MyController(histories, downloads, _Shield());
    var sync = local;
    Future<void> page({bool covered = false, bool legacy = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: TabDestinationScope(
              selectDestination: (_) {},
              child: RouteVisibility(
                isCovered: covered,
                child: legacy
                    ? MyPage(controller: controller)
                    : ModernProfilePage(
                        controller: controller,
                        readSyncState: () => sync,
                      ),
              ),
            ),
          ),
        );
    await page();
    await tester.pumpAndSettle();
    expect(histories.events.hasListener, isTrue);
    histories.records = [
      history('a', [1]),
      history('b', [1, 2]),
    ];
    histories.events.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(controller.watchStats.watchedEpisodeCount, 2);
    expect(find.text('观看足迹'), findsOneWidget);
    await page(covered: true);
    await tester.pump();
    expect(histories.events.hasListener, isFalse);
    expect(downloads.events.hasListener, isFalse);
    histories.records = [];
    sync = const ProfileSyncState(
      bangumi: '待验证 · 打开设置检查连接',
      webDav: '已配置 · 同步关闭',
    );
    await page();
    await tester.pumpAndSettle();
    expect(controller.watchStats.watchedEpisodeCount, 0);
    expect(find.text(sync.bangumi), findsOneWidget);
    await page(legacy: true);
    await tester.pumpAndSettle();
    expect(histories.events.hasListener, isTrue);
    await page();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(histories.events.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(histories.events.hasListener, isFalse);
    expect(downloads.events.hasListener, isFalse);
    await histories.events.close();
    await downloads.events.close();
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
