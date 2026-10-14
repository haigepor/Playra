import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

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
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(0);
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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
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
          child: Container(
            height: 206 + 115 * (scale - 1).clamp(0, 3),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xff222e50),
              borderRadius: BorderRadius.circular(20),
            ),
            child: LayoutBuilder(
              builder: (context, bounds) {
                // 视觉指示线与命中区分开；六项在小屏也保留独立的可点击宽度。
                final coverWidth = math.min(
                  math.min((bounds.maxWidth - 36) * .34, 116.0),
                  (bounds.maxHeight - 66) / 1.42,
                );
                final trackWidth = math.min(
                  bounds.maxWidth - 36,
                  widget.entries.length * 26.0,
                );
                final step = trackWidth / widget.entries.length;
                final indicatorBottom =
                    10 + (bounds.maxHeight - 28 - (coverWidth * 1.42 + 38)) / 2;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: SvgPicture.asset(
                          'assets/images/modern-feature-orbit.svg',
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: widget.entries.length,
                        onPageChanged: (index) {
                          setState(() => _index = index);
                          _schedule();
                        },
                        itemBuilder: (_, index) => _FeatureSlide(
                          entry: widget.entries[index],
                          coverWidth: coverWidth,
                        ),
                      ),
                    ),
                    if (widget.entries.length > 1)
                      Positioned(
                        right: math.max(
                          12,
                          18 + (coverWidth + 6 - trackWidth) / 2,
                        ),
                        width: trackWidth,
                        bottom: indicatorBottom - 4,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: trackWidth,
                            height: 40,
                            child: AnimatedBuilder(
                              animation: _pages,
                              builder: (context, _) {
                                // 跟随真实滚动位置，手势中途也连续移动；减少动画时直接定位。
                                final page = _reduce
                                    ? _index.toDouble()
                                    : (_pages.hasClients &&
                                              _pages
                                                  .position
                                                  .hasContentDimensions
                                          ? _pages.page ?? _index.toDouble()
                                          : _index.toDouble());
                                final position = page.clamp(
                                  0.0,
                                  (widget.entries.length - 1).toDouble(),
                                );
                                final stretch = _reduce
                                    ? 0.0
                                    : math.sin((position % 1) * math.pi) * 4;
                                final markerWidth = math.min(
                                  12 + stretch,
                                  step,
                                );
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < widget.entries.length;
                                          i++
                                        )
                                          Semantics(
                                            button: true,
                                            selected: i == _index,
                                            label: '切换到第 ${i + 1} 张推荐',
                                            child: InkWell(
                                              key: ValueKey(
                                                'feature-indicator-$i',
                                              ),
                                              onTap: () => _go(i),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: SizedBox(
                                                width: step,
                                                height: 40,
                                                child: const Center(
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      color: Color(0xff65708f),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: SizedBox(
                                                      width: 3,
                                                      height: 3,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    PositionedDirectional(
                                      start:
                                          position * step +
                                          (step - markerWidth) / 2,
                                      top: 18.5,
                                      child: IgnorePointer(
                                        child: Container(
                                          key: const ValueKey(
                                            'feature-carousel-active-indicator',
                                          ),
                                          width: markerWidth,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: const Color(0xffc1cdff),
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  const _FeatureSlide({required this.entry, required this.coverWidth});
  final ModernFeatureEntry entry;
  final double coverWidth;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
    child: LayoutBuilder(
      builder: (context, bounds) {
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 14,
                        color: Color(0xffc1cdff),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '精选推荐',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xffc1cdff),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffedf0f8),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    entry.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: Color(0xffbdc8e3),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: entry.onTap,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    iconAlignment: IconAlignment.end,
                    label: const Text('查看详情', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffedf0ff),
                      foregroundColor: const Color(0xff243153),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: '查看 ${entry.title}',
                  child: InkWell(
                    onTap: entry.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Transform.rotate(
                      angle: .045,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xff536080),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xff687698)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: NetworkImgLayer(
                            src: entry.cover,
                            type: entry.imageType,
                            width: coverWidth,
                            height: coverWidth * 1.42,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ],
        );
      },
    ),
  );
}
