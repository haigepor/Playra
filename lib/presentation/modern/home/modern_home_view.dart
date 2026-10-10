import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'home_theme.dart';
import 'modern_home_controller.dart';

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
    required this.onHistory,
    required this.onToggleTheme,
    required this.onDetails,
    required this.onResume,
  });
  final ModernHomeController controller;
  final VoidCallback onSearch, onHistory, onToggleTheme;
  final ValueChanged<BangumiItem> onDetails;
  final ValueChanged<History> onResume;

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(constraints.maxWidth, 760.0) - 40;
              final columns = width < 310
                  ? 2
                  : width > 560
                  ? 4
                  : 3;
              final posterWidth = (width - (columns - 1) * 12) / columns;
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final items = controller.items;
                      final recent = controller.recent;
                      return RefreshIndicator(
                        onRefresh: () async {
                          controller.reloadHistory();
                          await controller.refresh();
                        },
                        child: CustomScrollView(
                          key: const PageStorageKey('modern-home-scroll'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              sliver: SliverList.list(
                                children: [
                                  _BrandHeader(
                                    onHistory: onHistory,
                                    onToggleTheme: onToggleTheme,
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    '找到今天的心动番剧',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.7,
                                      height: 1.25,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _SearchEntry(onSearch: onSearch),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final feed in HomeFeed.values)
                                        Semantics(
                                          selected: controller.feed == feed,
                                          child: ShadButton.raw(
                                            key: ValueKey(
                                              'home-feed-${feed.name}',
                                            ),
                                            height: 38,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                            ),
                                            variant: controller.feed == feed
                                                ? ShadButtonVariant.primary
                                                : ShadButtonVariant.ghost,
                                            onPressed: () =>
                                                controller.selectFeed(feed),
                                            child: Text(
                                              feed.label,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  if (items.isNotEmpty)
                                    _Featured(
                                      item: items.first,
                                      onDetails: () => onDetails(items.first),
                                    )
                                  else if (controller.loading)
                                    const _LoadingFeature()
                                  else
                                    _EmptyFeed(
                                      message: controller.error ?? '暂时没有可展示的番剧',
                                      retry: controller.refresh,
                                    ),
                                  const SizedBox(height: 22),
                                  _SectionHeading(
                                    title: '继续观看',
                                    subtitle: '把故事接着看完',
                                    actionLabel: '全部',
                                    onAction: onHistory,
                                  ),
                                  const SizedBox(height: 12),
                                  if (recent.isEmpty)
                                    const _EmptyWatch()
                                  else
                                    SizedBox(
                                      height: 94 + 32 * (scale - 1).clamp(0, 3),
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: recent.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(width: 12),
                                        itemBuilder: (_, index) =>
                                            _ContinueCard(
                                              history: recent[index],
                                              width: math.min(
                                                width -
                                                    (recent.length > 1
                                                        ? 20
                                                        : 0),
                                                350,
                                              ),
                                              onTap: () =>
                                                  onResume(recent[index]),
                                            ),
                                      ),
                                    ),
                                  const SizedBox(height: 22),
                                  _SectionHeading(
                                    title: controller.feed == HomeFeed.season
                                        ? '新番放映'
                                        : '大家都在看',
                                    subtitle: controller.feed == HomeFeed.season
                                        ? '从新故事里，找到新的期待'
                                        : '总有一部，值得你按下播放',
                                    actionLabel:
                                        controller.feed == HomeFeed.season
                                        ? '热门'
                                        : '新番',
                                    onAction: () => controller.selectFeed(
                                      controller.feed == HomeFeed.season
                                          ? HomeFeed.popular
                                          : HomeFeed.season,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (controller.error != null &&
                                      items.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: _EmptyFeed(
                                        message: controller.error!,
                                        retry: controller.refresh,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: items.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                      mainAxisExtent:
                                          posterWidth * 1.42 + 65 * scale,
                                    ),
                                itemBuilder: (_, index) => _PosterCard(
                                  item: items[index],
                                  onTap: () => onDetails(items[index]),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                28,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Center(
                                  child: controller.loading && items.isNotEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : controller.hasMore
                                      ? ShadButton.outline(
                                          key: const ValueKey('home-load-more'),
                                          onPressed: controller.loadMore,
                                          trailing: const Icon(
                                            LucideIcons.chevronDown,
                                            size: 16,
                                          ),
                                          child: const Text('加载更多'),
                                        )
                                      : items.isNotEmpty
                                      ? Text(
                                          '好故事，值得慢慢发现',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onHistory, required this.onToggleTheme});
  final VoidCallback onHistory, onToggleTheme;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SvgPicture.asset(
        'assets/images/modern-home-mark.svg',
        width: 36,
        height: 36,
        excludeFromSemantics: true,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kazumi',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -.7,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '发现新的故事',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      _HeaderButton(
        id: 'home-history',
        label: '历史记录',
        icon: LucideIcons.history,
        action: onHistory,
      ),
      const SizedBox(width: 8),
      _HeaderButton(
        id: 'home-theme',
        label: '切换明暗主题',
        action: onToggleTheme,
        icon: Theme.of(context).brightness == Brightness.dark
            ? LucideIcons.moon
            : LucideIcons.sun,
      ),
    ],
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.action,
  });
  final String id, label;
  final IconData icon;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    key: ValueKey(id),
    tooltip: label,
    onPressed: action,
    icon: Icon(icon, size: 19),
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onSearch});
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => Semantics(
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
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
                Icon(
                  LucideIcons.arrowUpRight,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Featured extends StatelessWidget {
  const _Featured({required this.item, required this.onDetails});
  final BangumiItem item;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final metadata = [
      ...item.metaTags,
      ...item.tags.map((tag) => tag.name),
    ].toSet().take(2).join(' · ');
    return Material(
      key: const ValueKey('home-featured'),
      color: const Color(0xff222e50),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: SizedBox(
          height: 208 + 110 * (scale - 1).clamp(0, 3),
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
            const SizedBox(height: 4),
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

class _EmptyWatch extends StatelessWidget {
  const _EmptyWatch();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        SvgPicture.asset(
          'assets/images/modern-home-empty-watch.svg',
          width: 84,
          height: 66,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '好故事，从第一帧开始',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '看过的番剧会留在这里，随时继续。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
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

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item, required this.onTap});
  final BangumiItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '查看 ${homeTitle(item)}',
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('home-poster-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => NetworkImgLayer(
                src: homeCover(item),
                width: constraints.maxWidth,
                height: constraints.maxWidth * 1.42,
                type: 'bg',
                borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 4),
            Row(
              children: [
                if (item.ratingScore > 0) ...[
                  Icon(
                    LucideIcons.star,
                    size: 11,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.ratingScore.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                if (item.airDate.length >= 4)
                  Expanded(
                    child: Text(
                      item.airDate.substring(0, 4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    height: 208,
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
