import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';

/// Unified segmented capsule tab bar (Scheme B: outer pill track + elevated
/// sliding thumb) synchronized 1:1 with a [TabController].
///
/// By default [expand] is `true`, stretching the track to the available width
/// with evenly adaptive segments (automatically falling back to horizontal
/// scrolling under large accessibility text scales).
class PlayraSegmentedTabBar extends StatefulWidget {
  const PlayraSegmentedTabBar({
    super.key,
    required this.labels,
    this.controller,
    this.initialIndex = 0,
    this.onTap,
    this.horizontalPadding = 0,
    this.verticalPadding = 6,
    this.expand = true,
    this.center = false,
  });

  final List<String> labels;
  final TabController? controller;
  final int initialIndex;
  final ValueChanged<int>? onTap;
  final double horizontalPadding;
  final double verticalPadding;
  final bool expand;
  final bool center;

  @override
  State<PlayraSegmentedTabBar> createState() => _PlayraSegmentedTabBarState();
}

class _PlayraSegmentedTabBarState extends State<PlayraSegmentedTabBar>
    with SingleTickerProviderStateMixin {
  static const double _trackPadding = 3.0;

  TabController? _ownedController;
  TabController? _activeController;
  final GlobalKey _trackKey = GlobalKey();
  late List<GlobalKey> _tabKeys;
  List<({double left, double width})> _metrics = const [];
  int _lastIndex = 0;
  double? _lastLayoutWidth;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(widget.labels.length, (_) => GlobalKey());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant PlayraSegmentedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _tabKeys = List.generate(widget.labels.length, (_) => GlobalKey());
      _metrics = const [];
    }
    _syncController();
    _scheduleMeasure();
  }

  void _syncController() {
    final external = widget.controller ?? DefaultTabController.maybeOf(context);
    TabController resolved;
    if (external != null) {
      _ownedController?.dispose();
      _ownedController = null;
      resolved = external;
    } else {
      if (_ownedController == null ||
          _ownedController!.length != widget.labels.length) {
        _ownedController?.dispose();
        final safeIndex = widget.labels.isEmpty
            ? 0
            : widget.initialIndex.clamp(0, widget.labels.length - 1);
        _ownedController = TabController(
          length: widget.labels.length,
          initialIndex: safeIndex,
          vsync: this,
        );
      }
      resolved = _ownedController!;
    }
    if (!identical(_activeController, resolved)) {
      _activeController?.removeListener(_onControllerTick);
      _activeController = resolved;
      _lastIndex = resolved.index;
      resolved.addListener(_onControllerTick);
    }
    _scheduleMeasure();
  }

  void _onControllerTick() {
    final controller = _activeController;
    if (controller == null) return;
    if (controller.index != _lastIndex) {
      _lastIndex = controller.index;
      _scheduleMeasure();
      _scrollTabIntoView(_lastIndex);
    }
  }

  void _scrollTabIntoView(int index) {
    if (index < 0 || index >= _tabKeys.length) return;
    final ctx = _tabKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final trackBox =
          _trackKey.currentContext?.findRenderObject() as RenderBox?;
      if (trackBox == null || !trackBox.hasSize) return;
      final next = <({double left, double width})>[];
      for (final key in _tabKeys) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final offset = box.localToGlobal(Offset.zero, ancestor: trackBox);
        next.add((left: offset.dx, width: box.size.width));
      }
      if (next.length != _metrics.length || _metricsChanged(next)) {
        setState(() => _metrics = next);
      }
    });
  }

  bool _metricsChanged(List<({double left, double width})> next) {
    for (var i = 0; i < next.length; i++) {
      if ((next[i].left - _metrics[i].left).abs() > 0.25 ||
          (next[i].width - _metrics[i].width).abs() > 0.25) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _activeController?.removeListener(_onControllerTick);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _activeController;
    if (controller == null || widget.labels.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    final pillHeight = math.max(30.0, scaler.scale(13) * 1.2 + 12);
    final trackRadius = BorderRadius.circular(
      (pillHeight + _trackPadding * 2) / 2,
    );
    final pillRadius = BorderRadius.circular(pillHeight / 2);

    final trackColor = isDark
        ? const Color(0xFF151A24)
        : const Color(0xFFECE8F5);
    final trackBorder = t.accent.withValues(alpha: 0.14);

    final thumbDecoration = BoxDecoration(
      gradient: isDark
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3B2F5C), Color(0xFF2D2348)],
            )
          : null,
      color: isDark ? null : Colors.white,
      borderRadius: pillRadius,
      border: Border.all(
        color: t.accent.withValues(alpha: isDark ? 0.28 : 0.16),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? const Color(0x73000000) : const Color(0x1A16121F),
          blurRadius: isDark ? 8 : 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (_lastLayoutWidth != maxWidth) {
          _lastLayoutWidth = maxWidth;
          _scheduleMeasure();
        }
        final innerWidth = maxWidth.isFinite
            ? math.max(0.0, maxWidth - widget.horizontalPadding * 2)
            : 0.0;
        final minPerSegment = scaler.scale(13) * 2.8 + 16;
        final shouldExpand =
            widget.expand &&
            maxWidth.isFinite &&
            innerWidth >= widget.labels.length * minPerSegment;

        final track = AnimatedBuilder(
          animation: controller.animation ?? controller,
          builder: (context, _) {
            final animValue =
                (controller.animation?.value ?? controller.index.toDouble())
                    .clamp(0.0, (widget.labels.length - 1).toDouble());
            final lower = animValue.floor();
            final upper = animValue.ceil();
            final frac = animValue - lower;
            final hasMetrics = _metrics.length == widget.labels.length;

            double? sliderLeft;
            double? sliderWidth;
            if (hasMetrics) {
              sliderLeft = lerpDouble(
                _metrics[lower].left,
                _metrics[upper].left,
                frac,
              );
              sliderWidth = lerpDouble(
                _metrics[lower].width,
                _metrics[upper].width,
                frac,
              );
            }

            Widget buildTabButton(int i) => _SegmentedTabButton(
              key: _tabKeys[i],
              label: widget.labels[i],
              height: pillHeight,
              radius: pillRadius,
              selected: controller.index == i,
              selectionT: (1.0 - (animValue - i).abs()).clamp(0.0, 1.0),
              fallbackDecoration: !hasMetrics && controller.index == i
                  ? thumbDecoration
                  : null,
              activeColor: t.accent,
              inactiveColor: t.textSecondary,
              pressTint: t.accent.withValues(alpha: 0.14),
              horizontalPadding: shouldExpand ? 6 : 13,
              onTap: () {
                if (controller.index != i) {
                  controller.animateTo(
                    i,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                  );
                }
                widget.onTap?.call(i);
              },
            );

            return Container(
              key: _trackKey,
              width: shouldExpand ? double.infinity : null,
              padding: const EdgeInsets.all(_trackPadding),
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: trackRadius,
                border: Border.all(color: trackBorder, width: 1),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (sliderLeft != null && sliderWidth != null)
                    Positioned(
                      left: sliderLeft - _trackPadding,
                      top: 0,
                      width: sliderWidth,
                      height: pillHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(decoration: thumbDecoration),
                      ),
                    ),
                  Row(
                    mainAxisSize: shouldExpand
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.labels.length; i++)
                        shouldExpand
                            ? Expanded(child: buildTabButton(i))
                            : buildTabButton(i),
                    ],
                  ),
                ],
              ),
            );
          },
        );

        if (shouldExpand) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.horizontalPadding,
              vertical: widget.verticalPadding,
            ),
            child: track,
          );
        }

        final scrollView = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: widget.horizontalPadding,
            vertical: widget.verticalPadding,
          ),
          child: track,
        );

        if (widget.center) return Center(child: scrollView);
        return Align(alignment: Alignment.centerLeft, child: scrollView);
      },
    );
  }
}

class _SegmentedTabButton extends StatelessWidget {
  const _SegmentedTabButton({
    super.key,
    required this.label,
    required this.height,
    required this.radius,
    required this.selected,
    required this.selectionT,
    required this.activeColor,
    required this.inactiveColor,
    required this.pressTint,
    required this.horizontalPadding,
    required this.onTap,
    this.fallbackDecoration,
  });

  final String label;
  final double height;
  final BorderRadius radius;
  final bool selected;
  final double selectionT;
  final Color activeColor;
  final Color inactiveColor;
  final Color pressTint;
  final double horizontalPadding;
  final VoidCallback onTap;
  final BoxDecoration? fallbackDecoration;

  @override
  Widget build(BuildContext context) {
    final textColor = Color.lerp(inactiveColor, activeColor, selectionT)!;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            decoration: fallbackDecoration,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: selectionT > 0.5
                    ? FontWeight.w700
                    : FontWeight.w500,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Editorial underline tab bar with a glowing bottom pill slider that glides
/// 1:1 with [TabController.animation] and elastically stretches mid-transition.
class PlayraUnderlineTabBar extends StatefulWidget {
  const PlayraUnderlineTabBar({
    super.key,
    required this.labels,
    this.controller,
    this.initialIndex = 0,
    this.onTap,
    this.horizontalPadding = 16,
    this.minHeight = 36.0,
    this.indicatorBottom = 2.0,
  });

  final List<String> labels;
  final TabController? controller;
  final int initialIndex;
  final ValueChanged<int>? onTap;
  final double horizontalPadding;
  final double minHeight;
  final double indicatorBottom;

  @override
  State<PlayraUnderlineTabBar> createState() => _PlayraUnderlineTabBarState();
}

class _PlayraUnderlineTabBarState extends State<PlayraUnderlineTabBar>
    with SingleTickerProviderStateMixin {
  TabController? _ownedController;
  TabController? _activeController;
  final GlobalKey _rowKey = GlobalKey();
  late List<GlobalKey> _tabKeys;
  List<({double centerX, double width})> _metrics = const [];
  int _lastIndex = 0;
  double? _lastLayoutWidth;

  @override
  void initState() {
    super.initState();
    _tabKeys = List.generate(widget.labels.length, (_) => GlobalKey());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant PlayraUnderlineTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels.length != widget.labels.length) {
      _tabKeys = List.generate(widget.labels.length, (_) => GlobalKey());
      _metrics = const [];
    }
    _syncController();
    _scheduleMeasure();
  }

  void _syncController() {
    final external = widget.controller ?? DefaultTabController.maybeOf(context);
    TabController resolved;
    if (external != null) {
      _ownedController?.dispose();
      _ownedController = null;
      resolved = external;
    } else {
      if (_ownedController == null ||
          _ownedController!.length != widget.labels.length) {
        _ownedController?.dispose();
        final safeIndex = widget.labels.isEmpty
            ? 0
            : widget.initialIndex.clamp(0, widget.labels.length - 1);
        _ownedController = TabController(
          length: widget.labels.length,
          initialIndex: safeIndex,
          vsync: this,
        );
      }
      resolved = _ownedController!;
    }
    if (!identical(_activeController, resolved)) {
      _activeController?.removeListener(_onControllerTick);
      _activeController = resolved;
      _lastIndex = resolved.index;
      resolved.addListener(_onControllerTick);
    }
    _scheduleMeasure();
  }

  void _onControllerTick() {
    final controller = _activeController;
    if (controller == null) return;
    if (controller.index != _lastIndex) {
      _lastIndex = controller.index;
      _scheduleMeasure();
      _scrollTabIntoView(_lastIndex);
    }
  }

  void _scrollTabIntoView(int index) {
    if (index < 0 || index >= _tabKeys.length) return;
    final ctx = _tabKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
      if (rowBox == null || !rowBox.hasSize) return;
      final next = <({double centerX, double width})>[];
      for (final key in _tabKeys) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final offset = box.localToGlobal(Offset.zero, ancestor: rowBox);
        next.add((
          centerX: offset.dx + box.size.width / 2,
          width: box.size.width,
        ));
      }
      if (next.length != _metrics.length || _metricsChanged(next)) {
        setState(() => _metrics = next);
      }
    });
  }

  bool _metricsChanged(List<({double centerX, double width})> next) {
    for (var i = 0; i < next.length; i++) {
      if ((next[i].centerX - _metrics[i].centerX).abs() > 0.25 ||
          (next[i].width - _metrics[i].width).abs() > 0.25) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _activeController?.removeListener(_onControllerTick);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _activeController;
    if (controller == null || widget.labels.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    final barHeight = math.max(
      widget.minHeight,
      scaler.scale(15) * 1.2 + 16,
    );

    final indicatorDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: isDark
            ? [t.accent, const Color(0xFF9B7BFF)]
            : [t.accent, const Color(0xFF8B5CF6)],
      ),
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: t.accent.withValues(alpha: isDark ? 0.5 : 0.35),
          blurRadius: 8,
          offset: const Offset(0, 1),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastLayoutWidth != constraints.maxWidth) {
          _lastLayoutWidth = constraints.maxWidth;
          _scheduleMeasure();
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
          child: AnimatedBuilder(
            animation: controller.animation ?? controller,
            builder: (context, _) {
              final animValue =
                  (controller.animation?.value ?? controller.index.toDouble())
                      .clamp(0.0, (widget.labels.length - 1).toDouble());
              final lower = animValue.floor();
              final upper = animValue.ceil();
              final frac = animValue - lower;
              final hasMetrics = _metrics.length == widget.labels.length;

              double? indicatorLeft;
              double? indicatorWidth;
              if (hasMetrics) {
                final centerX = lerpDouble(
                  _metrics[lower].centerX,
                  _metrics[upper].centerX,
                  frac,
                )!;
                final tabWidth = lerpDouble(
                  _metrics[lower].width,
                  _metrics[upper].width,
                  frac,
                )!;
                final baseWidth = (tabWidth * 0.44).clamp(18.0, 26.0);
                final stretch = math.sin(frac * math.pi) * 12.0;
                indicatorWidth = baseWidth + stretch;
                indicatorLeft = centerX - indicatorWidth / 2;
              }

              return SizedBox(
                height: barHeight,
                child: Stack(
                  key: _rowKey,
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.labels.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _UnderlineTabItem(
                            key: _tabKeys[i],
                            label: widget.labels[i],
                            selected: controller.index == i,
                            selectionT: (1.0 - (animValue - i).abs()).clamp(
                              0.0,
                              1.0,
                            ),
                            activeColor: t.textPrimary,
                            inactiveColor: t.textSecondary,
                            pressTint: t.accent.withValues(alpha: 0.12),
                            showFallbackBar:
                                !hasMetrics && controller.index == i,
                            indicatorBottom: widget.indicatorBottom,
                            indicatorDecoration: indicatorDecoration,
                            onTap: () {
                              if (controller.index != i) {
                                controller.animateTo(
                                  i,
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              widget.onTap?.call(i);
                            },
                          ),
                        ],
                      ],
                    ),
                    if (indicatorLeft != null && indicatorWidth != null)
                      Positioned(
                        left: indicatorLeft,
                        bottom: widget.indicatorBottom,
                        width: indicatorWidth,
                        height: 3,
                        child: IgnorePointer(
                          child: DecoratedBox(decoration: indicatorDecoration),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _UnderlineTabItem extends StatelessWidget {
  const _UnderlineTabItem({
    super.key,
    required this.label,
    required this.selected,
    required this.selectionT,
    required this.activeColor,
    required this.inactiveColor,
    required this.pressTint,
    required this.showFallbackBar,
    required this.indicatorBottom,
    required this.indicatorDecoration,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double selectionT;
  final Color activeColor;
  final Color inactiveColor;
  final Color pressTint;
  final bool showFallbackBar;
  final double indicatorBottom;
  final BoxDecoration indicatorDecoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Color.lerp(inactiveColor, activeColor, selectionT)!;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: indicatorBottom > 0 ? 3 : 2),
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontSize: selected ? 15.0 : 14.0,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.15,
                  ),
                ),
              ),
              if (showFallbackBar)
                Positioned(
                  bottom: indicatorBottom,
                  child: Container(
                    width: 20,
                    height: 3,
                    decoration: indicatorDecoration,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
