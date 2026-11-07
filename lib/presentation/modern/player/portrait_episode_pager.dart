/// 竖屏全屏的分集翻页（抖音式）：上下滑动按页吸附，一页一集。
///
/// 当前播放页嵌真实播放器表面（GlobalKey 复用，翻页不重建播放状态）；
/// 相邻页是封面占位，翻页落定才请求播放 —— 播放失败时页码回弹到
/// 仍在播放的那一集（currentIndex 不变，didUpdateWidget 会拉回来）。
library;

import 'package:flutter/material.dart';

class PortraitEpisodePager extends StatefulWidget {
  const PortraitEpisodePager({
    super.key,
    required this.currentIndex,
    required this.itemCount,
    required this.titleFor,
    required this.coverFor,
    required this.surfaceBuilder,
    required this.onPageSelected,
  });

  /// 当前正在播放的分集下标（0 起）；未知时为 -1，翻页器停在原地等待。
  final int currentIndex;
  final int itemCount;

  /// 占位页文案（分集名）与封面。
  final String Function(int index) titleFor;
  final String Function(int index) coverFor;

  /// 播放器表面：只挂在 [currentIndex] 对应的页上。
  final Widget Function() surfaceBuilder;

  /// 用户翻页落定后请求播放目标集。
  final ValueChanged<int> onPageSelected;

  @override
  State<PortraitEpisodePager> createState() => _PortraitEpisodePagerState();
}

class _PortraitEpisodePagerState extends State<PortraitEpisodePager> {
  late PageController _controller = PageController(
    initialPage: widget.currentIndex.clamp(0, widget.itemCount - 1),
  );

  @override
  void didUpdateWidget(covariant PortraitEpisodePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final page = _controller.hasClients ? _controller.page?.round() : null;
    // 播放状态变化（自动连播/选集面板/播放失败回弹）驱动页码对齐。
    if (widget.currentIndex != page &&
        widget.currentIndex >= 0 &&
        widget.currentIndex < widget.itemCount) {
      _controller.animateToPage(
        widget.currentIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      itemCount: widget.itemCount,
      // 预建相邻页，翻页时占位封面已就绪。
      allowImplicitScrolling: true,
      onPageChanged: (index) {
        if (index != widget.currentIndex) {
          widget.onPageSelected(index);
        }
      },
      itemBuilder: (context, index) =>
          index == widget.currentIndex
          ? widget.surfaceBuilder()
          : _PlaceholderPage(
              title: widget.titleFor(index),
              cover: widget.coverFor(index),
            ),
    );
  }
}

/// 邻页占位：黑底 + 居中封面 + 分集名；落定后由播放器页接管。
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.cover});

  final String title;
  final String cover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cover.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  cover,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_fill_rounded,
                  size: 20, color: colors.onSurface.withValues(alpha: 0.8)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.9),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
