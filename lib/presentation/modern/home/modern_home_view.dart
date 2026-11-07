import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;
import 'package:kazumi/utils/image_extension.dart' show isFlutterTestBinding;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../modern_layout.dart';
import '../widgets/modern_page_art.dart';
import '../widgets/modern_section_mark.dart';
import '../widgets/modern_feature_carousel.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'home_theme.dart';
import 'modern_home_controller.dart';
import 'home_content_algorithm.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_models.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/whisklet/whisklet_home_controller.dart';
import 'package:kazumi/services/source/whisklet/whisklet_models.dart';
import 'package:kazumi/services/source/hongguo/hongguo_home_controller.dart';
import 'package:kazumi/services/source/hongguo/hongguo_models.dart';
import 'package:kazumi/services/source/content_search.dart' show ContentGroup;
import '../player/sdk_rank_section.dart';
import '../pages/modern_category_list_page.dart';
import 'home_anime_card.dart';
import 'home_display_session.dart';
import 'home_frame_updates.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';
import 'package:kazumi/pages/history/personal_history_query.dart';
import '../library/sdk_library_widgets.dart';

String homeTitle(BangumiItem item) =>
    item.nameCn.isEmpty ? item.name : item.nameCn;

String homeCover(BangumiItem item) {
  for (final size in ['large', 'common', 'medium', 'small']) {
    final url = item.images[size];
    if (url != null && url.isNotEmpty) return url;
  }
  return '';
}

class ModernHomeView extends StatefulWidget {
  const ModernHomeView({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onCalendar,
    required this.onBrowse,
    required this.onHistory,
    required this.onToggleTheme,
    required this.onDetails,
    required this.onResume,
    this.anime,
    this.onAnimeDetails,
    this.onAnimeBanner,
    this.ranking,
    this.onRankDetails,
    this.refreshRanking,
    this.refreshAnime,
    this.whisklet,
    this.onWhiskletDetails,
    this.hongguo,
    this.onHongguoDetails,
  });
  final ModernHomeController controller;
  final LuminaHomeController? anime;

  /// 第二内容源目录：热门/推荐合并展示，风格频道独立出片。
  final WhiskletHomeController? whisklet;

  /// 第二内容源片目点击 → 详情页（播放供给方由路由层组装）。
  final ValueChanged<WhiskletWork>? onWhiskletDetails;

  /// 红果短剧频道：热榜 + 推荐流，独立出片。
  final HongguoHomeController? hongguo;

  /// 红果条目点击 → 详情页。
  final ValueChanged<HongguoSeriesSummary>? onHongguoDetails;
  final ValueChanged<LuminaVideo>? onAnimeDetails;
  final ValueChanged<LuminaBanner>? onAnimeBanner;
  final SdkRankController? ranking;
  final ValueChanged<SdkPlaybackEntry>? onRankDetails;
  final VoidCallback? refreshRanking;
  final Future<void> Function()? refreshAnime;
  final VoidCallback onSearch, onCalendar, onHistory, onToggleTheme;
  final ValueChanged<BangumiItem> onDetails;
  final ValueChanged<History> onResume;
  final ValueChanged<String> onBrowse;

  @override
  State<ModernHomeView> createState() => _ModernHomeViewState();
}

class _ModernHomeViewState extends State<ModernHomeView> {
  ModernHomeController get controller => widget.controller;
  LuminaHomeController? get anime => widget.anime;
  WhiskletHomeController? get whisklet => widget.whisklet;
  ValueChanged<WhiskletWork>? get onWhiskletDetails => widget.onWhiskletDetails;
  HongguoHomeController? get hongguo => widget.hongguo;
  ValueChanged<HongguoSeriesSummary>? get onHongguoDetails =>
      widget.onHongguoDetails;

  /// 本频道由 SDK 目录（Whisklet 或红果）出片，Bangumi 主列表不出片。
  bool get isSdkStyleFeed =>
      controller.feed.isWhiskletStyle || controller.feed.isHongguoStyle;
  ValueChanged<LuminaVideo>? get onAnimeDetails => widget.onAnimeDetails;
  ValueChanged<LuminaBanner>? get onAnimeBanner => widget.onAnimeBanner;
  SdkRankController? get ranking => widget.ranking;
  ValueChanged<SdkPlaybackEntry>? get onRankDetails => widget.onRankDetails;
  VoidCallback? get refreshRanking => widget.refreshRanking;
  Future<void> Function()? get refreshAnime => widget.refreshAnime;
  VoidCallback get onSearch => widget.onSearch;
  VoidCallback get onCalendar => widget.onCalendar;
  VoidCallback get onHistory => widget.onHistory;
  VoidCallback get onToggleTheme => widget.onToggleTheme;
  ValueChanged<BangumiItem> get onDetails => widget.onDetails;
  ValueChanged<History> get onResume => widget.onResume;
  ValueChanged<String> get onBrowse => widget.onBrowse;
  final _sessions = <HomeFeed, HomeDisplaySession>{};
  int _revision = -1, _featuredRevision = 0;

  late HomeFrameUpdates _contentUpdates;
  HomeFrameUpdates _listenContent() =>
      HomeFrameUpdates([controller, ?anime, ?whisklet, ?hongguo]);

  /// 换频道时按需取第二内容源的首屏；已取过的频道不重复请求。
  void _syncWhisklet() {
    final source = whisklet;
    if (source != null) {
      if (controller.feed.isWhiskletStyle) {
        final style = controller.feed.style!;
        unawaited(source.loadStyle(style));
      } else if (controller.feed == HomeFeed.popular) {
        unawaited(source.loadHot());
      } else if (controller.feed == HomeFeed.recommended) {
        unawaited(source.loadShelves());
      } else if (controller.feed == HomeFeed.anime) {
        // 动漫主源是 Lumina，第二源只补一条副货架，仍需在此触发加载。
        unawaited(source.loadStyle(HomeStyle.anime));
      }
    }
    // 红果频道：热榜与推荐流并行首屏。
    if (controller.feed.isHongguoStyle) {
      unawaited(hongguo?.load());
    }
  }

  @override
  void initState() {
    super.initState();
    _contentUpdates = _listenContent();
    controller.addListener(_syncWhisklet);
    _syncWhisklet();
  }

  @override
  void didUpdateWidget(covariant ModernHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller || oldWidget.anime != anime) {
      _contentUpdates.dispose();
      _contentUpdates = _listenContent();
    }
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_syncWhisklet);
      controller.addListener(_syncWhisklet);
      _syncWhisklet();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_syncWhisklet);
    _contentUpdates.dispose();
    super.dispose();
  }

  HomeDisplaySession get _session {
    if (_revision != controller.presentationRevision) {
      _revision = controller.presentationRevision;
      _sessions.clear();
      _featuredRevision = 0;
    }
    return _sessions.putIfAbsent(controller.feed, HomeDisplaySession.new);
  }

  List<HomeAnimeCard> _stableAnime(
    String key,
    List<HomeAnimeCard> preferred,
    List<HomeAnimeCard> fallback, [
    String? bucket,
  ]) => _session.anime(
    key,
    preferred,
    fallback,
    waitingForPrimary:
        anime != null &&
        (anime!.loading || anime!.loadingIn(bucket ?? animeBucket)),
  );

  String get animeBucket => switch (controller.feed) {
    HomeFeed.japanese => 'japanese',
    HomeFeed.chinese => 'chinese',
    HomeFeed.animeMovies => 'movies',
    HomeFeed.season => 'season',
    _ => 'all',
  };
  List<HomeAnimeCard> _sourceCards([String? bucket]) => onAnimeDetails == null
      ? const []
      : [
          for (final video
              in anime?.browseItems(bucket ?? animeBucket) ?? <LuminaVideo>[])
            HomeAnimeCard.lumina(video, () => onAnimeDetails!(video)),
        ];
  String _channelBucket(HomeChannel channel) => switch (channel.id) {
    final id when id.startsWith('lumina:') =>
      'channel:${id.substring('lumina:'.length)}',
    'chinese' => 'chinese',
    'japanese' => 'japanese',
    'anime-movies' => 'movies',
    'season' || 'season-more' || 'region-new' => 'season',
    _ => animeBucket,
  };
  List<HomeAnimeCard> _channelCards(HomeChannel channel) {
    if (channel.id.startsWith('lumina:')) {
      return _sourceCards(_channelBucket(channel));
    }
    final animeCards = _stableAnime(
      'channel-${channel.id}',
      _sourceCards(_channelBucket(channel)),
      const [],
      _channelBucket(channel),
    );
    return _session.append('channel-${channel.id}', animeCards);
  }

  String _channelTitle(HomeChannel channel) => channel.title;
  void _openChannel(BuildContext context, HomeChannel channel) {
    final bucket = _channelBucket(channel);
    _showChannelItems(
      context,
      channel,
      controller,
      onDetails,
      readCards: () => _channelCards(channel),
      sourceUpdates: anime,
      sourceLoadMore: anime == null ? null : () => anime!.loadMoreIn(bucket),
      sourceHasMore: () => anime?.hasMoreIn(bucket) == true,
      sourceLoading: () => anime?.loadingIn(bucket) == true,
      sourceFailed: () => anime?.pageFailedIn(bucket) == true,
      onRefresh: anime == null ? null : () => anime!.bootstrap(force: true),
      onSearch: () => onBrowse(_channelTitle(channel)),
      emptyMessage: '暂无${_channelTitle(channel)}内容',
    );
  }

  void _openOrBrowse(BuildContext context, HomeChannel channel, String tag) {
    if (_sourceCards(_channelBucket(channel)).isNotEmpty) {
      _openChannel(context, channel);
    } else {
      onBrowse(tag);
    }
  }

  /// 第二内容源片目 → 首页卡片，点击进详情页（播放供给方由路由层组装）。
  List<HomeAnimeCard> _whiskletCards(List<WhiskletWork> works) => [
    for (final work in works)
      HomeAnimeCard(
        id: work.identity,
        title: work.title,
        cover: work.cover,
        status: work.remarks,
        subtitle: [
          work.year,
          work.area,
        ].where((value) => value.isNotEmpty).join(' · '),
        year: int.tryParse(work.year),
        onTap: () => _noticeWhisklet(context, work),
      ),
  ];

  void _noticeWhisklet(BuildContext context, WhiskletWork work) {
    final handler = onWhiskletDetails;
    if (handler != null) {
      handler(work);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('《${work.title}》来自第二内容源，播放链路将在下一阶段接入'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// 红果条目 → 详情页；卡片模型由 _HongguoStyleGrid 构造。
  void _noticeHongguo(BuildContext context, HongguoSeriesSummary item) {
    final handler = onHongguoDetails;
    if (handler != null) {
      handler(item);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('《${item.title}》播放链路将在下一阶段接入'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Widget? _whiskletRail(
    BuildContext context,
    String id,
    String title, {
    required List<WhiskletWork> works,
    required bool loading,
    required bool failed,
    required String emptyMessage,
    VoidCallback? onRetry,
    int typeId = 0,
  }) {
    final source = whisklet;
    if (source == null) return null;
    final cards = _whiskletCards(works);
    final style = HomeStyle.ofTid(typeId);
    return _ChannelRail(
      id: id,
      title: title,
      items: cards,
      controller: controller,
      onDetails: (card) => card.onTap(),
      onMore: () {
        if (style != null && source.of(style).isEmpty && !source.loading(style)) {
          source.loadStyle(style);
        }
        _showChannelItems(
          context,
          HomeChannel(id, title, const []),
          controller,
          onDetails,
          readCards: () => style != null && source.of(style).isNotEmpty
              ? _whiskletCards(source.of(style))
              : cards,
          sourceUpdates: style != null ? source : null,
          sourceLoadMore: style != null ? () => source.loadMore(style) : null,
          sourceHasMore: style != null ? () => source.hasMore(style) == true : null,
          sourceLoading: style != null ? () => source.loading(style) == true : null,
          sourceFailed: style != null ? () => source.failed(style) == true : null,
          onRefresh: style != null
              ? () => source.loadStyle(style, refresh: true)
              : null,
          onSearch: () => onBrowse(title),
          initialCards: cards,
          emptyMessage: emptyMessage,
        );
      },
      loading: loading,
      failed: failed,
      emptyMessage: emptyMessage,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: LayoutBuilder(
      builder: (context, bounds) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ModernPageArt(
            kind: ModernPageArtKind.discover,
            contentMaxWidth: 1120,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PlayraLayout.catalogWidth,
                ),
                child: ListenableBuilder(
                  listenable: _contentUpdates,
                  child: _HistorySection(
                    controller: controller,
                    onHistory: onHistory,
                    onResume: onResume,
                  ),
                  builder: (context, recentSection) {
                    final sourceCards = _sourceCards();
                    final animeItems = _stableAnime(
                      'items',
                      sourceCards,
                      const [],
                    );
                    final items = _session.append('items', animeItems);
                    final showAnime =
                        anime != null &&
                        (controller.feed.isAnimeCategory ||
                            controller.feed.isGeneralCategory);
                    final sourcePool =
                        anime?.browseItems(animeBucket) ?? <LuminaVideo>[];
                    final heroCards = <HomeAnimeCard>[];
                    if (animeBucket == 'all' && onAnimeBanner != null) {
                      for (final banner in anime?.banners ?? <LuminaBanner>[]) {
                        final catalog = sourcePool
                            .where((video) => video.id == banner.videoId)
                            .firstOrNull;
                        final cover = banner.cover.isNotEmpty
                            ? banner.cover
                            : catalog?.cover ?? '';
                        if (banner.title.trim().isEmpty ||
                            isBlockedSourceNotice(
                              title: banner.title,
                              cover: cover,
                            )) {
                          continue;
                        }
                        heroCards.add(
                          HomeAnimeCard(
                            id: 'lumina:${banner.videoId}',
                            title: banner.title,
                            cover: cover,
                            onTap: () => onAnimeBanner!(banner),
                            subtitle: catalog?.subtitle ?? '',
                          ),
                        );
                      }
                    }
                    if (animeBucket != 'all' || heroCards.length < 4) {
                      final seenHeroIds = {
                        for (final card in heroCards) card.id,
                      };
                      for (final card in animeItems) {
                        if (seenHeroIds.add(card.id)) {
                          heroCards.add(card);
                        }
                      }
                    }
                    final visibleHeroCards = heroCards.take(6).toList();
                    // 四卡布局依次翻阅来源轮播，不用目录前四项代替推荐。
                    final featured = List<HomeAnimeCard?>.generate(
                      4,
                      (index) => index >= heroCards.length
                          ? null
                          : heroCards[(_featuredRevision * 4 + index) %
                                heroCards.length],
                    );
                    final sourceChannels = [
                      for (final channel
                          in anime?.channels ?? <LuminaChannel>[])
                        HomeChannel(
                          'lumina:${channel.id}',
                          channel.name,
                          const [],
                        ),
                    ];
                    final compact =
                        bounds.maxWidth < 600 || bounds.maxHeight < 500;
                    final smallScreen = isCompactModernViewport(
                      MediaQuery.sizeOf(context),
                    );
                    final horizontalPadding = smallScreen ? 16.0 : 20.0;
                    // 固定导航独立于内容滚动，子分类展开仍可平滑改变内容区高度。
                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            smallScreen
                                ? PlayraSpace.tiny
                                : PlayraSpace.compact,
                            horizontalPadding,
                            smallScreen ? PlayraSpace.xs : PlayraSpace.sm,
                          ),
                          child: _HomeHeader(
                            controller: controller,
                            onSearch: onSearch,
                            onCalendar: onCalendar,
                            compact: smallScreen,
                          ),
                        ),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              Future<void> retryFeed() async {
                                controller.reloadHistory();
                                refreshRanking?.call();
                                // 各来源独立刷新，慢 SDK 不阻塞影视或备用资料请求。
                                final animeRefresh = showAnime
                                    ? (refreshAnime?.call() ??
                                          anime?.bootstrap(force: true))
                                    : null;
                                final whiskletRefresh = whisklet != null
                                    ? (controller.feed == HomeFeed.recommended
                                        ? whisklet!.loadShelves(refresh: true)
                                        : controller.feed == HomeFeed.popular
                                            ? whisklet!.loadHot(refresh: true)
                                            : controller.feed.isWhiskletStyle
                                                ? whisklet!.loadStyle(
                                                    controller.feed.style!,
                                                    refresh: true,
                                                  )
                                                : null)
                                    : null;
                                final hongguoRefresh =
                                    controller.feed.isHongguoStyle
                                    ? hongguo?.load(refresh: true)
                                    : null;
                                await Future.wait([
                                  controller.refresh(),
                                  ?animeRefresh,
                                  ?whiskletRefresh,
                                  ?hongguoRefresh,
                                ]);
                              }

                              return RefreshIndicator(
                                onRefresh: retryFeed,
                                child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                // 只在尾部继续向下滚动时取下一页，横向栏目和刷新不触发。
                                if (notification.depth == 0 &&
                                    notification.metrics.axis ==
                                        Axis.vertical &&
                                    notification.metrics.extentAfter < 480 &&
                                    (notification is ScrollUpdateNotification &&
                                            (notification.scrollDelta ?? 0) >
                                                0 ||
                                        notification
                                                is OverscrollNotification &&
                                            notification.overscroll > 0)) {
                                  if (controller.feed.isWhiskletStyle) {
                                    whisklet?.loadMore(controller.feed.style!);
                                  } else if (controller.feed.isHongguoStyle) {
                                    hongguo?.loadMoreDiscover();
                                  } else if (anime?.pageFailedIn(animeBucket) !=
                                      true) {
                                    anime?.loadMoreIn(animeBucket);
                                  }
                                }
                                return false;
                              },
                              child: CustomScrollView(
                                key: const PageStorageKey('modern-home-scroll'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      horizontalPadding,
                                      smallScreen ? 0 : PlayraSpace.xs,
                                      horizontalPadding,
                                      0,
                                    ),
                                    sliver: SliverList.list(
                                      children: [
                                        if (controller.feed ==
                                                HomeFeed.recommended &&
                                            !compact &&
                                            (featured.any(
                                                  (card) => card != null,
                                                ) ||
                                                anime?.loading == true))
                                          _RecommendationBento(
                                            key: const ValueKey(
                                              'home-primary-recommendations',
                                            ),
                                            items: featured,
                                            canShuffle: heroCards.length > 4,
                                            onShuffle: () => setState(
                                              () => _featuredRevision++,
                                            ),
                                            onDetails: (card) => card.onTap(),
                                          )
                                        else if (!isSdkStyleFeed &&
                                            visibleHeroCards.isNotEmpty)
                                          ModernFeatureCarousel(
                                            key: ValueKey(
                                              controller.feed ==
                                                      HomeFeed.recommended
                                                  ? 'home-primary-recommendations'
                                                  : 'anime-feature-${controller.feed.name}',
                                            ),
                                            entries: [
                                              for (final item
                                                  in visibleHeroCards)
                                                ModernFeatureEntry(
                                                  id: item.id,
                                                  title: item.title,
                                                  subtitle: item.subtitle,
                                                  cover: item.cover,
                                                  imageType: 'bg',
                                                  onTap: item.onTap,
                                                ),
                                            ],
                                          )
                                        else if (!isSdkStyleFeed &&
                                            (anime?.loading == true ||
                                                controller.loading ||
                                                (!controller
                                                        .feed
                                                        .isGeneralCategory &&
                                                    controller.catalogLoading)))
                                          _LoadingFeature(
                                            bento:
                                                controller.feed ==
                                                    HomeFeed.recommended &&
                                                !compact,
                                          )
                                        else if (items.isEmpty &&
                                            !isSdkStyleFeed)
                                          _EmptyFeed(
                                            message:
                                                controller.error ??
                                                (anime == null
                                                    ? '当前平台尚不支持 Lumina'
                                                    : 'Lumina 暂无可展示的内容'),
                                            retry: retryFeed,
                                          ),
                                        if (sourceCards.isEmpty &&
                                            controller.error != null &&
                                            items.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: PlayraSpace.md,
                                            ),
                                            child: _EmptyFeed(
                                              message: controller.error!,
                                              retry: retryFeed,
                                            ),
                                          ),
                                        // 继续观看是跨分类的个人历史，只在聚合位展示；
                                        // 风格频道只允许出现本分类数据。
                                        if (controller.feed.isGeneralCategory)
                                          recentSection!,
                                        if (controller.feed.isWhiskletStyle &&
                                            whisklet != null)
                                          _WhiskletStyleGrid(
                                            style: controller.feed.style!,
                                            source: whisklet!,
                                            controller: controller,
                                            onTap: (work) =>
                                                _noticeWhisklet(context, work),
                                          ),
                                        if (controller.feed.isHongguoStyle &&
                                            hongguo != null &&
                                            onHongguoDetails != null)
                                          _HongguoStyleGrid(
                                            source: hongguo!,
                                            controller: controller,
                                            onTap: (item) =>
                                                _noticeHongguo(context, item),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Lumina 榜单同样是跨分类内容，风格频道不展示。
                                  if (!isSdkStyleFeed &&
                                      ranking != null &&
                                      onRankDetails != null)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          horizontalPadding,
                                          smallScreen
                                              ? PlayraSpace.lg
                                              : PlayraSpace.xl,
                                          horizontalPadding,
                                          0,
                                        ),
                                        child: SdkRankSection(
                                          controller: ranking!,
                                          onDetails: onRankDetails!,
                                        ),
                                      ),
                                    ),
                                  SliverList.list(
                                    children: [
                                      if (controller.feed == HomeFeed.popular)
                                        ?_whiskletRail(
                                          context,
                                          'whisklet-hot',
                                          '热播 · 第二源',
                                          works: whisklet?.hot ?? const [],
                                          loading: whisklet?.hotLoading == true,
                                          failed: whisklet?.hotError != null,
                                          emptyMessage: '第二内容源热播暂不可用',
                                          onRetry: () =>
                                              whisklet?.loadHot(refresh: true),
                                        ),
                                      if (controller.feed ==
                                              HomeFeed.recommended &&
                                          whisklet != null)
                                        for (final shelf in whisklet!.shelves)
                                          ?_whiskletRail(
                                            context,
                                            'whisklet-${shelf.title}',
                                            shelf.title,
                                            works: shelf.items,
                                            loading: false,
                                            failed: false,
                                            emptyMessage: '暂无片目',
                                            typeId: shelf.typeId,
                                          ),
                                      if (controller.feed == HomeFeed.anime)
                                        ?_whiskletRail(
                                          context,
                                          'whisklet-anime',
                                          '动漫 · 第二源',
                                          works:
                                              whisklet?.of(HomeStyle.anime) ??
                                              const [],
                                          loading:
                                              whisklet?.loading(
                                                HomeStyle.anime,
                                              ) ==
                                              true,
                                          failed:
                                              whisklet?.failed(
                                                HomeStyle.anime,
                                              ) ==
                                              true,
                                          emptyMessage: '第二源暂无动漫片目',
                                          onRetry: () =>
                                              whisklet?.retry(HomeStyle.anime),
                                        ),
                                      if (controller.feed.isGeneralCategory)
                                        for (final channel in sourceChannels)
                                          if (_channelCards(channel).isNotEmpty ||
                                              anime?.loadingIn(
                                                    _channelBucket(channel),
                                                  ) ==
                                                  true)
                                            _ChannelRail(
                                            id: channel.id,
                                            title: _channelTitle(channel),
                                            items: _channelCards(
                                              channel,
                                            ).take(20).toList(),
                                            controller: controller,
                                            onDetails: (card) => card.onTap(),
                                            onMore: () =>
                                                _openChannel(context, channel),
                                            loading:
                                                anime?.loadingIn(
                                                  _channelBucket(channel),
                                                ) ==
                                                true,
                                            failed:
                                                anime?.pageFailedIn(
                                                      _channelBucket(channel),
                                                    ) ==
                                                    true &&
                                                _sourceCards(
                                                  _channelBucket(channel),
                                                ).isEmpty,
                                            emptyMessage:
                                                '暂无${channel.title}内容',
                                          )
                                      else if (controller
                                              .catalog
                                              .hasStructuredData &&
                                          controller.feed.hasContentSource)
                                        for (final channel
                                            in controller.channels)
                                          _ChannelRail(
                                            id: channel.id,
                                            title: channel.title,
                                            items: _channelCards(
                                              channel,
                                            ).take(20).toList(),
                                            controller: controller,
                                            onDetails: (card) => card.onTap(),
                                            onMore: () =>
                                                _openChannel(context, channel),
                                          ),
                                      if (!controller.feed.isGeneralCategory &&
                                          !controller.feed.isHongguoStyle &&
                                          !controller
                                              .catalog
                                              .hasStructuredData) ...[
                                        if (items.isNotEmpty)
                                          _ChannelRail(
                                            id: 'main',
                                            title: switch (controller.feed) {
                                              HomeFeed.recommended => '今日推荐',
                                              HomeFeed.popular => '人气热播',
                                              HomeFeed.season => '新番放送',
                                              HomeFeed.japanese => '日漫热播',
                                              HomeFeed.chinese => '国漫热播',
                                              _ => '${controller.feed.label}精选',
                                            },
                                            items: items,
                                            loading: controller.loading,
                                            controller: controller,
                                            onDetails: (card) => card.onTap(),
                                            onMore: () => _openOrBrowse(
                                              context,
                                              HomeChannel(
                                                'main',
                                                '${controller.feed.label}精选',
                                                controller.items,
                                              ),
                                              switch (controller.feed) {
                                                HomeFeed.chinese => '中国',
                                                HomeFeed.japanese => '日本',
                                                _ => '',
                                              },
                                            ),
                                          ),
                                        if (controller
                                            .feed
                                            .hasContentSource) ...[
                                          _ChannelRail(
                                            id: 'chinese',
                                            onMore: () => _openOrBrowse(
                                              context,
                                              HomeChannel(
                                                'chinese',
                                                '国漫剧场',
                                                controller.catalog.chinese,
                                              ),
                                              '中国',
                                            ),
                                            title: '国漫剧场',
                                            items: _channelCards(
                                              HomeChannel(
                                                'chinese',
                                                '国漫剧场',
                                                controller.catalog.chinese,
                                              ),
                                            ).take(20).toList(),
                                            controller: controller,
                                            onDetails: (card) => card.onTap(),
                                            loading: controller.catalogLoading,
                                            failed:
                                                controller.catalog.failed
                                                    .contains('chinese') &&
                                                _sourceCards('chinese').isEmpty,
                                          ),
                                          _ChannelRail(
                                            id: 'japanese',
                                            onMore: () => _openOrBrowse(
                                              context,
                                              HomeChannel(
                                                'japanese',
                                                '日漫精选',
                                                controller.catalog.japanese,
                                              ),
                                              '日本',
                                            ),
                                            title: '日漫精选',
                                            items: _channelCards(
                                              HomeChannel(
                                                'japanese',
                                                '日漫精选',
                                                controller.catalog.japanese,
                                              ),
                                            ).take(20).toList(),
                                            controller: controller,
                                            onDetails: (card) => card.onTap(),
                                            loading: controller.catalogLoading,
                                            failed:
                                                controller.catalog.failed
                                                    .contains('japanese') &&
                                                _sourceCards(
                                                  'japanese',
                                                ).isEmpty,
                                          ),
                                        ],
                                      ],
                                      if (controller.feed.hasContentSource)
                                        SizedBox(
                                          height:
                                              24 +
                                              MediaQuery.paddingOf(
                                                context,
                                              ).bottom,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.controller,
    required this.onSearch,
    required this.onCalendar,
    required this.compact,
  });
  final ModernHomeController controller;
  final VoidCallback onSearch, onCalendar;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: const _HomeBrand(),
            ),
            const SizedBox(width: PlayraSpace.md),
            Expanded(child: _SearchEntry(onSearch: onSearch)),
            const SizedBox(width: PlayraSpace.sm),
            _HeaderIconButton(
              key: const ValueKey('home-calendar'),
              icon: LucideIcons.calendarDays,
              tooltip: '排期表',
              onTap: onCalendar,
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 8),
        _FeedTabs(controller: controller, compact: compact),
      ],
    );
  }
}

class _HomeBrand extends StatelessWidget {
  const _HomeBrand();

  @override
  Widget build(BuildContext context) => Text(
    'Playra',
    maxLines: 1,
    softWrap: false,
    style: TextStyle(
      fontSize: PlayraType.title,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.1,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PlayraIconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(
      icon,
      size: PlayraLayout.icon,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _FeedTabs extends StatefulWidget {
  const _FeedTabs({required this.controller, required this.compact});
  final ModernHomeController controller;
  final bool compact;

  @override
  State<_FeedTabs> createState() => _FeedTabsState();
}

class _FeedTabsState extends State<_FeedTabs> {
  // 顺序即展示顺序：两个聚合位在前，其后是上游 7 个风格频道与红果短剧。
  // 动漫由 Lumina 出片（子分类仍走动漫内部桶），其余风格由第二源出片；
  // 红果短剧由红果源独立出片。
  static const feeds = [
    HomeFeed.recommended,
    HomeFeed.popular,
    HomeFeed.movies,
    HomeFeed.television,
    HomeFeed.anime,
    HomeFeed.variety,
    HomeFeed.shortDrama,
    HomeFeed.aiComic,
    HomeFeed.live,
    HomeFeed.hongguo,
  ];
  final Map<HomeFeed, GlobalKey> _keys = {
    for (final feed in feeds) feed: GlobalKey(),
  };
  HomeFeed? _lastRevealed;

  @override
  void initState() {
    super.initState();
    _lastRevealed = widget.controller.feed;
    widget.controller.addListener(_revealSelected);
  }

  @override
  void didUpdateWidget(covariant _FeedTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_revealSelected);
      widget.controller.addListener(_revealSelected);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_revealSelected);
    super.dispose();
  }

  // 只在选中项变化时回滚视野；加载状态刷新不打断用户的手动横滑。
  void _revealSelected() {
    final feed = widget.controller.feed;
    if (feed == _lastRevealed) return;
    _lastRevealed = feed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _keys[feed]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.controller.feed;
    final height = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(16) * 1.4,
    );
    return SingleChildScrollView(
      key: const ValueKey('home-feed-selector'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final feed in feeds) ...[
            Semantics(
              key: ValueKey('home-feed-${feed.name}'),
              selected: feed == selected,
              child: Material(
                key: _keys[feed],
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(PlayraTokens.radiusSm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(PlayraTokens.radiusSm),
                  // 分类切换只用文字颜色/字重表达选中，不显示悬停、焦点或按压底色。
                  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  onTap: () => widget.controller.selectFeed(feed),
                  child: SizedBox(
                    height: height,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact
                            ? PlayraSpace.xs
                            : PlayraSpace.compact,
                      ),
                      child: Center(
                        child: Text(
                        feed.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: feed == selected ? 16 : 15,
                          fontWeight: feed == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: feed == selected
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (feed != feeds.last) SizedBox(width: widget.compact ? 6 : 8),
          ],
        ],
      ),
    );
  }
}

/// 风格频道正文：三列海报网格 + 触底/按钮续页。
///
/// 这些频道由第二内容源独立出片，不参与 Lumina 动漫桶的排序；动漫频道
/// 仍以 Lumina 为主，第二源只出一节「动漫 · 第二源」栏。
class _WhiskletStyleGrid extends StatelessWidget {
  const _WhiskletStyleGrid({
    required this.style,
    required this.source,
    required this.controller,
    required this.onTap,
  });
  final HomeStyle style;
  final WhiskletHomeController source;
  final ModernHomeController controller;
  final ValueChanged<WhiskletWork> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final works = source.of(style);
    final loading = source.loading(style);
    final failed = source.failed(style);
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    final horizontalPadding = compact ? 16.0 : 20.0;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = MediaQuery.sizeOf(context).width >= 840 ? 5 : 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? PlayraSpace.md : PlayraSpace.lg,
        horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ModernSectionMark(kind: ModernSectionKind.curated),
              const SizedBox(width: PlayraSpace.sm),
              Expanded(
                child: Text(
                  style.label,
                  style: const TextStyle(
                    fontSize: PlayraType.section,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (works.isNotEmpty)
                Text(
                  '${works.length}${source.hasMore(style) ? '+' : ''} 部',
                  style: TextStyle(
                    fontSize: PlayraType.small,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: works.isEmpty && loading
                ? SkeletonPosters(
                    key: ValueKey('whisklet-skeleton-${style.name}'),
                    horizontal: false,
                    count: columns * 3,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.5,
                    ),
                  )
                : works.isEmpty
                ? Container(
                    key: ValueKey('whisklet-empty-${style.name}'),
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: PlayraButton.ghost(
                      key: ValueKey('whisklet-retry-${style.name}'),
                      onPressed: () => source.retry(style),
                      child: Text(
                        failed ? '这个频道加载失败，点击重试' : '暂无${style.label}内容',
                      ),
                    ),
                  )
                : Column(
                    key: ValueKey('whisklet-content-${style.name}'),
                    children: [
                      GridView.builder(
                        key: ValueKey('whisklet-grid-${style.name}'),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.5,
                        ),
                        itemCount:
                            works.length +
                            (loading
                                ? ((columns - (works.length % columns)) %
                                          columns) +
                                      columns
                                : 0),
                        itemBuilder: (context, index) => index >= works.length
                            ? ContentSkeleton(
                                animate: !isFlutterTestBinding,
                                child: const SkeletonPosterCard(),
                              )
                            : _PosterCard(
                                item: _card(works[index]),
                                controller: controller,
                                onTap: () => onTap(works[index]),
                              ),
                      ),
                      if (failed)
                        Center(
                          child: PlayraButton.ghost(
                            key: ValueKey('whisklet-more-${style.name}'),
                            onPressed: () => source.retry(style),
                            child: const Text('加载失败，点击重试'),
                          ),
                        ),
                      SizedBox(height: 8 * scale),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  HomeAnimeCard _card(WhiskletWork work) => HomeAnimeCard(
    id: work.identity,
    title: work.title,
    cover: work.cover,
    status: work.remarks,
    subtitle: [
      work.year,
      work.area,
    ].where((value) => value.isNotEmpty).join(' · '),
    year: int.tryParse(work.year),
    onTap: () => onTap(work),
  );
}

/// 红果短剧频道正文：热榜在前、推荐流续接的三列海报网格 + 触底续页。
class _HongguoStyleGrid extends StatelessWidget {
  const _HongguoStyleGrid({
    required this.source,
    required this.controller,
    required this.onTap,
  });
  final HongguoHomeController source;
  final ModernHomeController controller;
  final ValueChanged<HongguoSeriesSummary> onTap;

  List<HomeAnimeCard> _cards(List<HongguoSeriesSummary> items) => [
    for (final item in items)
      HomeAnimeCard(
        id: 'hongguo:${item.id}',
        title: item.title,
        cover: item.coverUrl,
        status: item.episodeCount > 0 ? '共${item.episodeCount}集' : '',
        subtitle: '红果短剧',
        group: ContentGroup.series,
        onTap: () => onTap(item),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = source.feed;
    final loading = source.loading;
    final failed = source.failed;
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    final horizontalPadding = compact ? 16.0 : 20.0;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = MediaQuery.sizeOf(context).width >= 840 ? 5 : 3;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? PlayraSpace.md : PlayraSpace.lg,
        horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ModernSectionMark(kind: ModernSectionKind.curated),
              const SizedBox(width: PlayraSpace.sm),
              Expanded(
                child: Text(
                  '红果热榜',
                  style: const TextStyle(
                    fontSize: PlayraType.section,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Text(
                  '${items.length}${source.discoverHasMore ? '+' : ''} 部',
                  style: TextStyle(
                    fontSize: PlayraType.small,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: items.isEmpty && loading
                ? SkeletonPosters(
                    key: const ValueKey('hongguo-skeleton'),
                    horizontal: false,
                    count: columns * 3,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.5,
                    ),
                  )
                : items.isEmpty
                ? Container(
                    key: const ValueKey('hongguo-empty'),
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: PlayraButton.ghost(
                      key: const ValueKey('hongguo-retry'),
                      onPressed: source.retry,
                      child: Text(
                        failed ? '红果频道加载失败，点击重试' : '暂无红果短剧内容',
                      ),
                    ),
                  )
                : Column(
                    key: const ValueKey('hongguo-content'),
                    children: [
                      GridView.builder(
                        key: const ValueKey('hongguo-grid'),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.5,
                        ),
                        itemCount:
                            items.length +
                            (source.discoverLoading
                                ? ((columns - (items.length % columns)) %
                                          columns) +
                                      columns
                                : 0),
                        itemBuilder: (context, index) => index >= items.length
                            ? ContentSkeleton(
                                animate: !isFlutterTestBinding,
                                child: const SkeletonPosterCard(),
                              )
                            : _PosterCard(
                                item: _cards([items[index]]).single,
                                controller: controller,
                                onTap: () => onTap(items[index]),
                              ),
                      ),
                      if (failed)
                        Center(
                          child: PlayraButton.ghost(
                            key: const ValueKey('hongguo-more'),
                            onPressed: source.retry,
                            child: const Text('加载失败，点击重试'),
                          ),
                        ),
                      SizedBox(height: 8 * scale),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRail extends StatelessWidget {
  const _ChannelRail({
    required this.id,
    required this.title,
    required this.items,
    required this.controller,
    required this.onDetails,
    required this.onMore,
    this.loading = false,
    this.failed = false,
    this.emptyMessage = '暂时没有番剧',
    this.onRetry,
  });
  final String id, title;
  final List<HomeAnimeCard> items;
  final ModernHomeController controller;
  final ValueChanged<HomeAnimeCard> onDetails;
  final VoidCallback onMore;
  final bool loading, failed;
  final String emptyMessage;

  /// 聚合/副源栏目的重试入口；为空时沿用主目录重试。
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    final horizontalPadding = compact ? 16.0 : 20.0;
    return Padding(
      padding: EdgeInsets.only(top: compact ? PlayraSpace.lg : PlayraSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: PlayraSpace.md,
            ),
            child: Row(
              children: [
                const ModernSectionMark(kind: ModernSectionKind.curated),
                const SizedBox(width: PlayraSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: PlayraType.section,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (failed)
                  PlayraButton.ghost(
                    onPressed: onRetry ?? controller.refreshCatalog,
                    child: const Text('重试'),
                  )
                else if (items.isNotEmpty)
                  PlayraButton.ghost(
                    key: ValueKey('home-more-$id'),
                    onPressed: onMore,

                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '查看更多',
                          style: TextStyle(fontSize: PlayraType.small),
                        ),
                        SizedBox(width: PlayraSpace.xs),
                        Icon(LucideIcons.chevronRight, size: 14),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          if (items.isEmpty && loading)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: const SkeletonPosters(),
            )
          else if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  failed ? '这个栏目暂时未加载，点击重试' : emptyMessage,
                  style: TextStyle(
                    fontSize: PlayraType.caption,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, bounds) {
                final width =
                    ((bounds.maxWidth - 2 * horizontalPadding) / 3.1 - 8).clamp(
                      104.0,
                      144.0,
                    );
                return SizedBox(
                  height: width * 1.42 + 48 * scale,
                  child: ScrollConfiguration(
                    behavior: const _HomeScrollBehavior(),
                    child: ListView.separated(
                      key: PageStorageKey('home-channel-$id'),
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: PlayraSpace.md),
                      itemBuilder: (_, index) => SizedBox(
                        width: width,
                        child: _PosterCard(
                          item: items[index],
                          controller: controller,
                          onTap: () => onDetails(items[index]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 导航至统一的专门分类列表页面（替代原有的临时弹窗），提供多端响应式网格与沉浸体验。
Future<void> _showChannelItems(
  BuildContext context,
  HomeChannel channel,
  ModernHomeController controller,
  ValueChanged<BangumiItem> onDetails, {
  List<HomeAnimeCard> Function()? readCards,
  Listenable? sourceUpdates,
  Future<void> Function()? sourceLoadMore,
  bool Function()? sourceHasMore,
  bool Function()? sourceLoading,
  bool Function()? sourceFailed,
  Future<void> Function()? onRefresh,
  VoidCallback? onSearch,
  List<HomeAnimeCard>? initialCards,
  String? emptyMessage,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ModernCategoryListPage(
      channelTitle: channel.title,
      channelId: channel.id,
      controller: controller,
      onDetails: onDetails,
      readCards: readCards,
      sourceUpdates: sourceUpdates,
      sourceLoadMore: sourceLoadMore,
      sourceHasMore: sourceHasMore,
      sourceLoading: sourceLoading,
      sourceFailed: sourceFailed,
      onRefresh: onRefresh,
      onSearch: onSearch,
      initialCards: initialCards,
      emptyMessage: emptyMessage,
    ),
  ),
);

class _HomeScrollBehavior extends MaterialScrollBehavior {
  const _HomeScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = context.playraTokens;
    return Material(
      key: const ValueKey('home-search'),
      color: tokens.surfaceRaised,
      borderRadius: BorderRadius.circular(PlayraTokens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSearch,
        borderRadius: BorderRadius.circular(PlayraTokens.radiusLg),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayraTokens.radiusLg),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '搜索动漫或关键词',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.foregroundMuted,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                LucideIcons.search,
                size: PlayraLayout.compactIcon,
                color: tokens.foregroundMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationBento extends StatelessWidget {
  const _RecommendationBento({
    super.key,
    required this.items,
    required this.canShuffle,
    required this.onShuffle,
    required this.onDetails,
  });
  final List<HomeAnimeCard?> items;
  final bool canShuffle;
  final VoidCallback onShuffle;
  final ValueChanged<HomeAnimeCard> onDetails;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = bounds.maxWidth >= 960 && scale <= 1.3
          ? 4
          : bounds.maxWidth >= 480 * scale + 10
          ? 2
          : 1;
      final rowHeight = columns == 1 || scale > 1.3
          ? 140.0 + 64 * (scale - 1).clamp(0, 3)
          : ((bounds.maxWidth - 10 * (columns - 1)) / columns * .75).clamp(
              124.0,
              152.0,
            );
      final rows = (items.length + columns - 1) ~/ columns;
      return Column(
        children: [
          SizedBox(
            height: rowHeight * rows + 10 * (rows - 1),
            child: Column(
              children: [
                for (var row = 0; row < rows; row++) ...[
                  if (row > 0) const SizedBox(height: 10),
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: 10),
                          Expanded(
                            child:
                                row * columns + column < items.length &&
                                    items[row * columns + column] != null
                                ? _BentoCard(
                                    item: items[row * columns + column]!,
                                    onTap: () => onDetails(
                                      items[row * columns + column]!,
                                    ),
                                  )
                                : const _BentoPlaceholder(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          PlayraButton.ghostIcon(
            key: const ValueKey('home-shuffle-featured'),
            onPressed: canShuffle ? onShuffle : null,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text(
              '换一批',
              style: TextStyle(fontSize: PlayraType.caption),
            ),
          ),
        ],
      );
    },
  );
}

class _BentoPlaceholder extends StatelessWidget {
  const _BentoPlaceholder();
  @override
  Widget build(BuildContext context) => Semantics(
    label: '推荐内容加载中',
    child: ExcludeSemantics(
      child: ContentSkeleton(
        animate: !isFlutterTestBinding,
        child: LayoutBuilder(
          builder: (context, bounds) => Container(
            padding: const EdgeInsets.all(PlayraSpace.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(PlayraRadius.card),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Bone(
                  width: bounds.maxWidth * .34,
                  height: bounds.maxHeight - 16,
                  uniRadius: PlayraRadius.thumbnail,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: PlayraSpace.compact),
                      Bone(height: 12, uniRadius: 3),
                      SizedBox(height: PlayraSpace.sm),
                      Bone(height: 12, uniRadius: 3),
                      Spacer(),
                      FractionallySizedBox(
                        widthFactor: .55,
                        alignment: Alignment.centerLeft,
                        child: Bone(height: 10, uniRadius: 3),
                      ),
                      SizedBox(height: PlayraSpace.sm),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _BentoCard extends StatefulWidget {
  const _BentoCard({required this.item, required this.onTap});
  final HomeAnimeCard item;
  final VoidCallback onTap;
  @override
  State<_BentoCard> createState() => _BentoCardState();
}

class _BentoCardState extends State<_BentoCard> {
  bool _hovered = false;

  Widget _cover(double width, double height) => ClipRect(
    child: AnimatedScale(
      scale: _hovered ? 1.04 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: NetworkImgLayer(
        src: widget.item.cover,
        fallbackTitle: widget.item.title,
        width: width,
        height: height,
        type: 'bg',
        borderRadius: BorderRadius.zero,
      ),
    ),
  );

  Widget _rating() {
    final tokens = PlayraTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.star, size: 12, color: tokens.rankGold),
        const SizedBox(width: PlayraSpace.xs),
        Flexible(
          child: Text(
            widget.item.ratingScore > 0
                ? widget.item.ratingScore.toStringAsFixed(1)
                : '暂无评分',
            semanticsLabel: widget.item.ratingScore > 0
                ? '评分 ${widget.item.ratingScore.toStringAsFixed(1)}'
                : '暂无评分',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: PlayraType.small,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: tokens.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      button: true,
      label: '查看推荐 ${widget.item.title}',
      child: PlayraCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: LayoutBuilder(
              builder: (context, bounds) {
                // 横向推荐卡用竖版缩略图，标题不再覆盖封面，也不将海报裁成横幅。
                final coverWidth = math.min(
                  bounds.maxWidth * .40,
                  bounds.maxHeight * .68,
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: SvgPicture.asset(
                          'assets/images/modern-recommendation-lines.svg',
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(PlayraSpace.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: coverWidth - 8,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                PlayraRadius.thumbnail,
                              ),
                              child: _cover(
                                coverWidth - 8,
                                bounds.maxHeight - 16,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    widget.item.title,
                                    maxLines: scale > 1.3 ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.onSurface,
                                      fontSize: PlayraType.caption,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _rating(),
                                      const SizedBox(height: PlayraSpace.sm),
                                      Text(
                                        '查看作品 ›',
                                        style: TextStyle(
                                          fontSize: PlayraType.caption,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });
  final String title, subtitle, actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      const ModernSectionMark(kind: ModernSectionKind.resume),
      const SizedBox(width: PlayraSpace.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: PlayraType.section,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (subtitle.isNotEmpty) const SizedBox(height: PlayraSpace.xs),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: PlayraType.small,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      PlayraButton.ghost(
        onPressed: onAction,

        trailing: const Icon(LucideIcons.chevronRight, size: 14),
        child: Text(
          actionLabel,
          style: const TextStyle(fontSize: PlayraType.caption),
        ),
      ),
    ],
  );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.controller,
    required this.onHistory,
    required this.onResume,
  });
  final ModernHomeController controller;
  final VoidCallback onHistory;
  final ValueChanged<History> onResume;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      controller.historyUpdates,
      SdkLibraryStore.shared,
    ]),
    builder: (context, _) {
      final recent = groupPersonalHistory(
        controller.recent,
        SdkLibraryStore.shared.histories,
      ).expand((group) => group.entries).take(10).toList();
      if (recent.isEmpty) return const SizedBox.shrink();
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          _SectionHeading(
            title: '继续观看',
            subtitle: '',
            actionLabel: '全部',
            onAction: onHistory,
          ),
          const SizedBox(height: PlayraSpace.sm),
          LayoutBuilder(
            builder: (context, bounds) => SizedBox(
              height: 94 + 32 * (scale - 1).clamp(0, 3),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: PlayraSpace.md),
                itemBuilder: (_, index) => recent[index].sdk != null
                    ? SizedBox(
                        width: math.min(
                          bounds.maxWidth - (recent.length > 1 ? 20 : 0),
                          350,
                        ),
                        child: SdkLibraryTile(
                          record: recent[index].sdk!,
                          compact: true,
                          onOpen: () =>
                              openSdkLibraryRecord(context, recent[index].sdk!),
                        ),
                      )
                    : _ContinueCard(
                        history: recent[index].history!,
                        width: math.min(
                          bounds.maxWidth - (recent.length > 1 ? 20 : 0),
                          350,
                        ),
                        onTap: () => onResume(recent[index].history!),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.history,
    required this.width,
    required this.onTap,
  });
  final History history;
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final position =
        history.progresses[history.lastWatchEpisode]?.progress ?? Duration.zero;
    final savedPosition =
        '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}';
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label:
            '继续观看 ${homeTitle(history.bangumiItem)} 第${history.lastWatchEpisode}集，看到 $savedPosition',
        child: PlayraCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            key: ValueKey('home-resume-${history.key}'),
            borderRadius: BorderRadius.circular(PlayraRadius.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  NetworkImgLayer(
                    src: homeCover(history.bangumiItem),
                    fallbackTitle: homeTitle(history.bangumiItem),
                    width: 52,
                    height: 74,
                    type: 'bg',
                    borderRadius: BorderRadius.circular(
                      PlayraRadius.thumbnail,
                    ),
                  ),
                  const SizedBox(width: PlayraSpace.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          homeTitle(history.bangumiItem),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: PlayraType.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '第 ${history.lastWatchEpisode} 集 · $savedPosition',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: PlayraType.small,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: PlayraSpace.sm),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.play,
                      color: Theme.of(context).colorScheme.primary,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterCard extends StatefulWidget {
  const _PosterCard({
    required this.item,
    required this.controller,
    required this.onTap,
  });
  final HomeAnimeCard item;
  final ModernHomeController controller;
  final VoidCallback onTap;
  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _hovered = false;
  @override
  void initState() {
    super.initState();
    _requestSchedule();
  }

  @override
  void didUpdateWidget(covariant _PosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requestSchedule();
  }

  void _requestSchedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final metadata = widget.item.metadata;
      if (mounted && metadata != null) {
        widget.controller.ensureSchedule(metadata.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.item.metadata == null
      ? _buildCard(context)
      : ListenableBuilder(
          listenable: widget.controller.scheduleChanges(
            widget.item.metadata!.id,
          ),
          builder: (context, _) => _buildCard(context),
        );

  Widget _buildCard(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    final item = widget.item;
    final airing = item.metadata == null
        ? item.status
        : widget.controller.scheduleLabel(item.metadata!);
    return Semantics(
      label:
          '查看 ${item.title}，评分 ${item.ratingScore > 0 ? item.ratingScore.toStringAsFixed(1) : '暂无'}，$airing',
      button: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: PlayraCard(
        kind: PlayraCardKind.poster,
        padding: EdgeInsets.zero,
        child: InkWell(
          key: ValueKey('home-poster-${item.id}'),
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(PlayraRadius.poster),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, bounds) => ClipRRect(
                  borderRadius: BorderRadius.circular(PlayraRadius.poster),
                  child: SizedBox(
                    width: bounds.maxWidth,
                    height: bounds.maxWidth * 1.42,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MouseRegion(
                          onEnter: (_) => setState(() => _hovered = true),
                          onExit: (_) => setState(() => _hovered = false),
                          child: AnimatedScale(
                            key: ValueKey('home-cover-scale-${item.id}'),
                            scale: _hovered ? 1.04 : 1,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: NetworkImgLayer(
                              src: item.cover,
                              fallbackTitle: item.title,
                              width: bounds.maxWidth,
                              height: bounds.maxWidth * 1.42,
                              type: 'bg',
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: bounds.maxWidth * 1.42 * .36,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: ValueKey('home-cover-shade-${item.id}'),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Color(0x50000000),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (item.ratingScore > 0)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              key: ValueKey('home-rating-${item.id}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: PlayraSpace.compact,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.rankGold,
                                borderRadius: const BorderRadius.only(
                                  bottomRight: Radius.circular(
                                    PlayraRadius.thumbnail,
                                  ),
                                ),
                              ),
                              child: Text(
                                item.ratingScore.toStringAsFixed(1),
                                semanticsLabel:
                                    '评分 ${item.ratingScore.toStringAsFixed(1)}',
                                style: TextStyle(
                                  color: tokens.warningContainer,
                                  fontSize: PlayraType.small,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          left: 6,
                          child: IgnorePointer(
                            child: Text(
                              airing,
                              key: ValueKey('home-airing-${item.id}'),
                              maxLines: 2,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: PlayraType.micro,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PlayraSpace.sm),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: PlayraType.label,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PlayraSpace.xl),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PlayraRadius.hero),
        border: Border.all(color: tokens.borderSubtle),
      ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/modern-home-empty-feed.svg',
          width: 112,
          height: 81,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: PlayraType.caption,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        PlayraButton.outline(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );
  }
}

class _LoadingFeature extends StatelessWidget {
  const _LoadingFeature({this.bento = false});
  final bool bento;
  @override
  Widget build(BuildContext context) => SkeletonFeature(
    bento: bento,
    height: ModernFeatureCarousel.heightFor(context),
  );
}
