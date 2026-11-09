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

/// A single horizontal feature shelf, sized from the current content pane.
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
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
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
              final cardWidth = math.max(1.0, availableWidth);
              final cardHeight = availableHeight - (compact ? 6.0 : 8.0);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: (d) =>
                    _onHorizontalDragUpdate(d, cardWidth),
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

    final stepX = cardWidth + PlayraSpace.md;

    return ClipRect(
      child: Stack(
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
      ),
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
    const scale = 1.0;
    // 横向位移
    final offsetX = data.diff * stepX;
    const opacity = 1.0;

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
    required this.onCardTap,
  });
  final ModernFeatureEntry entry;
  final double cardWidth, cardHeight;
  final bool compact;
  final VoidCallback onCardTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(PlayraRadius.card),
    child: Material(
      color: PlayraMedia.canvas,
      child: InkWell(
        onTap: onCardTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entry.cover.isNotEmpty)
              NetworkImgLayer(
                src: entry.cover,
                type: 'bg',
                width: cardWidth,
                height: cardHeight,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.zero,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    PlayraMedia.canvas,
                    PlayraMedia.scrimMedium,
                    PlayraMedia.scrimSoft,
                  ],
                  stops: [0, .65, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(PlayraSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    '精选推荐',
                    style: TextStyle(
                      fontSize: PlayraType.caption,
                      color: PlayraMedia.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: PlayraSpace.xs),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact
                          ? PlayraType.section
                          : PlayraType.pageTitle,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: PlayraMedia.foreground,
                    ),
                  ),
                  if (entry.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: PlayraSpace.xs),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: PlayraType.caption,
                        color: PlayraMedia.foregroundMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: PlayraSpace.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PlayraButton(
                      onPressed: onCardTap,
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        size: PlayraLayout.compactIcon,
                      ),
                      child: const Text('查看详情'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
