import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/widgets/modern_feature_carousel.dart';
import 'modern_home_controller_test.dart' show item;
import 'package:kazumi/presentation/modern/home/home_catalog.dart';
import 'package:kazumi/services/source/whisklet/whisklet_catalog.dart';
import 'package:kazumi/services/source/whisklet/whisklet_client.dart';
import 'package:kazumi/services/source/whisklet/whisklet_home_controller.dart';
import 'package:kazumi/services/source/whisklet/whisklet_models.dart';

/// Layout fixtures now enter the same Lumina card path as production.
class _FixtureLuminaHome extends LuminaHomeController {
  _FixtureLuminaHome(this.controller) : super(LuminaService()) {
    controller.addListener(sync);
    sync();
  }
  final ModernHomeController controller;
  void sync() {
    channels = [
      LuminaChannel.fromJson({'id': '1', 'name': '动漫'}),
    ];
    channelId = '1';
    items = [
      for (final item in controller.items)
        LuminaVideo.fromJson({
          'id': '${item.id}',
          'title': item.nameCn,
          'updatedTo': 2,
        }),
    ];
    channelItems['1'] = items;
    banners = [
      for (final video in items)
        LuminaBanner.fromJson({
          'videoId': video.id,
          'title': video.title,
          'cover': 'https://images.example/${video.id}.jpg',
        }),
    ];
    loading = controller.loading;
    notifyListeners();
  }

  @override
  List<LuminaChannel> browseChannels([String bucket = 'all']) => channels;
  @override
  bool hasMoreIn(String bucket) => controller.hasMore;
  @override
  bool loadingIn(String bucket) => controller.loading;
  @override
  Future<void> loadMoreIn(String bucket) => controller.loadMore();
  @override
  Future<void> bootstrap({bool force = false, bool warmOtherChannels = true}) =>
      controller.refresh();
  @override
  void dispose() {
    controller.removeListener(sync);
    service.dispose();
    super.dispose();
  }
}

Future<void> mountHome(
  WidgetTester tester,
  ModernHomeController controller, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  VoidCallback? onSearch,
  VoidCallback? onCalendar,
  ValueChanged<String>? onBrowse,
  VoidCallback? onHistory,
  VoidCallback? onTheme,
  ValueChanged<History>? onResume,
  ValueChanged<int>? onDetails,
  WhiskletHomeController? whisklet,
  ValueChanged<WhiskletWork>? onWhiskletDetails,
  SdkRankController? ranking,
  ValueChanged<SdkPlaybackEntry>? onRankDetails,
}) async {
  final anime = _FixtureLuminaHome(controller);
  addTearDown(anime.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ModernHomeView(
        controller: controller,
        anime: anime,
        whisklet: whisklet,
        onWhiskletDetails: onWhiskletDetails,
        ranking: ranking,
        onRankDetails: onRankDetails,
        onAnimeDetails: (video) => onDetails?.call(int.parse(video.id)),
        onAnimeBanner: (banner) => onDetails?.call(int.parse(banner.videoId)),
        onSearch: onSearch ?? () {},
        onCalendar: onCalendar ?? () {},
        onBrowse: onBrowse ?? (_) {},
        onHistory: onHistory ?? () {},
        onToggleTheme: onTheme ?? () {},
        onDetails: (subject) => onDetails?.call(subject.id),
        onResume: onResume ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'category rails scroll independently and expose more and corner metadata',
    (tester) async {
      String? opened;
      final controller = ModernHomeController(
        loadFeed: (_, _) async => List.generate(24, item),
        readHistory: () => [],
        loadCatalog: () async => HomeCatalog(
          chinese: List.generate(10, (i) => item(i + 100)),
          japanese: List.generate(10, (i) => item(i + 200)),
          airing: {0: const HomeAiring(6, '21:05')},
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(tester, controller, onBrowse: (tag) => opened = tag);
      final rail = find.byKey(const PageStorageKey('home-channel-lumina:1'));
      final poster = find.byKey(const ValueKey('home-poster-lumina:0'));
      expect(
        find.byKey(const ValueKey('home-rating-lumina:0')),
        findsNothing,
      );
      expect(find.text('暂无'), findsNothing);
      expect(
        tester
            .getBottomRight(find.byKey(const ValueKey('home-airing-lumina:0')))
            .dy,
        greaterThan(tester.getTopLeft(poster).dy + 100),
      );
      final time = tester.widget<Text>(
        find.byKey(const ValueKey('home-airing-lumina:0')),
      );
      expect(time.data, '更新至 2 集');
      expect(time.style!.backgroundColor, isNull);
      expect(time.style!.shadows, isNull);
      expect(
        _tooltip('资料收录的放送安排（原播出地时间），非播放源更新时间；未收录时显示待定。'),
        findsNothing,
      );
      expect(Theme.of(tester.element(poster)).brightness, Brightness.dark);
      expect(tester.widget<InkWell>(poster).hoverColor, Colors.transparent);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('home-cover-scale-lumina:0')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('home-cover-scale-lumina:0')),
            )
            .scale,
        greaterThan(1),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(
              find.byKey(const ValueKey('home-cover-scale-lumina:0')),
            )
            .scale,
        1,
      );
      await mouse.removePointer();
      await tester.ensureVisible(rail);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(of: rail, matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(rail, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(before),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-more-lumina:1')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final vertical = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      // 保留固定分类栏的空间，避免按钮被滚到栏后而点不中。
      vertical.jumpTo(
        (vertical.pixels - 110).clamp(
          vertical.minScrollExtent,
          vertical.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-more-lumina:1')));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text('推荐·动漫'), findsWidgets);
      expect(opened, isNull);
      expect(find.text('左右滑动'), findsNothing);
      expect(find.byKey(const ValueKey('home-load-more')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('recommended and popular entries retain only anime navigation', (
    tester,
  ) async {
    final controller = ModernHomeController(
      loadFeed: (feed, _) async =>
          List.generate(24, (i) => item(i + feed.index * 100)),
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await mountHome(tester, controller);
    expect(find.text('找到今天的心动番剧'), findsNothing);
    expect(find.byKey(const ValueKey('home-load-more')), findsNothing);
    final selector = find.byKey(const ValueKey('home-feed-selector'));
    // 两个聚合位 + 上游 7 个风格频道（tid 1/2/4/5/21/22/20 一一对应）。
    for (final label in [
      '推荐',
      '热门',
      '电影',
      '电视剧',
      '动漫',
      '综艺',
      '短剧',
      'AI漫剧',
      '电视直播',
    ]) {
      expect(
        find.descendant(of: selector, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.byType(TabBar), findsNothing);

    TextStyle labelStyle(String feed) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('home-feed-$feed')),
            matching: find.byType(Text),
          ),
        )
        .style!;

    // 初始 feed 是 recommended：默认选中「推荐」，「动漫」为未选中态。
    expect(labelStyle('recommended').fontSize, 16);
    expect(labelStyle('recommended').fontWeight, FontWeight.w700);
    expect(labelStyle('anime').fontSize, 15);
    expect(labelStyle('anime').fontWeight, FontWeight.w500);
    expect(labelStyle('popular').fontSize, 15);
    expect(labelStyle('popular').fontWeight, FontWeight.w500);

    await tester.drag(selector, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.recommended);
    await tester.drag(selector, const Offset(400, 0)); // 回到行首再点，避免点到视口外
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-feed-popular')));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.popular);
    expect(labelStyle('popular').fontWeight, FontWeight.w700);
    await tester.tap(find.byKey(const ValueKey('home-feed-recommended')));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.recommended);
    // 风格频道由第二内容源出片；没有第二源时正文为空，但选中态必须切换。
    controller.selectFeed(HomeFeed.shortDrama);
    await tester.pumpAndSettle();
    expect(labelStyle('shortDrama').fontWeight, FontWeight.w700);
    expect(labelStyle('anime').fontWeight, FontWeight.w500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anime feed triggers the second-source shelf load', (
    tester,
  ) async {
    final controller = ModernHomeController(
      loadFeed: (_, _) async => [item(1)],
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    final catalog = _SecondSourceCatalog();
    final source = WhiskletHomeController(catalog: catalog);
    addTearDown(source.dispose);
    await controller.refresh();
    await mountHome(tester, controller, whisklet: source);
    // 聚合位（推荐/热门）之外的风格频道不应在进首页时被预取。
    expect(catalog.browsed, isEmpty);
    controller.selectFeed(HomeFeed.anime);
    await tester.pumpAndSettle();
    // 回归点：动漫主源是 Lumina，第二源副货架仍要在切到该频道时触发加载。
    expect(catalog.browsed, [HomeStyle.anime.tid]);
    expect(source.of(HomeStyle.anime).map((work) => work.title), [
      '星轨信使',
      '幻夜巡游',
    ]);
    await tester.scrollUntilVisible(
      find.text('星轨信使'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('动漫 · 第二源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('second-source card tap forwards the work to the details handler', (
    tester,
  ) async {
    final controller = ModernHomeController(
      loadFeed: (_, _) async => [item(1)],
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    final catalog = _SecondSourceCatalog();
    final source = WhiskletHomeController(catalog: catalog);
    addTearDown(source.dispose);
    await controller.refresh();
    WhiskletWork? opened;
    await mountHome(
      tester,
      controller,
      whisklet: source,
      onWhiskletDetails: (work) => opened = work,
    );
    controller.selectFeed(HomeFeed.anime);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('星轨信使'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('星轨信使'));
    await tester.pumpAndSettle();
    expect(opened?.id, 401);
    expect(opened?.title, '星轨信使');
    // 回调已接管点击：不再弹「播放链路将在下一阶段接入」的占位提示。
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('style channels keep only their own second-source content', (
    tester,
  ) async {
    final history = History(item(9), 3, 'test', DateTime(2026), '', '');
    history.progresses[3] = Progress(3, 0, 503000);
    final controller = ModernHomeController(
      loadFeed: (_, _) async => List.generate(4, item),
      readHistory: () => [history],
    );
    addTearDown(controller.dispose);
    final catalog = _SecondSourceCatalog();
    final source = WhiskletHomeController(catalog: catalog);
    addTearDown(source.dispose);
    final ranking = SdkRankController();
    addTearDown(ranking.dispose);
    await controller.refresh();
    await mountHome(
      tester,
      controller,
      whisklet: source,
      ranking: ranking,
      onRankDetails: (_) {},
    );
    controller.selectFeed(HomeFeed.movies);
    await tester.pumpAndSettle();
    expect(catalog.browsed, [HomeStyle.movie.tid]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('whisklet-grid-movie')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('星轨信使'), findsOneWidget);
    // 跨分类内容一律不得混入风格频道：个人历史、Lumina 榜单、Lumina 横幅、动漫副货架。
    expect(find.text('继续观看'), findsNothing);
    expect(find.text('热播推荐'), findsNothing);
    expect(find.byType(ModernFeatureCarousel), findsNothing);
    expect(find.text('动漫 · 第二源'), findsNothing);

    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    // 聚合位（推荐）仍保留历史与榜单：收口只针对风格频道。
    controller.selectFeed(HomeFeed.recommended);
    await tester.pumpAndSettle();
    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('热播推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      testWidgets('loaded home at $size, dark=$dark, enlarged text', (
        tester,
      ) async {
        final history = History(item(9), 3, 'test', DateTime(2026), '', '');
        history.progresses[3] = Progress(3, 0, 503000);
        final controller = ModernHomeController(
          loadFeed: (_, _) async => List.generate(6, item),
          readHistory: () => [history],
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        await mountHome(tester, controller, size: size, scale: 1.6, dark: dark);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-poster-lumina:0')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('home-poster-lumina:0')),
          findsWidgets,
        );
      });
    }
  }

  testWidgets(
    'search, calendar, details and resume preserve callbacks and identity',
    (tester) async {
      var searches = 0, calendars = 0;
      int? details;
      History? resumed;
      final history = History(item(9), 3, 'test', DateTime(2026), '', '');
      history.progresses[3] = Progress(3, 0, 503000);
      final controller = ModernHomeController(
        loadFeed: (_, _) async => [item(1)],
        readHistory: () => [history],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(
        tester,
        controller,
        onSearch: () => searches++,
        onCalendar: () => calendars++,
        onDetails: (id) => details = id,
        onResume: (entry) => resumed = entry,
      );
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-calendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('番剧 1').first);
      await tester.ensureVisible(
        find.byKey(ValueKey('home-resume-${history.key}')),
      );
      await tester.tap(find.byKey(ValueKey('home-resume-${history.key}')));
      expect(searches, 1);
      expect(calendars, 1);
      expect(find.byKey(const ValueKey('home-history')), findsNothing);
      expect(find.byKey(const ValueKey('home-theme')), findsNothing);
      expect(details, 1);
      expect(resumed, same(history));
      expect(find.text('第 3 集 · 8:23'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feed selection loads new subjects and retry recovers an empty response',
    (tester) async {
      var empty = true;
      final controller = ModernHomeController(
        loadFeed: (feed, _) async => empty ? [] : [item(feed.index + 1)],
        readHistory: () => [],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await mountHome(tester, controller);
      expect(find.text('这个分类暂时没有符合条件的作品'), findsOneWidget);
      empty = false;
      await tester.tap(find.text('重试').first);
      await tester.pumpAndSettle();
      final recommendation = tester.widget<ModernFeatureCarousel>(
        find.byKey(const ValueKey('home-primary-recommendations')),
      );
      expect(recommendation.entries.single.title, '番剧 1');
      await tester.tap(find.byKey(const ValueKey('home-feed-anime')));
      await tester.pumpAndSettle();
      expect(controller.items.single.id, HomeFeed.anime.index + 1);
      expect(controller.hasMore, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _StubTransport extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('stub: widget tests must not reach the network');
  }
}

/// 只覆写目录层；触网由用例断言 `browsed` 记录来验证。
class _SecondSourceCatalog extends WhiskletCatalog {
  _SecondSourceCatalog() : super(client: WhiskletClient(transport: _StubTransport()));
  final List<int> browsed = [];

  @override
  Future<WhiskletPage> browse(int category, int page, {cancel}) async {
    browsed.add(category);
    return WhiskletPage(
      items: [
        WhiskletWork.fromRow({
          'vod_id': 401,
          'vod_name': '星轨信使',
          'vod_pic': '//img.example/a.jpg',
          'vod_remarks': '更新至12集',
          'type_id': 4,
        })!,
        WhiskletWork.fromRow({'vod_id': 402, 'vod_name': '幻夜巡游', 'type_id': 4})!,
      ],
      page: page,
      pages: 1,
    );
  }
}

Finder _tooltip(String message) => find.byWidgetPredicate((widget) =>
  widget is PlayraIconButton && widget.tooltip == message ||
  widget is Tooltip && widget.message == message);
