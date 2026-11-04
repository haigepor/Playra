import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:forui/forui.dart' as f;
import 'package:kazumi/presentation/widgets/playra_card.dart';
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

/// 推荐轮播只切换展示，不触发请求；后台、离屏和用户操作时暂停。
class ModernFeatureCarousel extends StatefulWidget {
  const ModernFeatureCarousel({super.key, required this.entries});
  final List<ModernFeatureEntry> entries;

  static double heightFor(BuildContext context) {
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return (compact ? 216.0 : 236.0) + 120 * (scale - 1).clamp(0, 3);
  }

  @override
  State<ModernFeatureCarousel> createState() => _ModernFeatureCarouselState();
}

class _ModernFeatureCarouselState extends State<ModernFeatureCarousel>
    with WidgetsBindingObserver {
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;
  bool _hover = false, _focus = false, _touch = false;
  bool _foreground = true;
  bool get _reduce =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(ModernFeatureCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.map((e) => e.id).join('|') !=
        widget.entries.map((e) => e.id).join('|')) {
      final previous = oldWidget.entries.isEmpty
          ? null
          : oldWidget.entries[_index.clamp(0, oldWidget.entries.length - 1)].id;
      final retained = widget.entries.indexWhere(
        (entry) => entry.id == previous,
      );
      _index = retained >= 0 ? retained : 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  bool get _canAuto =>
      widget.entries.length > 1 &&
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
      // 页面可能仍在导航栈或滚动缓存中，只有可见推荐区才自动推进。
      final box = context.findRenderObject();
      final visible =
          box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).overlaps(
            Offset.zero & MediaQuery.sizeOf(context),
          );
      if (_canAuto && visible && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _go((_index + 1) % widget.entries.length);
      } else {
        _schedule();
      }
    });
  }

  void _go(int index) {
    if (!_pages.hasClients) return;
    if (((_pages.page ?? _index.toDouble()) - index).abs() < .001) {
      _schedule();
      return;
    }
    if (_reduce) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final compact = isCompactModernViewport(MediaQuery.sizeOf(context));
    return Focus(
      onFocusChange: (value) {
        _focus = value;
        _schedule();
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
        child: Listener(
          onPointerDown: (_) {
            _touch = true;
            _schedule();
          },
          onPointerUp: (_) {
            _touch = false;
            _schedule();
          },
          onPointerCancel: (_) {
            _touch = false;
            _schedule();
          },
          child: SizedBox(
            height: ModernFeatureCarousel.heightFor(context),
            child: PlayraCard(
              kind: PlayraCardKind.hero,
              padding: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final footer = widget.entries.length > 1 ? 40.0 : 0.0;
                  final coverWidth = math.min(
                    math.min(bounds.maxWidth * .3, compact ? 104.0 : 124.0),
                    (bounds.maxHeight - footer - PlayraSpace.section) / 1.42,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        bottom: footer,
                        child: PageView.builder(
                          controller: _pages,
                          dragStartBehavior: DragStartBehavior.down,
                          itemCount: widget.entries.length,
                          onPageChanged: (index) {
                            setState(() => _index = index);
                            _schedule();
                          },
                          itemBuilder: (_, index) => _FeatureSlide(
                            entry: widget.entries[index],
                            coverWidth: coverWidth,
                            compact: compact,
                          ),
                        ),
                      ),
                      if (widget.entries.length > 1)
                        Positioned(
                          left: PlayraSpace.lg,
                          right: PlayraSpace.lg,
                          bottom: 0,
                          height: footer,
                          child: Center(
                            child: _pagination(
                              context,
                              math.min(
                                bounds.maxWidth - PlayraSpace.section,
                                widget.entries.length * 20.0 + 12,
                              ),
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
    );
  }

  Widget _pagination(BuildContext context, double width) {
    final colors = Theme.of(context).colorScheme;
    const inset = 6.0;
    final step = (width - inset * 2) / widget.entries.length;
    return SizedBox(
      width: width,
      height: 40,
      child: AnimatedBuilder(
        animation: _pages,
        builder: (context, _) {
          final page = _reduce
              ? _index.toDouble()
              : (_pages.hasClients && _pages.position.hasContentDimensions
                    ? _pages.page ?? _index.toDouble()
                    : _index.toDouble());
          final position = page.clamp(
            0.0,
            (widget.entries.length - 1).toDouble(),
          );
          final stretch = _reduce
              ? 0.0
              : math.sin((position % 1) * math.pi) * 4;
          final markerWidth = math.min(12 + stretch, step);
          return Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: f.FBadge.raw(
                  variant: f.FBadgeVariant.secondary,
                  builder: (_, _) => SizedBox(width: width, height: 24),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: inset),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.entries.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == _index,
                          label: '切换到第 ${i + 1} 张推荐',
                          child: f.FTappable(
                            key: ValueKey('feature-indicator-$i'),
                            onPress: () => _go(i),
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: .45,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox(width: 4, height: 4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PositionedDirectional(
                start: inset + position * step + (step - markerWidth) / 2,
                top: 18,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('feature-carousel-active-indicator'),
                    width: markerWidth,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  const _FeatureSlide({
    required this.entry,
    required this.coverWidth,
    required this.compact,
  });
  final ModernFeatureEntry entry;
  final double coverWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(PlayraSpace.lg),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              f.FBadge(
                variant: f.FBadgeVariant.secondary,
                style: const f.FBadgeStyleDelta.delta(
                  padding: f.EdgeInsetsGeometryDelta.value(
                    EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 12),
                    SizedBox(width: PlayraSpace.xs),
                    Text('精选推荐', style: TextStyle(fontSize: PlayraType.small)),
                  ],
                ),
              ),
              const SizedBox(height: PlayraSpace.sm),
              f.FTappable(
                onPress: entry.onTap,
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: compact ? PlayraType.section : PlayraType.title,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (entry.subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: PlayraSpace.xs),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              f.FButton(
                onPress: entry.onTap,
                variant: f.FButtonVariant.outline,
                size: f.FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                suffix: const Icon(Icons.arrow_forward_rounded, size: 14),
                child: const Text(
                  '查看详情',
                  style: TextStyle(fontSize: PlayraType.caption),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: PlayraSpace.md),
        Semantics(
          button: true,
          label: '查看 ${entry.title}',
          child: f.FTappable(
            onPress: entry.onTap,
            child: PlayraCard(
              kind: PlayraCardKind.poster,
              padding: EdgeInsets.zero,
              width: coverWidth,
              height: coverWidth * 1.42,
              child: NetworkImgLayer(
                src: entry.cover,
                type: entry.imageType,
                width: coverWidth,
                height: coverWidth * 1.42,
                borderRadius: BorderRadius.circular(PlayraRadius.poster),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
