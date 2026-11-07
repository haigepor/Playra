import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import '../modern_layout.dart';

class ModernFeatureEntry {
  const ModernFeatureEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
    this.imageType = '',
  });
  final String id, title, subtitle, cover, imageType;
  final VoidCallback onTap;
}

/// 卡片叠层轮播图（Stacked Cards Carousel - 模式 A：居中景深层叠）
/// 主卡片居中高亮呈现，左右相邻卡片景深缩放与层级叠放，纯粹沉浸式展示，无底部冗余控制栏。
class ModernFeatureCarousel extends StatefulWidget {
  const ModernFeatureCarousel({super.key, required this.entries});
  final List<ModernFeatureEntry> entries;

  static double heightFor(BuildContext context) {
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return (compact ? 208.0 : 236.0) + 120 * (scale - 1).clamp(0, 3);
  }

  @override
  State<ModernFeatureCarousel> createState() => _ModernFeatureCarouselState();
}

class _ModernFeatureCarouselState extends State<ModernFeatureCarousel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animController;
  Animation<double>? _pageAnim;
  double _page = 0.0;
  int _index = 0;
  Timer? _timer;
  bool _hover = false, _focus = false, _touch = false;
  bool _foreground = true;
  double _dragStartX = 0.0;
  double _dragStartPage = 0.0;

  bool get _reduce =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _animController.addListener(() {
      if (_pageAnim != null) {
        setState(() {
          _page = _pageAnim!.value;
        });
      }
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final count = _entries.length;
        if (count > 0) {
          _page = (_page % count + count) % count;
          _index = _page.round() % count;
          setState(() {});
        }
        _schedule();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(ModernFeatureCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entries = _entries;
    final oldEntries = oldWidget.entries.take(6).toList();
    if (oldEntries.map((e) => e.id).join('|') !=
        entries.map((e) => e.id).join('|')) {
      final previous = oldEntries.isEmpty
          ? null
          : oldEntries[_index.clamp(0, oldEntries.length - 1)].id;
      final retained = entries.indexWhere((entry) => entry.id == previous);
      _index = retained >= 0 ? retained : 0;
      _page = _index.toDouble();
      setState(() {});
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  List<ModernFeatureEntry> get _entries => widget.entries.take(6).toList();

  bool get _canAuto =>
      _entries.length > 1 &&
      _foreground &&
      !_reduce &&
      !_hover &&
      !_focus &&
      !_touch &&
      TickerMode.valuesOf(context).enabled;

  void _schedule() {
    _timer?.cancel();
    if (!_canAuto) return;
    _timer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      final box = context.findRenderObject();
      final visible =
          box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).overlaps(
            Offset.zero & MediaQuery.sizeOf(context),
          );
      if (_canAuto && visible && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _animateTo((_index + 1) % _entries.length);
      } else {
        _schedule();
      }
    });
  }

  void _animateTo(int targetIndex) {
    final count = _entries.length;
    if (count <= 1) return;
    final normalized = (_page % count + count) % count;
    var delta = (targetIndex - normalized) % count;
    if (delta > count / 2) delta -= count;
    if (delta < -count / 2) delta += count;

    if (delta.abs() < 0.001) {
      _schedule();
      return;
    }

    _index = targetIndex % count;
    if (_reduce) {
      setState(() {
        _page = targetIndex.toDouble();
      });
      _schedule();
      return;
    }

    final start = _page;
    final end = _page + delta;
    _animController.stop();
    _pageAnim = Tween<double>(begin: start, end: end).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animController.forward(from: 0.0);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_entries.length <= 1) return;
    _touch = true;
    _timer?.cancel();
    _animController.stop();
    _dragStartX = details.localPosition.dx;
    _dragStartPage = _page;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double cardWidth) {
    if (_entries.length <= 1 || cardWidth <= 0) return;
    final dx = details.localPosition.dx - _dragStartX;
    setState(() {
      _page = _dragStartPage - (dx / (cardWidth * 0.82));
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _touch = false;
    final count = _entries.length;
    if (count <= 1) {
      _schedule();
      return;
    }

    final velocity = details.primaryVelocity ?? 0.0;
    int target;
    if (velocity < -300) {
      target = (_page.floor() + 1) % count;
    } else if (velocity > 300) {
      target = (_page.ceil() - 1 + count) % count;
    } else {
      target = (_page.round() % count + count) % count;
    }

    _animateTo(target);
  }

  double _diffFor(int index, double page, int count) {
    final normalizedPage = (page % count + count) % count;
    var diff = index - normalizedPage;
    while (diff > count / 2) {
      diff -= count;
    }
    while (diff < -count / 2) {
      diff += count;
    }
    return diff;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));

    return Focus(
      onFocusChange: (value) {
        _focus = value;
        _schedule();
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _animateTo((_index - 1 + entries.length) % entries.length);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _animateTo((_index + 1) % entries.length);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          _hover = true;
          _schedule();
        },
        onExit: (_) {
          _hover = false;
          _schedule();
        },
        child: SizedBox(
          height: ModernFeatureCarousel.heightFor(context),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final availableWidth = bounds.maxWidth;
              final availableHeight = bounds.maxHeight;
              final cardWidth = (availableWidth * (compact ? 0.88 : 0.62))
                  .clamp(310.0, 720.0);
              final cardHeight = availableHeight - (compact ? 6.0 : 8.0);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, cardWidth),
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Center(
                  child: SizedBox(
                    width: availableWidth,
                    height: cardHeight,
                    child: _buildCardStack(
                      context,
                      bounds: bounds,
                      cardWidth: cardWidth,
                      cardHeight: cardHeight,
                      compact: compact,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCardStack(
    BuildContext context, {
    required BoxConstraints bounds,
    required double cardWidth,
    required double cardHeight,
    required bool compact,
  }) {
    final entries = _entries;
    final count = entries.length;

    // 单张卡片时直接居中静态渲染
    if (count == 1) {
      return Center(
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: _FeatureCard(
            entry: entries.first,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            compact: compact,
            absD: 0.0,
            onCardTap: entries.first.onTap,
          ),
        ),
      );
    }

    // 多张卡片：计算每张卡片的循环相对偏移与层级
    final cardDataList = <_CardLayoutData>[];
    for (var i = 0; i < count; i++) {
      final diff = _diffFor(i, _page, count);
      // 过滤超出可视范围的背面卡片
      if (diff.abs() <= 2.2) {
        cardDataList.add(
          _CardLayoutData(index: i, diff: diff, entry: entries[i]),
        );
      }
    }

    // 核心叠层渲染规则：按距离绝对值从大到小排序（绝对值越大在底层，活跃卡片在最顶层）
    cardDataList.sort((a, b) => b.diff.abs().compareTo(a.diff.abs()));

    final stepX = compact ? cardWidth * 0.74 : cardWidth * 0.52;

    return Stack(
      alignment: Alignment.center,
      children: [
        for (final data in cardDataList)
          _buildTransformCard(
            context,
            data: data,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            stepX: stepX,
            compact: compact,
          ),
      ],
    );
  }

  Widget _buildTransformCard(
    BuildContext context, {
    required _CardLayoutData data,
    required double cardWidth,
    required double cardHeight,
    required double stepX,
    required bool compact,
  }) {
    final absD = data.diff.abs();
    // 景深缩放：当前卡片 1.0，侧边递减至 0.86 ~ 0.74
    final scale = (1.0 - 0.13 * math.min(absD, 2.0)).clamp(0.74, 1.0);
    // 横向位移
    final offsetX = data.diff * stepX;
    // 透明度过渡
    final opacity = (1.0 - 0.35 * math.min(absD, 2.0)).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(offsetX, 0),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: _FeatureCard(
              entry: data.entry,
              cardWidth: cardWidth,
              cardHeight: cardHeight,
              compact: compact,
              absD: absD,
              onCardTap: () {
                if (absD < 0.28) {
                  data.entry.onTap();
                } else if (data.diff > 0) {
                  _animateTo((_index + 1) % _entries.length);
                } else {
                  _animateTo((_index - 1 + _entries.length) % _entries.length);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CardLayoutData {
  const _CardLayoutData({
    required this.index,
    required this.diff,
    required this.entry,
  });
  final int index;
  final double diff;
  final ModernFeatureEntry entry;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.entry,
    required this.cardWidth,
    required this.cardHeight,
    required this.compact,
    required this.absD,
    required this.onCardTap,
  });

  final ModernFeatureEntry entry;
  final double cardWidth;
  final double cardHeight;
  final bool compact;
  final double absD;
  final VoidCallback onCardTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.playraTokens;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isActive = absD < 0.35;
    // 侧边卡片文字平滑淡出，避免露出截断文字
    final textOpacity = (1.0 - absD * 3.0).clamp(0.0, 1.0);

    final posterWidth = math.min(
      cardWidth * 0.24,
      (cardHeight - 32.0) / 1.42,
    ).clamp(88.0, 132.0);

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(PlayraRadius.card),
        border: Border.all(
          color: isActive
              ? Colors.white.withValues(alpha: 0.16)
              : tokens.borderSubtle.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isActive ? 0.60 : 0.32),
            blurRadius: isActive ? 26 : 14,
            offset: Offset(0, isActive ? 8 : 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PlayraRadius.card),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onCardTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. 沉浸式高清背景图（整卡完整铺底，两侧卡片均能看清画面）
                if (entry.cover.isNotEmpty)
                  Positioned.fill(
                    child: NetworkImgLayer(
                      src: entry.cover,
                      type: 'bg',
                      width: cardWidth,
                      height: cardHeight,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                // 2. 纵深暗色渐变蒙版（左深右透，保护主卡片文字对比度）
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          tokens.surface.withValues(alpha: 0.96),
                          tokens.surface.withValues(alpha: 0.88),
                          tokens.surface.withValues(alpha: 0.40),
                          tokens.surface.withValues(alpha: 0.15),
                        ],
                        stops: const [0.0, 0.42, 0.74, 1.0],
                      ),
                    ),
                  ),
                ),
                // 3. 卡片前景文字与交互区（中心主卡片才呈现，侧方卡片平滑淡出，绝不露出截断文字）
                if (textOpacity > 0.01)
                  Positioned.fill(
                    child: Opacity(
                      opacity: textOpacity,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? PlayraSpace.md : PlayraSpace.xl,
                          vertical: compact ? PlayraSpace.sm : PlayraSpace.md,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const PlayraBadge.secondary(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.auto_awesome_rounded, size: 12),
                                        SizedBox(width: PlayraSpace.xs),
                                        Text('精选推荐', style: TextStyle(fontSize: PlayraType.small)),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: compact ? PlayraSpace.xs : PlayraSpace.sm),
                                  Text(
                                    entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: compact ? PlayraType.section : 22.0,
                                      height: 1.25,
                                      fontWeight: FontWeight.w800,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  if (entry.subtitle.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: PlayraType.caption,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  // 标准化小胶囊按钮组
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PlayraButton(
                                        onPressed: onCardTap,
                                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                        child: const Text('立即播放'),
                                      ),
                                      const SizedBox(width: PlayraSpace.md),
                                      PlayraButton.outline(
                                        onPressed: onCardTap,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('详情'),
                                            SizedBox(width: 3),
                                            Icon(Icons.arrow_forward_ios_rounded, size: 10),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // 右侧微立体竖版海报（仅在大屏或足够宽度展示）
                            if (!compact) ...[
                              const SizedBox(width: PlayraSpace.lg),
                              Semantics(
                                button: true,
                                label: '查看 ${entry.title}',
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(PlayraRadius.poster),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.50),
                                        blurRadius: 16,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(PlayraRadius.poster),
                                    child: NetworkImgLayer(
                                      src: entry.cover,
                                      type: entry.imageType,
                                      width: posterWidth,
                                      height: posterWidth * 1.42,
                                      borderRadius: BorderRadius.circular(PlayraRadius.poster),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                // 4. 景深暗化层（侧方卡片稍微调暗）
                if (absD > 0.15)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(
                          alpha: (0.42 * math.min(absD, 1.5)).clamp(0.0, 0.55),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
