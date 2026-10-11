import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/info/character_info_view.dart';
import 'package:kazumi/pages/info/character_page.dart';
import 'package:kazumi/bean/widget/image_preview.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/pages/onboarding/onboarding_step_layout.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';
import 'package:kazumi/request/core/dio_factory.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Collect implements ICollectRepository {
  @override
  bool getPrivateMode() => true;
  @override
  Set<int> getBangumiIdsByType(dynamic type) => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Histories implements ISearchHistoryRepository {
  List<SearchHistory> values = [SearchHistory('一条可以删除的搜索记录', 1)];
  @override
  List<SearchHistory> getAllHistories() => values;
  @override
  Future<void> deleteHistory(SearchHistory history) async =>
      values.remove(history);
  @override
  Future<void> clearAllHistories() async => values.clear();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends SearchPageController {
  _Controller(this.histories) : super(_Collect(), histories);
  final _Histories histories;
  List<String> queries = [];
  bool failed = false;
  @override
  bool get lastSearchFailed => failed;
  @override
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    queries.add(input);
    isLoading = false;
  }
}

class _Adapter implements HttpClientAdapter {
  String body = '{"data":[]}';
  String Function(RequestOptions)? bodyFor;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    bodyFor?.call(options) ?? body,
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_secondary_test_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = oldPaths;
    // 删除仅限本测试创建且已验证的临时目录。
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((p) => p.isNotEmpty).last,
      startsWith('playra_secondary_test_'),
    );
    await directory.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    double scale = 1,
    bool modern = true,
    double inset = 0,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: modern ? ModernSecondaryScope(child: child) : child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('真实控制器区分成功空结果、失败与恢复，不改变旧版字段', () async {
    final adapter = _Adapter();
    final dio = DioFactory.bangumiDio;
    final oldAdapter = dio.httpClientAdapter;
    dio.httpClientAdapter = adapter;
    addTearDown(() => dio.httpClientAdapter = oldAdapter);
    final controller = SearchPageController(_Collect(), _Histories());
    await controller.searchBangumi('不存在', type: 'init');
    expect(controller.lastSearchFailed, isFalse);
    expect(controller.bangumiList, isEmpty);
    adapter.body = '{}';
    await controller.searchBangumi('失败', type: 'init');
    expect(controller.lastSearchFailed, isTrue);
    adapter.body = '{"data":[]}';
    await controller.searchBangumi('恢复', type: 'init');
    expect(controller.lastSearchFailed, isFalse);
  });

  for (final width in [320.0, 390.0, 760.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('搜索和条件草稿：$width / $scale', (tester) async {
        final controller = _Controller(_Histories());
        await mount(
          tester,
          SearchPage(controller: controller, modern: true),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        final bar = tester.widget<SearchBar>(find.byType(SearchBar));
        final colors = Theme.of(
          tester.element(find.byType(SearchBar)),
        ).colorScheme;
        // 全局浅色主题的中间层级不能渗入新版搜索框。
        expect(bar.backgroundColor!.resolve({}), colors.surfaceContainerLow);
        await tester.tap(find.text('按条件查找'));
        await tester.pumpAndSettle();
        expect(find.text('应用筛选'), findsOneWidget);
        final historyLength = controller.histories.values.length;
        // 关闭草稿没有查询或历史写入。
        Navigator.of(tester.element(find.text('筛选番剧'))).pop();
        await tester.pumpAndSettle();
        expect(controller.queries, isEmpty);
        expect(controller.histories.values.length, historyLength);
        expect(tester.takeException(), isNull);
      });
      testWidgets('上传/链接与键盘布局：$width / $scale', (tester) async {
        final controller = _Controller(_Histories());
        await mount(
          tester,
          ImageSearchPage(controller: controller, modern: true),
          width: width,
          scale: scale,
          inset: 260,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('图片链接'));
        await tester.pumpAndSettle();
        expect(find.text('图片链接'), findsWidgets);
        expect(find.byType(TextField), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        field.controller!.text = 'not-a-url';
        await tester.pump();
        final action = tester.widget<FilledButton>(
          find.byKey(const ValueKey('image-search-primary')),
        );
        expect(action.onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('搜索历史管理与真实输入提交', (tester) async {
    final controller = _Controller(_Histories());
    await mount(tester, SearchPage(controller: controller, modern: true));
    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除这条搜索记录'));
    await tester.pump();
    expect(controller.histories.values, isEmpty);
    await tester.enterText(find.byType(TextField), '芙莉莲');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(controller.queries.single, contains('芙莉莲'));
    expect(find.text('没有找到匹配的番剧'), findsOneWidget);
  });
  testWidgets('应用条件只提交一次，标签删除后同步查询', (tester) async {
    final controller = _Controller(_Histories());
    await mount(tester, SearchPage(controller: controller, modern: true));
    await tester.tap(find.text('按条件查找'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('题材标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常'));
    await tester.pump();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(controller.queries, hasLength(1));
    expect(controller.queries.single, contains('日常'));
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.byTooltip('移除“日常”条件'));
    await tester.pumpAndSettle();
    expect(controller.queries, hasLength(2));
    expect(controller.queries.last, isNot(contains('日常')));
    expect(find.byType(InputChip), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('新版图片保留原生图库与分页，关闭区域可达', (tester) async {
    await mount(
      tester,
      ImageViewer(
        imageUrls: const [
          'https://example.com/first.png',
          'https://example.com/second.png',
        ],
        modern: true,
      ),
      width: 320,
    );
    expect(find.byType(PhotoViewGallery), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    final close = find.byKey(const ValueKey('image-preview-close'));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byIcon(LucideIcons.chevronRight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('真实结果卡片在窄屏大字体完整布局', (tester) async {
    final controller = _Controller(_Histories());
    final item = BangumiItem(
      id: 123,
      type: 2,
      name: '原名',
      nameCn: '非常长的番剧名称用于检查两行标题与评分信息布局',
      summary: '',
      airDate: '2026-10-01',
      airWeekday: 1,
      rank: 0,
      images: {},
      tags: [],
      alias: [],
      ratingScore: 8.2,
      votes: 1,
      votesCount: [],
      info: '',
    );
    controller.bangumiList.add(item);
    await mount(
      tester,
      SearchPage(controller: controller, modern: true),
      width: 320,
      scale: 2,
    );
    await tester.enterText(find.byType(TextField), '长标题');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('已加载 1 部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('人物紧凑资料和引导长文在大字体可滚动', (tester) async {
    final character = CharacterFullItem.fromJson({
      'id': 1,
      'name': '原名',
      'name_cn': '中文人物名',
      'summary': List.filled(30, '这是人物简介。').join(),
      'infobox': [
        {'key': '生日', 'value': '12月20日'},
      ],
    });
    await mount(
      tester,
      Scaffold(
        body: CharacterInfoView(
          character: character,
          characterName: '中文人物名',
          characterRelation: '主角',
          actorNames: const ['配音姓名'],
        ),
      ),
      width: 320,
      scale: 2,
    );
    expect(find.text('中文人物名'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.pump();
    await mount(
      tester,
      Scaffold(
        body: OnboardingStepLayout(
          leading: const Icon(Icons.play_arrow),
          title: '准备好下一段故事',
          subtitle: '查看使用约定，然后选择访问方式。',
          child: Text(List.filled(60, '使用约定内容。').join()),
        ),
      ),
      width: 320,
      scale: 2,
    );
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('人物完整页加载接口并切换资料与真实空评论', (tester) async {
    final requests = <String>[];
    final adapter = _Adapter()
      ..bodyFor = (options) {
        requests.add(options.path);
        return options.path.contains('/comments')
            ? '[]'
            : '{"id":123,"name":"人物原名","nameCN":"接口人物名","summary":"来自接口的完整简介","infobox":[],"images":{}}';
      };
    final dio = DioFactory.bangumiDio;
    final oldAdapter = dio.httpClientAdapter;
    dio.httpClientAdapter = adapter;
    addTearDown(() => dio.httpClientAdapter = oldAdapter);
    await mount(
      tester,
      const CharacterPage(
        characterID: 123,
        characterName: '点击入口名称',
        characterRelation: '主角',
        modern: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.every((url) => url.contains('123')), isTrue);
    expect(find.text('接口人物名'), findsOneWidget);
    expect(find.text('来自接口的完整简介'), findsOneWidget);
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).indicator,
      isA<UnderlineTabIndicator>(),
    );
    await tester.tap(find.text('吐槽'));
    await tester.pumpAndSettle();
    expect(find.text('还没有评论'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    expect(find.text('接口人物名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('旧版搜索和以图搜番保持原呈现', (tester) async {
    final controller = _Controller(_Histories());
    await mount(tester, SearchPage(controller: controller), modern: false);
    expect(find.text('番剧搜索'), findsOneWidget);
    final bar = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(bar.constraints!.minHeight, 64);
    await mount(tester, ImageSearchPage(controller: controller), modern: false);
    expect(find.text('这一幕，\n出自哪部番？'), findsOneWidget);
    expect(find.text('本地图片'), findsOneWidget);
  });
  testWidgets('错误详情与真实操作回调', (tester) async {
    var taps = 0;
    await mount(
      tester,
      Scaffold(
        body: SecondaryFailureView(
          title: '失败',
          message: '实际原因',
          details: '可复制的详细原因',
          action: () => taps++,
        ),
      ),
      width: 320,
      scale: 2,
    );
    await tester.tap(find.text('返回首页'));
    expect(taps, 1);
    await tester.tap(find.text('查看详细信息'));
    await tester.pumpAndSettle();
    expect(find.text('可复制的详细原因'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
