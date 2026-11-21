import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

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

class _DiscoverPageState extends State<DiscoverPage> {
  Future<HomeFeed>? _homeFuture;
  Future<List<MediaCategory>>? _categoryFuture;
  Object? _error;

  MediaSource? get _source => mediaSources.primary;

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
      _homeFuture = source.loadHome();
      _categoryFuture = source.loadCategories();
    });
  }

  Future<void> _refresh() async {
    _source?.invalidateCache();
    _load();
    try {
      // RefreshIndicator needs this future to complete; failures are rendered
      // by the FutureBuilder and must not become an uncaught exception.
      await _homeFuture;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    return PlayraBackdrop(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
          child: Column(
            children: [
              HomeTopBar(
                layout: layout,
                sourceLabel: _source?.displayName ?? '',
                categories: _categoryFuture,
                onSearch: () => context.pushNamed('/search'),
                onCategorySelected: _openCategory,
                onCalendar: () => widget.onSelectTab?.call(1),
                onHistory: _openHistory,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: FutureBuilder<HomeFeed>(
                    future: _homeFuture,
                    builder: (context, snapshot) {
                      final slivers = <Widget>[];
                      if (_error != null || snapshot.hasError) {
                        slivers.add(
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: MediaRetryNotice(
                              message: '首页加载失败',
                              error: _error ?? snapshot.error,
                              retrying:
                                  snapshot.connectionState ==
                                  ConnectionState.waiting,
                              onRetry: _load,
                            ),
                          ),
                        );
                      } else if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        slivers.add(
                          SliverToBoxAdapter(
                            child: _HomeLoading(layout: layout),
                          ),
                        );
                      } else {
                        final feed = snapshot.data;
                        if (feed == null || feed.isEmpty) {
                          slivers.add(
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: PlayraPageState(
                                icon: Icons.video_library_outlined,
                                title: '首页暂时没有内容',
                              ),
                            ),
                          );
                        } else {
                          final banners = feed.banners.isNotEmpty
                              ? feed.banners
                              : _fallbackBanners(feed);
                          if (banners.isNotEmpty) {
                            slivers.add(
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: layout.isPhone
                                        ? 0
                                        : layout.gutter,
                                  ),
                                  child: _buildHeroArea(
                                    context,
                                    layout,
                                    banners,
                                    feed,
                                  ),
                                ),
                              ),
                            );
                          }
                          slivers.add(
                            const SliverToBoxAdapter(child: _ResumeRail()),
                          );
                          for (final section in feed.sections) {
                            if (section.items.isEmpty) continue;
                            slivers.add(
                              SliverToBoxAdapter(
                                child: HomeSectionGrid(
                                  layout: layout,
                                  section: section,
                                  onTap: _openDetail,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroArea(
    BuildContext context,
    HomeLayoutMetrics layout,
    List<MediaBanner> banners,
    HomeFeed feed,
  ) {
    final hero = HomeBannerCarousel(
      layout: layout,
      banners: banners,
      onTap: _openBanner,
    );
    final ranked = _rankedSection(feed);
    if (!layout.showRankingPanel || ranked == null) return hero;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = PlayraSpace.lg;
        final leftWidth = (constraints.maxWidth - gap) * .62;
        final cardHeight = (leftWidth * layout.heroFraction * 9 / 16).clamp(
          layout.heroMinHeight,
          layout.heroMaxHeight,
        );
        // The carousel column also includes its top padding and dot row.
        // Keep a little extra room for the dot animation and the PageView
        // viewport rounding at tablet widths.
        const carouselChrome = PlayraSpace.sm * 2 + 20;
        return SizedBox(
          height: cardHeight + carouselChrome,
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
                  onTap: _openDetail,
                ),
              ),
            ],
          ),
        );
      },
    );
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

  void _openCategory(MediaCategory category) {
    final source = _source;
    if (source == null) return;
    context.pushNamed(
      '/browse',
      arguments: BrowseArgs(
        sourceId: source.id,
        categoryId: category.id,
        title: category.name,
      ),
    );
  }

  void _openDetail(MediaItem item) {
    context.pushNamed('/detail', arguments: item.key);
  }

  void _openBanner(MediaBanner banner) {
    final target = banner.target;
    if (target != null) {
      context.pushNamed('/detail', arguments: target);
    } else if (banner.linkUrl.isNotEmpty) {
      _showPlaceholder('链接内容待接入');
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheet) => _HistoryBottomSheet(
      onResume: (key) {
        Navigator.pop(sheet);
        context.pushNamed('/detail', arguments: key);
      },
    ),
  );
}

class _HistoryBottomSheet extends StatelessWidget {
  const _HistoryBottomSheet({required this.onResume});

  final ValueChanged<MediaKey> onResume;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: size.height * (size.width > size.height ? .85 : .75),
      ),
      child: Material(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<Box<dynamic>>(
            valueListenable: HistoryStorage.listenable(),
            builder: (context, box, _) {
              final records = HistoryStorage.getAll();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 9),
                  Container(
                    height: 3,
                    width: 32,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '播放历史',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (records.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                confirmClearPlaybackHistory(context),
                            child: const Text('清空'),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: records.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text('还没有播放记录'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 0, 4, 6),
                            itemCount: records.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: t.border),
                            itemBuilder: (context, index) {
                              final item = records[index];
                              return Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => onResume(
                                        MediaKey(
                                          sourceId: item.sourceId,
                                          mediaId: item.mediaId,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              child: SizedBox(
                                                width: 56,
                                                height: 42,
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    MediaCoverImage(
                                                      url: item.cover,
                                                      fit: BoxFit.cover,
                                                    ),
                                                    if (item.durationMs > 0)
                                                      Align(
                                                        alignment: Alignment
                                                            .bottomCenter,
                                                        child:
                                                            LinearProgressIndicator(
                                                              value:
                                                                  item.progress,
                                                              minHeight: 2,
                                                              backgroundColor:
                                                                  Colors
                                                                      .black38,
                                                              color: t.primary,
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.title,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  DefaultTextStyle(
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall!
                                                        .copyWith(
                                                          color: t
                                                              .foregroundSubtle,
                                                        ),
                                                    child: Wrap(
                                                      spacing: 8,
                                                      children: [
                                                        Text(
                                                          item
                                                                  .episodeTitle
                                                                  .isEmpty
                                                              ? '第 ${item.episode} 集'
                                                              : item.episodeTitle,
                                                        ),
                                                        Text(
                                                          item.formattedPosition,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '移除${item.title}',
                                    onPressed: () => HistoryStorage.delete(
                                      item.sourceId,
                                      item.mediaId,
                                    ),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: t.foregroundSubtle,
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
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
              foregroundColor: Theme.of(ctx).colorScheme.error,
              minimumSize: const Size(64, 48),
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
      final records = HistoryStorage.getAll(limit: 8);
      if (records.isEmpty) return const SizedBox.shrink();
      final single = records.length == 1 ? records.first : null;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '继续观看',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (single != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: InkWell(
                  onTap: () => context.pushNamed(
                    '/detail',
                    arguments: MediaKey(
                      sourceId: single.sourceId,
                      mediaId: single.mediaId,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          width: 112,
                          height: 65,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MediaCoverImage(url: single.cover),
                              if (single.durationMs > 0)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(
                                    value: single.progress,
                                    minHeight: 3,
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
                              single.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                single.episodeTitle,
                                single.formattedProgress,
                              ].where((part) => part.isNotEmpty).join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 106 + MediaQuery.textScalerOf(context).scale(14) * 1.3,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  scrollDirection: Axis.horizontal,
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final r = records[i];
                    return SizedBox(
                      width: 152,
                      child: InkWell(
                        onTap: () => context.pushNamed(
                          '/detail',
                          arguments: MediaKey(
                            sourceId: r.sourceId,
                            mediaId: r.mediaId,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 152,
                                height: 80,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    MediaCoverImage(url: r.cover),
                                    if (r.durationMs > 0)
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: LinearProgressIndicator(
                                          value: r.progress,
                                          minHeight: 3,
                                          backgroundColor: Colors.black45,
                                          semanticsLabel: '已观看',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                r.title,
                                r.episodeTitle,
                              ].where((part) => part.isNotEmpty).join(' · '),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
