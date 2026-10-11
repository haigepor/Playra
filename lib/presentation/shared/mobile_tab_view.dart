import 'package:flutter/material.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';

/// 点击主 Tab 时横移内容，缓存已访问的页面，不参与内部横向手势竞争。
class MobileTabView extends StatefulWidget {
  const MobileTabView({
    super.key,
    required this.selectedIndex,
    required this.pageBuilders,
    required this.isCovered,
  });

  final int selectedIndex;
  final List<WidgetBuilder> pageBuilders;
  final bool isCovered;

  @override
  State<MobileTabView> createState() => _MobileTabViewState();
}

class _MobileTabViewState extends State<MobileTabView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addStatusListener(_settled);
  late final Set<int> _visited = {widget.selectedIndex};
  // 缓存 Widget 实例，避免每个动画帧重建整页列表；页面自己的状态仍正常更新。
  late final Map<int, Widget> _pages = {
    widget.selectedIndex: Builder(
      builder: widget.pageBuilders[widget.selectedIndex],
    ),
  };
  late Map<int, double> _from = {widget.selectedIndex: 0};
  late Map<int, double> _to = {widget.selectedIndex: 0};

  double _offset(int index) {
    final progress = Curves.easeOutCubic.transform(_motion.value);
    final from = _from[index] ?? 0;
    return from + ((_to[index] ?? from) - from) * progress;
  }

  @override
  void didUpdateWidget(covariant MobileTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    final target = widget.selectedIndex;
    final direction = target > oldWidget.selectedIndex ? 1.0 : -1.0;
    // 快速反向切换从当前绘制位置接续，不能先回到旧动画的起点。
    final positions = {for (final index in _from.keys) index: _offset(index)};
    _motion.stop();
    positions.putIfAbsent(target, () => direction);
    _visited.add(target);
    _pages.putIfAbsent(
      target,
      () => Builder(builder: widget.pageBuilders[target]),
    );
    _from = positions;
    _to = {
      for (final index in positions.keys)
        index: index == target ? 0 : -direction,
    };
    if (MediaQuery.disableAnimationsOf(context)) {
      _from = {target: 0};
      _to = {target: 0};
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  void _settled(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    // 清理离开页的绘制位置，但保留其 Element、输入和滚动状态。
    setState(() {
      _from = {widget.selectedIndex: 0};
      _to = {widget.selectedIndex: 0};
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          // 当前页最后绘制，动画中只有它可以点击、聚焦和被读屏访问。
          for (final index in [
            ..._visited.where((i) => i != widget.selectedIndex),
            widget.selectedIndex,
          ])
            Positioned.fill(
              key: ValueKey(index),
              child: Offstage(
                offstage: !_from.containsKey(index),
                child: FractionalTranslation(
                  translation: Offset(_offset(index), 0),
                  child: RouteVisibility(
                    isCovered:
                        widget.isCovered || index != widget.selectedIndex,
                    child: TickerMode(
                      enabled:
                          !widget.isCovered && index == widget.selectedIndex,
                      child: ExcludeFocus(
                        excluding:
                            widget.isCovered || index != widget.selectedIndex,
                        child: ExcludeSemantics(
                          excluding:
                              widget.isCovered || index != widget.selectedIndex,
                          child: IgnorePointer(
                            ignoring:
                                widget.isCovered ||
                                index != widget.selectedIndex,
                            child: _pages[index]!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
