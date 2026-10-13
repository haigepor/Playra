import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 固定尺寸的播放标记；暂停冻结，减少动画/后台不运行 ticker。
class MioPlayingMark extends StatefulWidget {
  const MioPlayingMark({super.key, required this.active, required this.color});
  final bool active;
  final Color color;
  @override
  State<MioPlayingMark> createState() => _MioPlayingMarkState();
}

class _MioPlayingMarkState extends State<MioPlayingMark>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _sync() {
    final media = MediaQuery.maybeOf(context);
    final enabled =
        widget.active &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);
    if (enabled) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MioPlayingMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.active ? '正在播放' : '当前集',
    child: RepaintBoundary(
      child: SizedBox(
        width: 14,
        height: 14,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (_, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              3,
              (i) => Container(
                key: ValueKey('mio-playing-bar-$i'),
                width: 3,
                height:
                    4 +
                    9 *
                        (.5 +
                            .5 *
                                math.sin(
                                  _motion.value * math.pi * 2 + i * 2.1,
                                )),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
