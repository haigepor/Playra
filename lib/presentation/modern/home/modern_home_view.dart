import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../widgets/modern_page_art.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'home_theme.dart';
import 'modern_home_controller.dart';
import 'home_content_algorithm.dart';

String homeTitle(BangumiItem item) =>
    item.nameCn.isEmpty ? item.name : item.nameCn;

String homeCover(BangumiItem item) {
  for (final size in ['large', 'common', 'medium', 'small']) {
    final url = item.images[size];
    if (url != null && url.isNotEmpty) return url;
  }
  return '';
}

class ModernHomeView extends StatelessWidget {
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
  });
  final ModernHomeController controller;
  final VoidCallback onSearch, onCalendar, onHistory, onToggleTheme;
  final ValueChanged<BangumiItem> onDetails;
  final ValueChanged<History> onResume;
  final ValueChanged<String> onBrowse;

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ModernPageArt(
            kind: ModernPageArtKind.discover,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final items = controller.items;
                    final recent = controller.recent;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    // 固定导航独立于内容滚动，子分类展开仍可平滑改变内容区高度。
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                          child: Column(
                            children: [
                              _FeedSelector(controller: controller),
                              _AnimeFilters(controller: controller),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () async {
                              controller.reloadHistory();
                              await controller.refresh();
                            },
                            child: CustomScrollView(
                              key: const PageStorageKey('modern-home-scroll'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    0,
                                  ),
                                  sliver: SliverList.list(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _SearchEntry(
                                              onSearch: onSearch,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          FilledButton.icon(
                                            key: const ValueKey(
                                              'home-calendar',
                                            ),
                                            onPressed: onCalendar,
                                            icon: const Icon(
                                              LucideIcons.calendarDays,
                                              size: 17,
                                            ),
                                            label: const Text(
                                              '排期表',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 44),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      if (!controller.feed.hasContentSource)
                                        _CategoryPending(feed: controller.feed)
                                      else if (items.isNotEmpty &&
                                          controller.feed ==
                                              HomeFeed.recommended)
                                        _RecommendationBento(
                                          items: controller.featuredItems,
                                          canShuffle:
                                              items.length >
                                              ModernHomeController
                                                  .featuredBatchSize,
                                          onShuffle: controller.shuffleFeatured,
                                          onDetails: onDetails,
                                        )
                                      else if (items.isNotEmpty)
                                        _Featured(
                                          item: items.first,
                                          onDetails: () =>
                                              onDetails(items.first),
                                        )
                                      else if (controller.loading ||
                                          controller.catalogLoading)
                                        const _LoadingFeature()
                                      else
                                        _EmptyFeed(
                                          message:
                                              controller.error ?? '暂时没有可展示的番剧',
                                          retry: controller.refresh,
                                        ),
                                      if (controller.error != null &&
                                          items.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: _EmptyFeed(
                                            message: controller.error!,
                                            retry: controller.refresh,
                                          ),
                                        ),
                                      if (recent.isNotEmpty) ...[
                                        const SizedBox(height: 18),
                                        _SectionHeading(
                                          title: '继续观看',
                                          subtitle: '',
                                          actionLabel: '全部',
                                          onAction: onHistory,
                                        ),
                                        const SizedBox(height: 8),
                                        LayoutBuilder(
                                          builder: (context, bounds) =>
                                              SizedBox(
                                                height:
                                                    94 +
                                                    32 *
                                                        (scale - 1).clamp(0, 3),
                                                child: ListView.separated(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  itemCount: recent.length,
                                                  separatorBuilder: (_, _) =>
                                                      const SizedBox(width: 12),
                                                  itemBuilder: (_, index) =>
                                                      _ContinueCard(
                                                        history: recent[index],
                                                        width: math.min(
                                                          bounds.maxWidth -
                                                              (recent.length > 1
                                                                  ? 20
                                                                  : 0),
                                                          350,
                                                        ),
                                                        onTap: () => onResume(
                                                          recent[index],
                                                        ),
                                                      ),
                                                ),
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SliverList.list(
                                  children: [
                                    if (controller.catalog.hasStructuredData &&
                                        controller.feed.hasContentSource)
                                      for (final channel in controller.channels)
                                        _ChannelRail(
                                          id: channel.id,
                                          title: channel.title,
                                          items: channel.items,
                                          controller: controller,
                                          onDetails: onDetails,
                                          onMore: () => _showChannelItems(
                                            context,
                                            channel,
                                            controller,
                                            onDetails,
                                          ),
                                        ),
                                    if (!controller
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
                                          controller: controller,
                                          onDetails: onDetails,
                                          onMore: () => onBrowse(
                                            switch (controller.feed) {
                                              HomeFeed.chinese => '中国',
                                              HomeFeed.japanese => '日本',
                                              _ => '',
                                            },
                                          ),
                                        ),
                                      if (controller.feed.hasContentSource) ...[
                                        _ChannelRail(
                                          id: 'chinese',
                                          onMore: () => onBrowse('中国'),
                                          title: '国漫剧场',
                                          items: controller.catalog.chinese,
                                          controller: controller,
                                          onDetails: onDetails,
                                          loading: controller.catalogLoading,
                                          failed: controller.catalog.failed
                                              .contains('chinese'),
                                        ),
                                        _ChannelRail(
                                          id: 'japanese',
                                          onMore: () => onBrowse('日本'),
                                          title: '日漫精选',
                                          items: controller.catalog.japanese,
                                          controller: controller,
                                          onDetails: onDetails,
                                          loading: controller.catalogLoading,
                                          failed: controller.catalog.failed
                                              .contains('japanese'),
                                        ),
                                      ],
                                    ],
                                    const SizedBox(height: 24),
                                  ],
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
            ),
          ),
        ),
      ),
    ),
  );
}

class _FeedSelector extends StatefulWidget {
  const _FeedSelector({required this.controller});
  final ModernHomeController controller;

  @override
  State<_FeedSelector> createState() => _FeedSelectorState();
}

class _FeedSelectorState extends State<_FeedSelector>
    with SingleTickerProviderStateMixin {
  static const categories = HomeFeed.primaryCategories;
  late final TabController _tabs;

  int get selectedIndex => categories.indexOf(
    widget.controller.feed.isAnimeCategory
        ? HomeFeed.anime
        : widget.controller.feed,
  );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: categories.length,
      vsync: this,
      initialIndex: selectedIndex,
      animationDuration: const Duration(milliseconds: 260),
    );
    widget.controller.addListener(_syncSelection);
  }

  void _syncSelection() {
    if (_tabs.index == selectedIndex) return;
    _tabs.animateTo(
      selectedIndex,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _FeedSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSelection);
      widget.controller.addListener(_syncSelection);
      _syncSelection();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSelection);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 与追番分类复用原生指示器行为；横向手势浏览分类，不触发数据切换。
    return TabBar(
      key: const ValueKey('home-feed-selector'),
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      indicator: UnderlineTabIndicator(
        borderRadius: BorderRadius.circular(2),
        borderSide: BorderSide(width: 3, color: colors.primary),
        insets: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onTap: (index) => widget.controller.selectFeed(categories[index]),
      tabs: [
        for (var i = 0; i < categories.length; i++)
          Tab(
            key: ValueKey('home-feed-${categories[i].name}'),
            height: 44,
            child: Text(
              categories[i].label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selectedIndex == i
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selectedIndex == i
                    ? colors.onSurface
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _AnimeFilters extends StatefulWidget {
  const _AnimeFilters({required this.controller});
  final ModernHomeController controller;

  @override
  State<_AnimeFilters> createState() => _AnimeFiltersState();
}

class _AnimeFiltersState extends State<_AnimeFilters> {
  static const _feeds = [
    HomeFeed.anime,
    HomeFeed.season,
    HomeFeed.japanese,
    HomeFeed.chinese,
    HomeFeed.animeMovies,
  ];
  double? _dragPosition;

  @override
  void didUpdateWidget(covariant _AnimeFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controller.feed.isAnimeCategory) _dragPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = widget.controller.feed.isAnimeCategory;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    final position =
        _dragPosition ??
        _feeds
            .indexOf(widget.controller.feed)
            .clamp(0, _feeds.length - 1)
            .toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: visible ? 1 : 0, end: visible ? 1 : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      // 保持子分类挂载，用高度、透明度和位移过渡展开，避免突然挤动搜索栏。
      builder: (context, reveal, child) => ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          heightFactor: reveal,
          child: IgnorePointer(
            ignoring: !visible,
            child: ExcludeFocus(
              excluding: !visible,
              child: ExcludeSemantics(
                excluding: !visible,
                child: Opacity(
                  opacity: reveal,
                  child: Transform.translate(
                    offset: Offset(0, -6 * (1 - reveal)),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final width = 300 * scale;
            final cellWidth = width / _feeds.length;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: 36 * scale,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: width > bounds.maxWidth
                      ? null
                      : (_) => setState(() {
                          _dragPosition = position;
                        }),
                  onHorizontalDragUpdate: width > bounds.maxWidth
                      ? null
                      : (details) => setState(() {
                          _dragPosition =
                              (details.localPosition.dx / cellWidth - .5)
                                  .clamp(0, _feeds.length - 1)
                                  .toDouble();
                        }),
                  onHorizontalDragEnd: width > bounds.maxWidth
                      ? null
                      : (_) {
                          final feed =
                              _feeds[(_dragPosition ?? position).round()];
                          setState(() => _dragPosition = null);
                          widget.controller.selectFeed(feed);
                        },
                  onHorizontalDragCancel: width > bounds.maxWidth
                      ? null
                      : () => setState(() => _dragPosition = null),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        left: 4,
                        right: 4,
                        child: IgnorePointer(
                          child: AnimatedAlign(
                            alignment: Alignment(
                              position * 2 / (_feeds.length - 1) - 1,
                              0,
                            ),
                            duration: _dragPosition == null
                                ? duration
                                : Duration.zero,
                            curve: Curves.easeInOutCubic,
                            child: Container(
                              width: cellWidth - 8,
                              height: 36 * scale,
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final feed in _feeds)
                            Expanded(
                              child: Semantics(
                                selected:
                                    _feeds.indexOf(feed) == position.round(),
                                child: TextButton(
                                  onPressed: () =>
                                      widget.controller.selectFeed(feed),
                                  style: TextButton.styleFrom(
                                    minimumSize: Size(0, 36 * scale),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    overlayColor: Colors.transparent,
                                  ),
                                  child: Text(
                                    feed == HomeFeed.anime ? '全部' : feed.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          _feeds.indexOf(feed) ==
                                              position.round()
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryPending extends StatelessWidget {
  const _CategoryPending({required this.feed});
  final HomeFeed feed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(
            switch (feed) {
              HomeFeed.movies => Icons.movie_outlined,
              HomeFeed.television => Icons.live_tv_outlined,
              HomeFeed.variety => Icons.mic_none_outlined,
              _ => Icons.auto_stories_outlined,
            },
            size: 30,
            color: colors.primary,
          ),
          const SizedBox(height: 14),
          Text(
            '${feed.label}频道',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '内容即将上线',
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
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
  });
  final String id, title;
  final List<BangumiItem> items;
  final ModernHomeController controller;
  final ValueChanged<BangumiItem> onDetails;
  final VoidCallback onMore;
  final bool loading, failed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 12),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (failed)
                  TextButton(
                    onPressed: controller.refreshCatalog,
                    child: const Text('重试'),
                  )
                else
                  TextButton(
                    key: ValueKey('home-more-$id'),
                    onPressed: onMore,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      padding: const EdgeInsets.only(left: 8),
                      minimumSize: const Size(0, 40),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('查看更多', style: TextStyle(fontSize: 11)),
                        SizedBox(width: 4),
                        Icon(LucideIcons.chevronRight, size: 14),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        failed ? '这个栏目暂时未加载，点击重试' : '暂时没有番剧',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, bounds) {
                final width = ((bounds.maxWidth - 40) / 3.1 - 8).clamp(
                  104.0,
                  144.0,
                );
                return SizedBox(
                  height: width * 1.42 + 48 * scale,
                  child: ScrollConfiguration(
                    behavior: const _HomeScrollBehavior(),
                    child: ListView.separated(
                      key: PageStorageKey('home-channel-$id'),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
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

/// 展开同一份栏目快照，避免标签搜索放宽类型条件后混入其他分类。
Future<void> _showChannelItems(
  BuildContext context,
  HomeChannel channel,
  ModernHomeController controller,
  ValueChanged<BangumiItem> onDetails,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  showDragHandle: true,
  builder: (sheetContext) => ModernHomeScope(
    child: DraggableScrollableSheet(
      initialChildSize: .82,
      minChildSize: .4,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      channel.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                  final columns = ((bounds.maxWidth - 40) / (116 * scale))
                      .floor()
                      .clamp(2, 6);
                  final width =
                      (bounds.maxWidth - 40 - 12 * (columns - 1)) / columns;
                  return ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => ScrollConfiguration(
                      behavior: const _HomeScrollBehavior(),
                      child: GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: channel.allItems.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          mainAxisExtent: width * 1.42 + 48 * scale,
                        ),
                        itemBuilder: (context, index) => _PosterCard(
                          item: channel.allItems[index],
                          controller: controller,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onDetails(channel.allItems[index]);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// 浏览器验收支持鼠标拖动，安卓沿用触摸滚动与平台惯性。
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
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '搜索番剧、角色或关键词',
    button: true,
    onTap: onSearch,
    child: ExcludeSemantics(
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: InkWell(
          key: const ValueKey('home-search'),
          onTap: onSearch,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '搜索番剧、角色或关键词',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

class _RecommendationBento extends StatelessWidget {
  const _RecommendationBento({
    required this.items,
    required this.canShuffle,
    required this.onShuffle,
    required this.onDetails,
  });
  final List<BangumiItem> items;
  final bool canShuffle;
  final VoidCallback onShuffle;
  final ValueChanged<BangumiItem> onDetails;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final rowHeight =
          ((bounds.maxWidth - 10) / 2 * .75).clamp(112.0, 142.0) +
          48 * (scale - 1).clamp(0, 3);
      final rows = (items.length + 1) ~/ 2;
      return Column(
        children: [
          SizedBox(
            height: rowHeight * rows + 10 * (rows - 1),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(items.map((i) => i.id).join('-')),
                children: [
                  for (var row = 0; row < rows; row++) ...[
                    if (row > 0) const SizedBox(height: 10),
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var column = 0; column < 2; column++) ...[
                            if (column > 0) const SizedBox(width: 10),
                            Expanded(
                              child: row * 2 + column < items.length
                                  ? _BentoCard(
                                      item: items[row * 2 + column],
                                      onTap: () =>
                                          onDetails(items[row * 2 + column]),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            key: const ValueKey('home-shuffle-featured'),
            onPressed: canShuffle ? onShuffle : null,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('换一批', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              overlayColor: Colors.transparent,
              minimumSize: const Size(104, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      );
    },
  );
}

class _BentoCard extends StatefulWidget {
  const _BentoCard({required this.item, required this.onTap});
  final BangumiItem item;
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
        src: homeCover(widget.item),
        width: width,
        height: height,
        type: 'bg',
        borderRadius: BorderRadius.zero,
      ),
    ),
  );

  Widget _rating() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(LucideIcons.star, size: 12, color: Color(0xffe7b65c)),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          widget.item.ratingScore > 0
              ? widget.item.ratingScore.toStringAsFixed(1)
              : '暂无评分',
          semanticsLabel: widget.item.ratingScore > 0
              ? '评分 ' + widget.item.ratingScore.toStringAsFixed(1)
              : '暂无评分',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      button: true,
      label: '查看推荐 ' + homeTitle(widget.item),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        clipBehavior: Clip.antiAlias,
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
                  bounds.maxWidth * .43,
                  bounds.maxHeight * .68,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: coverWidth,
                      child: _cover(coverWidth, bounds.maxHeight),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              homeTitle(widget.item),
                              maxLines: scale > 1.3 ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _rating(),
                          ],
                        ),
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

class _Featured extends StatelessWidget {
  const _Featured({required this.item, required this.onDetails});
  final BangumiItem item;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final metadata = {
      ...item.metaTags,
      ...item.tags.map((tag) => tag.name),
    }.take(2).join(' · ');
    return Material(
      key: const ValueKey('home-featured'),
      color: const Color(0xff222e50),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: SizedBox(
          height: 176 + 110 * (scale - 1).clamp(0, 3),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: SvgPicture.asset(
                    'assets/images/modern-home-screen.svg',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final coverWidth = math.min(
                      constraints.maxWidth * .34,
                      116.0,
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        LucideIcons.sparkles,
                                        size: 13,
                                        color: Color(0xffc1cdff),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        '精选推荐',
                                        style: TextStyle(
                                          color: Color(0xffc1cdff),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    homeTitle(item),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    metadata.isNotEmpty
                                        ? metadata
                                        : item.airDate.isNotEmpty
                                        ? item.airDate
                                        : '开启一段新故事',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xffb7c3df),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              ShadButton(
                                key: const ValueKey('home-featured-details'),
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                backgroundColor: const Color(0xfff1f4ff),
                                foregroundColor: const Color(0xff283760),
                                hoverBackgroundColor: Colors.white,
                                onPressed: onDetails,
                                trailing: const Icon(
                                  LucideIcons.arrowRight,
                                  size: 14,
                                ),
                                child: const Text(
                                  '查看详情',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Transform.rotate(
                          angle: .035,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xff536080),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x50000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 9),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: NetworkImgLayer(
                                src: homeCover(item),
                                width: coverWidth,
                                height: coverWidth * 1.45,
                                fit: BoxFit.cover,
                                type: 'bg',
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
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
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (subtitle.isNotEmpty) const SizedBox(height: 4),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      ShadButton.ghost(
        size: ShadButtonSize.sm,
        onPressed: onAction,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        trailing: const Icon(LucideIcons.chevronRight, size: 14),
        child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
      ),
    ],
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
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: ValueKey('home-resume-${history.key}'),
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  NetworkImgLayer(
                    src: homeCover(history.bangumiItem),
                    width: 52,
                    height: 74,
                    type: 'bg',
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '第 ${history.lastWatchEpisode} 集 · $savedPosition',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
  final BangumiItem item;
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
      if (mounted) widget.controller.ensureSchedule(widget.item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final airing = widget.controller.scheduleLabel(item);
    return Semantics(
      label:
          '查看 ${homeTitle(item)}，评分 ${item.ratingScore > 0 ? item.ratingScore.toStringAsFixed(1) : '暂无'}，$airing',
      button: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('home-poster-${item.id}'),
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, bounds) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
                              src: homeCover(item),
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
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            key: ValueKey('home-rating-${item.id}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xffe7b65c),
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(9),
                              ),
                            ),
                            child: Text(
                              item.ratingScore > 0
                                  ? item.ratingScore.toStringAsFixed(1)
                                  : '暂无',
                              semanticsLabel: item.ratingScore > 0
                                  ? '评分 ${item.ratingScore.toStringAsFixed(1)}'
                                  : '暂无评分',
                              style: const TextStyle(
                                color: Color(0xff272017),
                                fontSize: 11,
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
                                fontSize: 10,
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
              const SizedBox(height: 8),
              Text(
                homeTitle(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
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
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        ShadButton.outline(
          onPressed: retry,
          size: ShadButtonSize.sm,
          child: const Text('重试'),
        ),
      ],
    ),
  );
}

class _LoadingFeature extends StatelessWidget {
  const _LoadingFeature();
  @override
  Widget build(BuildContext context) => Container(
    height: 176,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 16),
          Text('正在寻找好故事…', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
