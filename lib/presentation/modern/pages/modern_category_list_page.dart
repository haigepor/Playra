import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/presentation/modern/home/home_anime_card.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/settings/modern_back_button.dart';
import 'package:kazumi/presentation/modern/widgets/near_end_scroll.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

/// 统一的专门分类列表页面
///
/// 替代原首页栏目点击「查看更多」弹出的临时 Dialog / Sheet 窗口，
/// 提供专属的全屏分类浏览体验：包含现代化导航栏、作品计数徽章、
/// 响应式多端网格布局、沉浸海报卡片、无限滚动流式加载、回到顶部以及下拉刷新。
class ModernCategoryListPage extends StatefulWidget {
  const ModernCategoryListPage({
    super.key,
    required this.channelTitle,
    required this.channelId,
    required this.controller,
    required this.onDetails,
    this.readCards,
    this.sourceUpdates,
    this.sourceLoadMore,
    this.sourceHasMore,
    this.sourceLoading,
    this.sourceFailed,
    this.onRefresh,
    this.onSearch,
    this.initialCards,
    this.emptyMessage,
  });

  /// 分类名称，如「動態漫」、「日漫精选」、「国漫剧场」等
  final String channelTitle;

  /// 分类 ID
  final String channelId;

  /// 首页控制器
  final ModernHomeController controller;

  /// 查看作品详情回调
  final ValueChanged<BangumiItem> onDetails;

  /// 读取当前分类所有卡片的函数
  final List<HomeAnimeCard> Function()? readCards;

  /// 数据源变化监听
  final Listenable? sourceUpdates;

  /// 加载更多数据异步函数
  final Future<void> Function()? sourceLoadMore;

  /// 是否还有更多数据
  final bool Function()? sourceHasMore;

  /// 是否正在加载中
  final bool Function()? sourceLoading;

  /// 加载是否失败
  final bool Function()? sourceFailed;

  /// 手动刷新数据回调
  final Future<void> Function()? onRefresh;

  /// 打开分类专属搜索回调
  final VoidCallback? onSearch;

  /// 兜底初始卡片列表
  final List<HomeAnimeCard>? initialCards;

  /// 无内容时的提示文案
  final String? emptyMessage;

  @override
  State<ModernCategoryListPage> createState() => _ModernCategoryListPageState();
}

class _ModernCategoryListPageState extends State<ModernCategoryListPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 首次进入若数据为空且有更多，自动尝试拉取首批数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentCards = _getCards();
      if (currentCards.isEmpty && widget.sourceHasMore?.call() == true) {
        _triggerLoadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final showFab = offset > 350;
    if (showFab != _showBackToTop) {
      setState(() => _showBackToTop = showFab);
    }
  }

  List<HomeAnimeCard> _getCards() {
    final reader = widget.readCards;
    if (reader != null) {
      final list = reader();
      if (list.isNotEmpty) return list;
    }
    if (widget.initialCards != null && widget.initialCards!.isNotEmpty) {
      return widget.initialCards!;
    }
    if (widget.channelId == 'anime' && widget.controller.feed.isGeneralCategory) {
      return [
        for (final item in widget.controller.items)
          HomeAnimeCard.metadata(
            item,
            widget.controller,
            () => widget.onDetails(item),
          ),
      ];
    }
    return const [];
  }

  bool _isSourceLoading() {
    return _loadingMore ||
        widget.sourceLoading?.call() == true ||
        (widget.channelId == 'anime' &&
            widget.controller.feed.isGeneralCategory &&
            widget.controller.loading);
  }

  bool _isSourceHasMore() {
    if (widget.channelId == 'anime' &&
        widget.controller.feed.isGeneralCategory) {
      return widget.controller.hasMore;
    }
    return widget.sourceHasMore?.call() == true;
  }

  bool _isSourceFailed() {
    if (widget.channelId == 'anime' &&
        widget.controller.feed.isGeneralCategory) {
      return widget.controller.error != null;
    }
    return widget.sourceFailed?.call() == true;
  }

  Future<void> _triggerLoadMore() async {
    if (_loadingMore || _isSourceLoading()) return;
    if (!_isSourceHasMore()) return;

    setState(() => _loadingMore = true);
    try {
      if (widget.channelId == 'anime' &&
          widget.controller.feed.isGeneralCategory) {
        await widget.controller.loadMore();
      }
      if (widget.sourceLoadMore != null) {
        await widget.sourceLoadMore!();
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
      return;
    }
    if (widget.channelId == 'anime' &&
        widget.controller.feed.isGeneralCategory) {
      await widget.controller.refresh(includeCatalog: true);
      return;
    }
    if (widget.sourceLoadMore != null) {
      await widget.sourceLoadMore!();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    final theme = Theme.of(context);

    return ModernHomeScope(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.controller,
          ?widget.sourceUpdates,
        ]),
        builder: (context, _) {
          final cards = _getCards();
          final isLoading = _isSourceLoading();
          final hasMore = _isSourceHasMore();
          final isFailed = _isSourceFailed();

          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(
              scrolledUnderElevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
              elevation: 0,
              centerTitle: false,
              leading: ModernBackButton(
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              titleSpacing: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.channelTitle,
                    style: const TextStyle(
                      fontSize: PlayraType.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: PlayraSpace.sm),
                  if (cards.isNotEmpty)
                    PlayraBadge.secondary(
                      child: Text(
                        '${cards.length} 部',
                        style: const TextStyle(fontSize: PlayraType.micro),
                      ),
                    ),
                ],
              ),
              actions: [
                if (widget.onSearch != null)
                  PlayraIconButton(
                    tooltip: '搜索此分类',
                    onPressed: widget.onSearch,
                    icon: const Icon(LucideIcons.search, size: 18),
                  ),
                PlayraIconButton(
                  tooltip: '刷新',
                  onPressed: isLoading ? null : _handleRefresh,
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: PlayraSpinner(),
                        )
                      : const Icon(LucideIcons.rotateCw, size: 18),
                ),
                const SizedBox(width: PlayraSpace.sm),
              ],
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;

                  // 响应式多端列数适配：手机 3 列、中型平板 4-5 列、宽屏/桌面 6-7 列
                  final int columns;
                  if (width >= 1200) {
                    columns = 6;
                  } else if (width >= 880) {
                    columns = 5;
                  } else if (width >= 620) {
                    columns = 4;
                  } else if (width >= 380) {
                    columns = 3;
                  } else {
                    columns = 2;
                  }

                  const crossSpacing = 12.0;
                  const mainSpacing = 16.0;
                  final horizontalPadding =
                      width >= 840 ? PlayraSpace.xxl : PlayraSpace.lg;
                  final totalHorizontalSpacing =
                      horizontalPadding * 2 + crossSpacing * (columns - 1);
                  final cardWidth = (width - totalHorizontalSpacing) / columns;
                  final cardHeight = cardWidth * 1.42 + 52 * scale;

                  // 初始加载且无任何数据时的骨架屏
                  if (cards.isEmpty && isLoading) {
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        PlayraSpace.md,
                        horizontalPadding,
                        PlayraSpace.xxl,
                      ),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: columns * 4,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: crossSpacing,
                        mainAxisSpacing: mainSpacing,
                        mainAxisExtent: cardHeight,
                      ),
                      itemBuilder: (_, _) => const ContentSkeleton(
                        child: SkeletonPosterCard(),
                      ),
                    );
                  }

                  // 暂无数据时的优雅空状态
                  if (cards.isEmpty && !isLoading) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(PlayraSpace.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.film,
                              size: 48,
                              color: tokens.foregroundMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: PlayraSpace.md),
                            Text(
                              widget.emptyMessage ?? '暂无【${widget.channelTitle}】内容',
                              style: TextStyle(
                                fontSize: PlayraType.item,
                                fontWeight: FontWeight.w600,
                                color: tokens.foreground,
                              ),
                            ),
                            const SizedBox(height: PlayraSpace.xs),
                            Text(
                              '暂未检索到相关片目，请下拉或点击刷新重试',
                              style: TextStyle(
                                fontSize: PlayraType.caption,
                                color: tokens.foregroundMuted,
                              ),
                            ),
                            const SizedBox(height: PlayraSpace.lg),
                            PlayraButton.outline(
                              onPressed: _handleRefresh,
                              child: const Text('重新加载'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 正常列表：支持下拉刷新与向下无限滑动加载
                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (isNearEndScroll(notification) &&
                          !_isSourceLoading() &&
                          !isFailed &&
                          hasMore) {
                        unawaited(_triggerLoadMore());
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: _handleRefresh,
                      color: theme.colorScheme.primary,
                      backgroundColor: tokens.surfaceRaised,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              PlayraSpace.md,
                              horizontalPadding,
                              PlayraSpace.md,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: crossSpacing,
                                mainAxisSpacing: mainSpacing,
                                mainAxisExtent: cardHeight,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = cards[index];
                                  return _CategoryPosterCard(
                                    key: ValueKey('category-card-${item.id}'),
                                    item: item,
                                    controller: widget.controller,
                                    cardWidth: cardWidth,
                                    onTap: item.onTap,
                                  );
                                },
                                childCount: cards.length,
                              ),
                            ),
                          ),
                          // 底部加载更多状态、失败重试或全部完结提示
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: PlayraSpace.xxl * 2,
                                top: PlayraSpace.sm,
                              ),
                              child: Center(
                                child: _buildFooter(
                                  tokens: tokens,
                                  isLoading: isLoading,
                                  isFailed: isFailed,
                                  hasMore: hasMore,
                                  totalCount: cards.length,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            floatingActionButton: AnimatedScale(
              scale: _showBackToTop ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _showBackToTop ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: FloatingActionButton.small(
                  backgroundColor: tokens.surfaceRaised,
                  foregroundColor: tokens.foreground,
                  elevation: 4,
                  tooltip: '回到顶部',
                  onPressed: _scrollToTop,
                  child: const Icon(LucideIcons.arrowUp, size: 18),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter({
    required PlayraTokens tokens,
    required bool isLoading,
    required bool isFailed,
    required bool hasMore,
    required int totalCount,
  }) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PlayraSpace.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: PlayraSpinner(),
            ),
            const SizedBox(width: PlayraSpace.sm),
            Text(
              '正在加载更多作品…',
              style: TextStyle(
                color: tokens.foregroundMuted,
                fontSize: PlayraType.caption,
              ),
            ),
          ],
        ),
      );
    }

    if (isFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PlayraSpace.sm),
        child: PlayraButton.ghost(
          onPressed: _triggerLoadMore,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.refreshCw, size: 14),
              SizedBox(width: PlayraSpace.xs),
              Text('加载失败，点击重试'),
            ],
          ),
        ),
      );
    }

    if (!hasMore && totalCount > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PlayraSpace.md),
        child: Text(
          '— 已经到底了 · 共 $totalCount 部作品 —',
          style: TextStyle(
            color: tokens.foregroundMuted.withValues(alpha: 0.6),
            fontSize: PlayraType.caption,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 分类列表页专属海报卡片
///
/// 具备高帧率悬浮缩放动效、完整暗黑毛玻璃边框质感、状态徽章、评分标签以及多行标题截断。
class _CategoryPosterCard extends StatefulWidget {
  const _CategoryPosterCard({
    super.key,
    required this.item,
    required this.controller,
    required this.cardWidth,
    required this.onTap,
  });

  final HomeAnimeCard item;
  final ModernHomeController controller;
  final double cardWidth;
  final VoidCallback onTap;

  @override
  State<_CategoryPosterCard> createState() => _CategoryPosterCardState();
}

class _CategoryPosterCardState extends State<_CategoryPosterCard> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _requestSchedule();
  }

  @override
  void didUpdateWidget(covariant _CategoryPosterCard oldWidget) {
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
  Widget build(BuildContext context) {
    final metadata = widget.item.metadata;
    if (metadata == null) {
      return _buildCard(context);
    }
    return ListenableBuilder(
      listenable: widget.controller.scheduleChanges(metadata.id),
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    final item = widget.item;
    final posterHeight = widget.cardWidth * 1.42;

    final airing = item.metadata == null
        ? item.status
        : widget.controller.scheduleLabel(item.metadata!);

    return Semantics(
      label: '查看 ${item.title}，${item.subtitle.isNotEmpty ? '${item.subtitle}，' : ''}$airing',
      button: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: PlayraCard(
        kind: PlayraCardKind.poster,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(PlayraRadius.poster),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PlayraRadius.poster),
                child: SizedBox(
                  width: widget.cardWidth,
                  height: posterHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MouseRegion(
                        onEnter: (_) => setState(() => _hovered = true),
                        onExit: (_) => setState(() => _hovered = false),
                        child: AnimatedScale(
                          scale: _hovered ? 1.04 : 1.0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: NetworkImgLayer(
                            src: item.cover,
                            fallbackTitle: item.title,
                            width: widget.cardWidth,
                            height: posterHeight,
                            type: 'bg',
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      // 底部暗色渐变，增强状态字样可读性
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: posterHeight * 0.4,
                        child: const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0x75000000),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 左上角评分标签
                      if (item.ratingScore > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PlayraSpace.compact,
                              vertical: 4,
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
                              style: TextStyle(
                                color: tokens.warningContainer,
                                fontSize: PlayraType.micro,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      // 右下角连载/完结状态
                      if (airing.isNotEmpty)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          left: 6,
                          child: IgnorePointer(
                            child: Text(
                              airing,
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: PlayraType.micro,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: PlayraSpace.sm),
              // 标题：最多两行，保持精致排版
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: PlayraType.label,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              // 副标题（年份/地区/分类标签）
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: PlayraSpace.tiny),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: PlayraType.micro,
                    color: tokens.foregroundMuted,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
