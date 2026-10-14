import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import '../home/modern_home_controller.dart';
import '../widgets/modern_feature_carousel.dart';
import '../secondary/secondary_theme.dart';
import 'miomedia_browse.dart';
import 'miomedia_home_controller.dart';
import 'miomedia_rank_view.dart';

MioKind? mioKindForHomeFeed(HomeFeed feed) => switch (feed) {
  HomeFeed.movies => MioKind.movie,
  HomeFeed.television => MioKind.series,
  HomeFeed.variety => MioKind.variety,
  HomeFeed.comicDrama => MioKind.comicDrama,
  _ => null,
};

class MioGenreFilters extends StatefulWidget {
  const MioGenreFilters({
    super.key,
    required this.controller,
    required this.kind,
  });
  final MioHomeController controller;
  final MioKind kind;
  @override
  State<MioGenreFilters> createState() => _MioGenreFiltersState();
}

class _MioGenreFiltersState extends State<MioGenreFilters>
    with TickerProviderStateMixin {
  List<String> _genres = [];
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    _syncTabs();
  }

  @override
  void didUpdateWidget(covariant MioGenreFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabs(reset: oldWidget.kind != widget.kind, animate: true);
  }

  void _syncTabs({bool reset = false, bool animate = false}) {
    final genres = widget.controller.genres(widget.kind);
    final selected = widget.controller.genreSelections[widget.kind] ?? '';
    final index = selected.isEmpty ? 0 : genres.indexOf(selected) + 1;
    // 题材来自增量数据；频道或题材列表改变时重建控制器，避免索引错配。
    if (reset || !listEquals(genres, _genres)) {
      _tabs?.dispose();
      _genres = genres;
      _tabs = genres.isEmpty
          ? null
          : TabController(
              length: genres.length + 1,
              initialIndex: index,
              vsync: this,
              animationDuration: const Duration(milliseconds: 240),
            );
    } else if (_tabs != null && _tabs!.index != index) {
      _tabs!.animateTo(
        index,
        duration: !animate || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 只有“全部”时没有筛选意义，不保留空分类行或额外间距。
    if (_tabs == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(
        height: 38 * scale,
        child: TabBar(
          key: PageStorageKey('mio-genres-${widget.kind.name}'),
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: EdgeInsets.zero,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: EdgeInsets.symmetric(
            horizontal: 3,
            vertical: 4 * scale,
          ),
          indicator: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(9),
          ),
          automaticIndicatorColorAdjustment: false,
          labelColor: colors.primary,
          unselectedLabelColor: colors.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          onTap: (index) => widget.controller.selectGenre(
            widget.kind,
            index == 0 ? '' : _genres[index - 1],
          ),
          tabs: [
            for (final genre in ['', ..._genres])
              Tab(
                key: ValueKey('mio-genre-${widget.kind.name}-$genre'),
                height: 38 * scale,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 64 * scale),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(child: Text(genre.isEmpty ? '全部' : genre)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MioFeaturedCard extends StatelessWidget {
  const MioFeaturedCard({
    super.key,
    required this.controller,
    required this.kind,
    required this.onDetails,
  });
  final MioHomeController controller;
  final MioKind kind;
  final ValueChanged<MioVideo> onDetails;
  @override
  Widget build(BuildContext context) {
    final video = controller.featured(kind);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (video == null) {
      return controller.discovering || controller.loading.contains(kind)
          ? SkeletonFeature(height: 206 + 115 * (scale - 1).clamp(0, 3))
          : const SizedBox.shrink();
    }
    final items = controller.filtered(kind).take(6).toList();
    return ModernFeatureCarousel(
      key: ValueKey(
        'mio-feature-${kind.name}-${controller.genreSelections[kind]}',
      ),
      entries: [
        for (final item in items)
          ModernFeatureEntry(
            id: item.id,
            title: item.title,
            subtitle: item.genres.isEmpty
                ? item.subtitle
                : item.genres.take(3).join(' · '),
            cover: item.cover.isEmpty ? item.poster : item.cover,
            onTap: () => onDetails(item),
          ),
      ],
    );
  }
}

/// 推荐栏目与尾部网格使用同一个滚动视图；长列表按需构建，避免分页后全量渲染。
class MioCategorySliver extends StatelessWidget {
  const MioCategorySliver({
    super.key,
    required this.controller,
    required this.kind,
    required this.onDetails,
  });
  final MioHomeController controller;
  final MioKind kind;
  final ValueChanged<MioVideo> onDetails;

  @override
  Widget build(BuildContext context) {
    final pool = controller.filtered(kind);
    final rated = controller.rated(kind).take(8).toList();
    final genres =
        controller
            .genres(kind)
            .where(
              (genre) =>
                  genre != controller.genreSelections[kind] &&
                  pool.where((video) => video.genres.contains(genre)).length >=
                      2,
            )
            .toList()
          ..sort(
            (a, b) => pool
                .where((v) => v.genres.contains(b))
                .length
                .compareTo(pool.where((v) => v.genres.contains(a)).length),
          );
    final loading =
        controller.loading.contains(kind) ||
        (pool.isEmpty && controller.discovering);
    final failed =
        controller.failed.contains(kind) || controller.discoveryFailed;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MioRankSection(
                  controller: controller,
                  categoryId: controller.categoryIds[kind],
                  onDetails: onDetails,
                ),
                if (rated.isNotEmpty)
                  _Rail(title: '口碑佳片', items: rated, onDetails: onDetails),
                for (final genre in genres.take(2))
                  _Rail(
                    title: '$genre精选',
                    items: pool
                        .where((v) => v.genres.contains(genre))
                        .take(8)
                        .toList(),
                    onDetails: onDetails,
                  ),
                const _Heading('猜你喜欢'),
                const SizedBox(height: 4),
                Text(
                  controller.genreSelections[kind]?.isNotEmpty == true
                      ? '继续发现${controller.genreSelections[kind]}题材作品'
                      : '更多值得一看的${kind.label}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        if (pool.isEmpty && !loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SecondaryEmptyState(
                key: const ValueKey('mio-category-empty'),
                asset: 'modern-home-empty-feed',
                title: failed ? '内容暂时加载失败' : '暂无符合题材的作品',
                description: failed
                    ? controller.failureMessage(kind)
                    : '试试其他分类，或稍后回来看看',
                action: failed
                    ? TextButton(
                        onPressed: () =>
                            controller.categoryIds.containsKey(kind)
                            ? controller.load(
                                kind,
                                reset: !controller.pages.containsKey(kind),
                              )
                            : controller.bootstrap(force: true),
                        child: const Text('加载失败，点击重试'),
                      )
                    : null,
              ),
            ),
          ),
        if (pool.isEmpty && loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, bounds) => SkeletonPosters(
                  horizontal: false,
                  count: 6,
                  gridDelegate: mioPosterGridDelegate(context, bounds.maxWidth),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverLayoutBuilder(
            builder: (context, bounds) => SliverGrid(
              gridDelegate: mioPosterGridDelegate(
                context,
                bounds.crossAxisExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => MioPoster(
                  key: ValueKey('mio-guess-${pool[index].id}'),
                  video: pool[index],
                  onTap: () => onDetails(pool[index]),
                ),
                childCount: pool.length,
              ),
            ),
          ),
        ),
        if (pool.isNotEmpty && loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: LayoutBuilder(
                builder: (context, bounds) => SkeletonPosters(
                  horizontal: false,
                  count: 3,
                  gridDelegate: mioPosterGridDelegate(context, bounds.maxWidth),
                ),
              ),
            ),
          ),
        if (pool.isNotEmpty || loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Center(
                child: loading || (pool.isEmpty && !failed)
                    ? const SizedBox.shrink()
                    : failed
                    ? TextButton(
                        onPressed: () =>
                            controller.categoryIds.containsKey(kind)
                            ? controller.load(
                                kind,
                                reset: !controller.pages.containsKey(kind),
                              )
                            : controller.bootstrap(force: true),
                        child: const Text('加载失败，点击重试'),
                      )
                    : Text(
                        controller.more.contains(kind)
                            ? '继续下滑，发现更多'
                            : '已显示当前全部内容',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.items,
    required this.onDetails,
  });
  final String title;
  final List<MioVideo> items;
  final ValueChanged<MioVideo> onDetails;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = (bounds.maxWidth / 3.1 - 8).clamp(104.0, 144.0);
      final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(title),
          const SizedBox(height: 12),
          SizedBox(
            height: width * 1.42 + 66 * scale,
            child: ListView.separated(
              key: PageStorageKey('mio-shelf-$title'),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: width,
                child: MioPoster(
                  video: items[index],
                  onTap: () => onDetails(items[index]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      );
    },
  );
}
