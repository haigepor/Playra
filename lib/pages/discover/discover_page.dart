import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/home_banner.dart';
import 'package:kazumi/pages/discover/home_header.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/home_ranking_panel.dart';
import 'package:kazumi/pages/discover/home_sections.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/services/storage/storage.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, this.onSelectTab});

  /// Lets the home header switch the shell tab (e.g. calendar).
  final ValueChanged<int>? onSelectTab;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Future<List<MediaCategory>>? _categoriesFuture;

  MediaSource? get _source => mediaSources.primary;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kHomeChannels.length, vsync: this);
    _categoriesFuture = _source?.loadCategories();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<MediaCategory>> _loadCategories() {
    final source = _source;
    if (source == null) return Future.value(const <MediaCategory>[]);
    return _categoriesFuture ??= source.loadCategories();
  }

  void _refreshCategories() {
    _source?.invalidateCache();
    _categoriesFuture = _source?.loadCategories();
  }

  void _openBrowse({
    required String categoryId,
    required String title,
    String initialSort = '',
  }) {
    final source = _source;
    if (source == null) return;
    context.pushNamed(
      '/browse',
      arguments: BrowseArgs(
        sourceId: source.id,
        categoryId: categoryId,
        title: title,
        initialSort: initialSort,
      ),
    );
  }

  void _openDetail(MediaItem item) {
    context.pushNamed('/detail', arguments: item.key);
  }

  Future<void> _openBanner(MediaBanner banner) async {
    final target = banner.target;
    if (target != null) {
      context.pushNamed('/detail', arguments: target);
      return;
    }
    final uri = banner.externalUri;
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
      if (!opened && mounted) _showPlaceholder('无法打开外部链接');
    } catch (_) {
      if (mounted) _showPlaceholder('无法打开外部链接');
    }
  }

  void _openHistory() => showPlaybackHistory(context);

  void _showPlaceholder(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    return PlayraBackdrop(
      child: Column(
        children: [
          HomeTopBar(
            layout: layout,
            tabController: _tabController,
            channels: kHomeChannels,
            sourceLabel: _source?.displayName ?? '',
            onSearch: () => context.pushNamed('/search'),
            onCalendar: () => widget.onSelectTab?.call(1),
            onHistory: _openHistory,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final channel in kHomeChannels)
                  _ChannelFeedView(
                    key: ValueKey('discover-channel-${channel.id.name}'),
                    channel: channel,
                    layout: layout,
                    loadCategories: _loadCategories,
                    onInvalidateCategories: _refreshCategories,
                    onOpenDetail: _openDetail,
                    onOpenBanner: _openBanner,
                    onOpenBrowse: _openBrowse,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelSectionModel {
  const _ChannelSectionModel({
    required this.section,
    required this.useGrid,
    required this.browseCategoryId,
    required this.browseTitle,
    this.browseSort = '',
    this.maxItems,
    this.showScore = false,
  });

  final MediaSection section;
  final bool useGrid;
  final String browseCategoryId;
  final String browseTitle;
  final String browseSort;
  final int? maxItems;
  final bool showScore;
}

class _ChannelPageData {
  const _ChannelPageData({
    this.banners = const <MediaBanner>[],
    this.showResumeRail = false,
    this.rankingSection,
    this.sections = const <_ChannelSectionModel>[],
  });

  final List<MediaBanner> banners;
  final bool showResumeRail;
  final MediaSection? rankingSection;
  final List<_ChannelSectionModel> sections;

  bool get isEmpty =>
      banners.isEmpty && sections.every((entry) => entry.section.items.isEmpty);
}

typedef _BrowseLauncher =
    void Function({
      required String categoryId,
      required String title,
      String initialSort,
    });

class _ChannelFeedView extends StatefulWidget {
  const _ChannelFeedView({
    super.key,
    required this.channel,
    required this.layout,
    required this.loadCategories,
    required this.onInvalidateCategories,
    required this.onOpenDetail,
    required this.onOpenBanner,
    required this.onOpenBrowse,
  });

  final HomeChannel channel;
  final HomeLayoutMetrics layout;
  final Future<List<MediaCategory>> Function() loadCategories;
  final VoidCallback onInvalidateCategories;
  final ValueChanged<MediaItem> onOpenDetail;
  final ValueChanged<MediaBanner> onOpenBanner;
  final _BrowseLauncher onOpenBrowse;

  @override
  State<_ChannelFeedView> createState() => _ChannelFeedViewState();
}

class _ChannelFeedViewState extends State<_ChannelFeedView>
    with AutomaticKeepAliveClientMixin {
  static const _fallbackGuomanId = '319730681499283456';
  static const _fallbackRimanId = '319730676680028160';
  static const _fallbackOumeiId = '319730683562881024';
  static const _fallbackDramaId = '319730686415007744';
  static const _fallbackMovieId = '348338001690718208';
  static const _fallbackVarietyId = '364399242884866048';

  Future<_ChannelPageData>? _dataFuture;
  Object? _error;

  MediaSource? get _source => mediaSources.primary;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final source = _source;
    if (source == null) {
      setState(() => _error = '尚未注册任何内容源');
      return;
    }
    setState(() {
      _error = null;
      _dataFuture = _fetchChannel(source);
    });
  }

  Future<void> _refresh() async {
    widget.onInvalidateCategories();
    _load();
    try {
      await _dataFuture;
    } catch (_) {}
  }

  Future<List<MediaCategory>> _safeCategories() async {
    try {
      return await widget.loadCategories();
    } catch (_) {
      return const <MediaCategory>[];
    }
  }

  String _findCategoryId(
    MediaSource source,
    List<MediaCategory> categories,
    List<String> keywords,
    String clicliFallback,
  ) {
    for (final keyword in keywords) {
      for (final category in categories) {
        if (category.name.contains(keyword)) return category.id;
      }
    }
    if (source.id == 'clicli') return clicliFallback;
    return '';
  }

  Future<_ChannelPageData> _fetchChannel(MediaSource source) async {
    switch (widget.channel.id) {
      case HomeChannelId.recommend:
        return _fetchRecommend(source);
      case HomeChannelId.hot:
        return _fetchHot(source);
      case HomeChannelId.anime:
        return _fetchAnime(source);
      case HomeChannelId.drama:
        return _fetchStandardCategory(
          source,
          keywords: const ['影视', '电视', '剧集'],
          fallbackId: _fallbackDramaId,
          channelTitle: '电视剧',
          hotTitle: '热门剧集',
          updateTitle: '最新更新',
          pickTitle: '精选剧集',
          showBanners: true,
        );
      case HomeChannelId.movie:
        return _fetchStandardCategory(
          source,
          keywords: const ['剧场', '电影'],
          fallbackId: _fallbackMovieId,
          channelTitle: '电影',
          hotTitle: '热门电影',
          updateTitle: '最新上线',
          pickTitle: '精选电影',
          showBanners: true,
        );
      case HomeChannelId.variety:
        return _fetchStandardCategory(
          source,
          keywords: const ['综艺'],
          fallbackId: _fallbackVarietyId,
          channelTitle: '综艺',
          hotTitle: '热门综艺',
          updateTitle: '最新一期',
          pickTitle: '精选综艺',
          showBanners: false,
        );
    }
  }

  Future<_ChannelPageData> _fetchRecommend(MediaSource source) async {
    final feed = await source.loadChannelHome('');
    final banners = feed.banners.isNotEmpty
        ? feed.banners
        : _fallbackBanners(feed);
    final sections = <_ChannelSectionModel>[];
    for (final section in feed.sections) {
      if (section.items.isEmpty) continue;
      final isStrip =
          section.ranked || section.layout == MediaSectionLayout.strip;
      final isGrid = section.layout == MediaSectionLayout.grid;
      final browseSort = isStrip
          ? 'hot'
          : isGrid
          ? 'new'
          : '';
      sections.add(
        _ChannelSectionModel(
          section: section,
          useGrid: !isStrip,
          browseCategoryId: '',
          browseTitle: section.title.isNotEmpty ? section.title : '全部作品',
          browseSort: browseSort,
          maxItems: isStrip
              ? null
              : isGrid
              ? 6
              : 12,
        ),
      );
    }
    return _ChannelPageData(
      banners: banners,
      showResumeRail: true,
      rankingSection: _rankedSection(feed),
      sections: sections,
    );
  }

  Future<_ChannelPageData> _fetchHot(MediaSource source) async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      source
          .loadChannelHome('')
          .then<HomeFeed?>((value) => value, onError: (_) => null),
      source.browse(categoryId: '', page: 1, sort: 'hot'),
      source
          .browse(categoryId: '', page: 1, sort: 'score')
          .then<MediaPage?>(
            (value) => value,
            onError: (_) => const MediaPage(items: <MediaItem>[]),
          ),
    ]);
    final home = results[0] as HomeFeed?;
    final hotPage = results[1]! as MediaPage;
    final scorePage = results[2] as MediaPage?;

    final rankedFromHome = home == null ? null : _rankedSection(home);
    final topItems =
        (rankedFromHome != null && rankedFromHome.items.isNotEmpty)
        ? rankedFromHome.items
        : hotPage.items.take(10).toList(growable: false);

    final sections = <_ChannelSectionModel>[
      if (topItems.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'hot-top',
            title: '全站热播榜',
            layout: MediaSectionLayout.strip,
            items: topItems,
            ranked: true,
          ),
          useGrid: false,
          browseCategoryId: '',
          browseTitle: '全站热播',
          browseSort: 'hot',
        ),
      if (scorePage != null && scorePage.items.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'hot-score',
            title: '高分口碑',
            layout: MediaSectionLayout.grid,
            items: scorePage.items,
          ),
          useGrid: true,
          browseCategoryId: '',
          browseTitle: '高分口碑',
          browseSort: 'score',
          maxItems: 6,
          showScore: true,
        ),
      if (hotPage.items.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'hot-popular',
            title: '人气热播',
            layout: MediaSectionLayout.waterfall,
            items: hotPage.items,
          ),
          useGrid: true,
          browseCategoryId: '',
          browseTitle: '人气热播',
          browseSort: 'hot',
          maxItems: 12,
        ),
    ];

    return _ChannelPageData(sections: sections);
  }

  Future<_ChannelPageData> _fetchAnime(MediaSource source) async {
    final categories = await _safeCategories();
    final guomanId = _findCategoryId(
      source,
      categories,
      const ['国产动漫', '国产', '国漫'],
      _fallbackGuomanId,
    );
    final rimanId = _findCategoryId(
      source,
      categories,
      const ['日本动漫', '日本', '日漫'],
      _fallbackRimanId,
    );
    final oumeiId = _findCategoryId(
      source,
      categories,
      const ['欧美动漫', '欧美'],
      _fallbackOumeiId,
    );

    final feeds = await Future.wait<HomeFeed>(<Future<HomeFeed>>[
      source.loadChannelHome(guomanId),
      source
          .loadChannelHome(rimanId)
          .then<HomeFeed>(
            (value) => value,
            onError: (_) => const HomeFeed(),
          ),
      source
          .loadChannelHome(oumeiId)
          .then<HomeFeed>(
            (value) => value,
            onError: (_) => const HomeFeed(),
          ),
    ]);
    final guoman = feeds[0];
    final riman = feeds[1];
    final oumei = feeds[2];

    final banners = _mergeBanners(<List<MediaBanner>>[
      guoman.banners,
      riman.banners,
      oumei.banners,
    ]);

    MediaSection? pickHot(HomeFeed feed) {
      return _rankedSection(feed) ??
          (feed.sections.isNotEmpty ? feed.sections.first : null);
    }

    MediaSection? pickUpdate(HomeFeed feed) {
      for (final s in feed.sections) {
        if (s.layout == MediaSectionLayout.grid && s.items.isNotEmpty) return s;
      }
      if (feed.sections.length > 1 && feed.sections[1].items.isNotEmpty) {
        return feed.sections[1];
      }
      return null;
    }

    final guomanHot = pickHot(guoman);
    final rimanHot = pickHot(riman);
    final oumeiHot = pickHot(oumei);
    final guomanUpdate = pickUpdate(guoman);
    final rimanUpdate = pickUpdate(riman);

    final sections = <_ChannelSectionModel>[
      if (guomanHot != null && guomanHot.items.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'anime-guoman-hot',
            title: '国产动漫',
            layout: MediaSectionLayout.strip,
            items: guomanHot.items,
            ranked: true,
          ),
          useGrid: false,
          browseCategoryId: guomanId,
          browseTitle: '国产动漫',
          browseSort: 'hot',
        ),
      if (rimanHot != null && rimanHot.items.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'anime-riman-hot',
            title: '日本动漫',
            layout: MediaSectionLayout.strip,
            items: rimanHot.items,
            ranked: true,
          ),
          useGrid: false,
          browseCategoryId: rimanId,
          browseTitle: '日本动漫',
          browseSort: 'hot',
        ),
      if (oumeiHot != null && oumeiHot.items.isNotEmpty)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'anime-oumei-hot',
            title: '欧美动漫',
            layout: MediaSectionLayout.strip,
            items: oumeiHot.items,
            ranked: true,
          ),
          useGrid: false,
          browseCategoryId: oumeiId,
          browseTitle: '欧美动漫',
          browseSort: 'hot',
        ),
      if (guomanUpdate != null)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'anime-guoman-update',
            title: '国漫今日更新',
            layout: MediaSectionLayout.grid,
            items: guomanUpdate.items,
          ),
          useGrid: true,
          browseCategoryId: guomanId,
          browseTitle: '国产动漫',
          browseSort: 'new',
          maxItems: 6,
        ),
      if (rimanUpdate != null)
        _ChannelSectionModel(
          section: MediaSection(
            id: 'anime-riman-update',
            title: '日漫今日更新',
            layout: MediaSectionLayout.grid,
            items: rimanUpdate.items,
          ),
          useGrid: true,
          browseCategoryId: rimanId,
          browseTitle: '日本动漫',
          browseSort: 'new',
          maxItems: 6,
        ),
    ];

    return _ChannelPageData(
      banners: banners,
      rankingSection: guomanHot ?? rimanHot,
      sections: sections,
    );
  }

  Future<_ChannelPageData> _fetchStandardCategory(
    MediaSource source, {
    required List<String> keywords,
    required String fallbackId,
    required String channelTitle,
    required String hotTitle,
    required String updateTitle,
    required String pickTitle,
    required bool showBanners,
  }) async {
    final categories = await _safeCategories();
    final categoryId = _findCategoryId(
      source,
      categories,
      keywords,
      fallbackId,
    );
    final feed = await source.loadChannelHome(categoryId);

    final sections = <_ChannelSectionModel>[];
    for (final section in feed.sections) {
      if (section.items.isEmpty) continue;
      final isStrip =
          section.ranked || section.layout == MediaSectionLayout.strip;
      final isGrid = section.layout == MediaSectionLayout.grid;
      final displayTitle = isStrip
          ? hotTitle
          : isGrid
          ? updateTitle
          : pickTitle;
      final browseSort = isStrip
          ? 'hot'
          : isGrid
          ? 'new'
          : '';
      sections.add(
        _ChannelSectionModel(
          section: MediaSection(
            id: section.id,
            title: displayTitle,
            layout: section.layout,
            items: section.items,
            ranked: section.ranked,
            tabs: section.tabs,
            rows: section.rows,
          ),
          useGrid: !isStrip,
          browseCategoryId: categoryId,
          browseTitle: channelTitle,
          browseSort: browseSort,
          maxItems: isStrip
              ? null
              : isGrid
              ? 6
              : 12,
        ),
      );
    }

    return _ChannelPageData(
      banners: showBanners ? feed.banners : const <MediaBanner>[],
      rankingSection: showBanners ? _rankedSection(feed) : null,
      sections: sections,
    );
  }

  List<MediaBanner> _mergeBanners(List<List<MediaBanner>> groups) {
    final merged = <MediaBanner>[];
    final seen = <String>{};
    var index = 0;
    while (merged.length < 8) {
      var addedAny = false;
      for (final group in groups) {
        if (index < group.length) {
          final banner = group[index];
          final key = banner.id.isNotEmpty ? banner.id : banner.imageUrl;
          if (seen.add(key)) {
            merged.add(banner);
          }
          addedAny = true;
          if (merged.length >= 8) break;
        }
      }
      if (!addedAny) break;
      index++;
    }
    return merged;
  }

  MediaSection? _rankedSection(HomeFeed feed) {
    for (final section in feed.sections) {
      if (section.ranked && section.items.isNotEmpty) return section;
    }
    for (final section in feed.sections) {
      if (section.tabs.isNotEmpty && section.items.isNotEmpty) return section;
    }
    return null;
  }

  List<MediaBanner> _fallbackBanners(HomeFeed feed) {
    final items = <MediaItem>[];
    for (final section in feed.sections) {
      for (final item in section.items) {
        if (item.cover.isNotEmpty) items.add(item);
        if (items.length >= 8) break;
      }
      if (items.length >= 8) break;
    }
    return [
      for (var i = 0; i < items.length; i++)
        MediaBanner(
          id: 'fallback-$i',
          title: items[i].title,
          imageUrl: items[i].cover,
          target: items[i].key,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final layout = widget.layout;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_ChannelPageData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              final slivers = <Widget>[];
              if (_error != null || snapshot.hasError) {
                slivers.add(
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const MediaLoadingState(label: '正在重试')
                        : MediaErrorState(
                            message: '${widget.channel.label}内容未加载',
                            error: _error ?? snapshot.error,
                            onRetry: _load,
                          ),
                  ),
                );
              } else if (snapshot.connectionState == ConnectionState.waiting) {
                slivers.add(
                  SliverToBoxAdapter(child: _HomeLoading(layout: layout)),
                );
              } else {
                final data = snapshot.data;
                if (data == null || data.isEmpty) {
                  slivers.add(
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: PlayraPageState(
                        icon: Icons.video_library_outlined,
                        title: '${widget.channel.label}暂时没有内容',
                      ),
                    ),
                  );
                } else {
                  if (data.banners.isNotEmpty) {
                    slivers.add(
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: layout.isPhone ? 0 : layout.gutter,
                          ),
                          child: _buildHeroArea(
                            context,
                            layout,
                            data.banners,
                            data.rankingSection,
                          ),
                        ),
                      ),
                    );
                  }
                  if (data.showResumeRail) {
                    slivers.add(
                      const SliverToBoxAdapter(child: _ResumeRail()),
                    );
                  }
                  for (final entry in data.sections) {
                    if (entry.section.items.isEmpty) continue;
                    void openMore() => widget.onOpenBrowse(
                      categoryId: entry.browseCategoryId,
                      title: entry.browseTitle,
                      initialSort: entry.browseSort,
                    );
                    slivers.add(
                      SliverToBoxAdapter(
                        child: entry.useGrid
                            ? HomeSectionPosterGrid(
                                layout: layout,
                                section: entry.section,
                                onTap: widget.onOpenDetail,
                                onMore: openMore,
                                moreLabel: '查看更多',
                                maxItems: entry.maxItems,
                                showScore: entry.showScore,
                              )
                            : HomeSectionGrid(
                                layout: layout,
                                section: entry.section,
                                onTap: widget.onOpenDetail,
                                onMore: openMore,
                                moreLabel: '查看更多',
                                showScore: entry.showScore,
                              ),
                      ),
                    );
                  }
                  slivers.add(
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height:
                            MediaQuery.paddingOf(context).bottom +
                            PlayraSpace.section,
                      ),
                    ),
                  );
                }
              }
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: slivers,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroArea(
    BuildContext context,
    HomeLayoutMetrics layout,
    List<MediaBanner> banners,
    MediaSection? ranked,
  ) {
    final hero = HomeBannerCarousel(
      layout: layout,
      banners: banners,
      onTap: widget.onOpenBanner,
      canOpen: (banner) => banner.target != null || banner.externalUri != null,
    );
    if (!layout.showRankingPanel || ranked == null || ranked.items.isEmpty) {
      return hero;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = PlayraSpace.lg;
        final leftWidth = (constraints.maxWidth - gap) * .62;
        final cardHeight =
            (leftWidth * layout.heroFraction * 9 / 16).clamp(
              120.0,
              layout.heroMaxHeight,
            );
        final captionAllowance =
            MediaQuery.textScalerOf(context).scale(15) * 1.45 + 28;
        return SizedBox(
          height: cardHeight + layout.heroTopPadding + captionAllowance,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 62, child: hero),
              SizedBox(width: gap),
              Expanded(
                flex: 38,
                child: HomeRankingPanel(
                  layout: layout,
                  section: ranked,
                  onTap: widget.onOpenDetail,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading({required this.layout});

  final HomeLayoutMetrics layout;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    Widget block({double? height, double radius = 16}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: t.cardPlaceholder.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.gutter,
        PlayraSpace.lg,
        layout.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(
            height: layout.isPhone
                ? 200
                : (layout.isTabletLandscape ? 300 : 320),
          ),
          const SizedBox(height: PlayraSpace.lg),
          block(height: layout.isPhone ? 48 : 52, radius: PlayraRadius.control),
          SizedBox(height: layout.sectionGap),
          Container(
            width: 150,
            height: 18,
            decoration: BoxDecoration(
              color: t.cardPlaceholder.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: PlayraSpace.md),
          Row(
            children: [
              for (var i = 0; i < layout.sectionColumns; i++) ...[
                if (i > 0) SizedBox(width: layout.cardGap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: block(height: double.infinity),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

void showPlaybackHistory(BuildContext context) {
  Widget sheet(BuildContext sheetContext, {required bool centered}) =>
      _HistoryBottomSheet(
        centered: centered,
        onResume: (key) {
          Navigator.pop(sheetContext);
          context.pushNamed('/detail', arguments: key);
        },
      );

  if (MediaQuery.sizeOf(context).width >= 600) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: sheet(dialogContext, centered: true),
      ),
    );
  } else {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => sheet(sheetContext, centered: false),
    );
  }
}

class _HistoryBottomSheet extends StatelessWidget {
  const _HistoryBottomSheet({required this.onResume, required this.centered});

  final ValueChanged<MediaKey> onResume;
  final bool centered;

  static String _groupLabel(DateTime updatedAt, DateTime now) {
    final local = updatedAt.toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '今天';
    }
    return '更早';
  }

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final size = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 800,
        maxHeight: size.height * (centered ? .85 : .78),
      ),
      child: Material(
        key: const ValueKey('playback-history-surface'),
        color: isDark ? const Color(0xFF12141D) : t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: centered
              ? BorderRadius.circular(20)
              : const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<Box<dynamic>>(
            valueListenable: HistoryStorage.listenable(),
            builder: (context, box, _) {
              final records = HistoryStorage.getAll();
              final now = DateTime.now();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!centered) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 4,
                      width: 34,
                      decoration: BoxDecoration(
                        color: t.foregroundSubtle.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ] else
                    const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: t.border, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '播放历史',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        if (records.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: t.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${records.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: t.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (records.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                confirmClearPlaybackHistory(context),
                            style: TextButton.styleFrom(
                              foregroundColor: t.foregroundSubtle,
                              minimumSize: const Size(44, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              '清空',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        IconButton(
                          tooltip: '关闭播放历史',
                          onPressed: () => Navigator.pop(context),
                          constraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: t.foregroundSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: records.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 42),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 40,
                                  color: t.foregroundSubtle.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '还没有播放记录',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: t.foregroundSubtle),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 14),
                            itemCount: records.length,
                            itemBuilder: (context, index) {
                              final item = records[index];
                              final group = _groupLabel(item.updatedAt, now);
                              final showGroup =
                                  index == 0 ||
                                  _groupLabel(records[index - 1].updatedAt, now) !=
                                      group;
                              final hasProgress =
                                  item.durationMs > 0 && item.positionMs >= 0;
                              final episode = item.episodeTitle.isNotEmpty
                                  ? item.episodeTitle
                                  : item.episode > 0
                                  ? '第 ${item.episode} 集'
                                  : '';
                              final metaItems = <String>[
                                if (episode.isNotEmpty) episode,
                                if (item.positionMs >= 0) item.formattedProgress,
                              ];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showGroup)
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        index == 0 ? 12 : 14,
                                        16,
                                        4,
                                      ),
                                      child: Text(
                                        group,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: t.foregroundSubtle.withValues(
                                            alpha: 0.78,
                                          ),
                                        ),
                                      ),
                                    ),
                                  InkWell(
                                    onTap: () => onResume(
                                      MediaKey(
                                        sourceId: item.sourceId,
                                        mediaId: item.mediaId,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        9,
                                        8,
                                        9,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 54,
                                            height: 74,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: MediaCoverImage(
                                              url: item.cover,
                                              cacheWidth: (54 *
                                                      MediaQuery
                                                          .devicePixelRatioOf(
                                                        context,
                                                      ))
                                                  .round(),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: t.foreground,
                                                  ),
                                                ),
                                                if (metaItems.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 2,
                                                    children: [
                                                      for (var m = 0;
                                                          m < metaItems.length;
                                                          m++) ...[
                                                        if (m > 0)
                                                          Text(
                                                            '·',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: t
                                                                  .foregroundSubtle
                                                                  .withValues(
                                                                    alpha: 0.6,
                                                                  ),
                                                            ),
                                                          ),
                                                        Text(
                                                          metaItems[m],
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: m == 0 &&
                                                                    episode
                                                                        .isNotEmpty
                                                                ? t.foreground
                                                                      .withValues(
                                                                        alpha:
                                                                            0.84,
                                                                      )
                                                                : t
                                                                      .foregroundSubtle,
                                                            fontFeatures: const [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                                if (hasProgress) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Semantics(
                                                          label: '播放进度',
                                                          value:
                                                              '${(item.progress * 100).round()}%',
                                                          child: LinearProgressIndicator(
                                                            value:
                                                                item.progress,
                                                            minHeight: 3,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  99,
                                                                ),
                                                            backgroundColor:
                                                                t.border,
                                                            color: t.primary,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${(item.progress * 100).round()}%',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: t
                                                              .foregroundSubtle
                                                              .withValues(
                                                                alpha: 0.85,
                                                              ),
                                                          fontFeatures: const [
                                                            FontFeature.tabularFigures(),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: '移除${item.title}',
                                            onPressed: () =>
                                                HistoryStorage.delete(
                                                  item.sourceId,
                                                  item.mediaId,
                                                ),
                                            constraints: const BoxConstraints(
                                              minWidth: 38,
                                              minHeight: 38,
                                            ),
                                            icon: Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: t.foregroundSubtle
                                                  .withValues(alpha: 0.72),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
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
    );
  }
}

void confirmClearPlaybackHistory(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final errorColor = Theme.of(ctx).colorScheme.error;
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
        titleTextStyle: Theme.of(
          ctx,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        title: const Text('清空播放历史？'),
        content: const Text('所有续播进度也会删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: errorColor,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return errorColor.withValues(alpha: 0.16);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return errorColor.withValues(alpha: 0.09);
                }
                return null;
              }),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              HistoryStorage.clearAll();
            },
            child: const Text('清空'),
          ),
        ],
      );
    },
  );
}

class _ResumeRail extends StatelessWidget {
  const _ResumeRail();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HistoryStorage.listenable(),
    builder: (context, box, child) {
      final record = HistoryStorage.getAll(limit: 1).firstOrNull;
      if (record == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.fromLTRB(
          HomeLayoutMetrics.of(context).gutter,
          12,
          HomeLayoutMetrics.of(context).gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: PlayraHomeTokens.of(context).accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: PlayraSpace.sm),
                Expanded(
                  child: Text(
                    '继续观看',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => showPlaybackHistory(context),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.pushNamed(
                '/detail',
                arguments: MediaKey(
                  sourceId: record.sourceId,
                  mediaId: record.mediaId,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 96,
                        height: 54,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaCoverImage(
                              url: record.cover,
                              cacheWidth:
                                  (96 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                            ),
                            if (record.episodeTitle.isNotEmpty)
                              Positioned(
                                left: 4,
                                right: 4,
                                bottom: 4,
                                child: Align(
                                  alignment: Alignment.bottomRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xB8000000),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      record.episodeTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: PlayraType.micro,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            record.formattedProgress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (record.durationMs > 0) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: record.progress,
                                minHeight: 3,
                                semanticsLabel: '已观看',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .12),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
