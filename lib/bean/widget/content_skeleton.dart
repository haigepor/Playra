import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

PulseEffect _contentEffect(BuildContext context, {bool animate = true}) {
  final colors = Theme.of(context).colorScheme;
  return PulseEffect(
    from: Color.lerp(colors.surface, colors.onSurface, .055)!,
    to: Color.lerp(colors.surface, colors.onSurface, .095)!,
    duration: !animate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1800),
  );
}

/// 让已有评论、人物资料的 Bone 也继承同一配色与动画设置。
class ContentSkeletonTheme extends StatelessWidget {
  const ContentSkeletonTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SkeletonizerConfig(
    data: SkeletonizerConfigData(effect: _contentEffect(context)),
    child: child,
  );
}

/// 只绘制内容轮廓，不创建假作品或触发真实业务操作。
class ContentSkeleton extends StatelessWidget {
  const ContentSkeleton({super.key, required this.child, this.animate = true});
  final Widget child;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '正在加载内容',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: IgnorePointer(
            child: Skeletonizer.zone(
              effect: _contentEffect(context, animate: animate),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class SkeletonPosterCard extends StatelessWidget {
  const SkeletonPosterCard({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Bone(
          width: bounds.maxWidth,
          height: bounds.maxWidth * 1.42,
          uniRadius: 12,
        ),
        const SizedBox(height: 8),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: .82,
          child: Bone(
            height: MediaQuery.textScalerOf(context).scale(13),
            uniRadius: 4,
          ),
        ),
        const SizedBox(height: 6),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: .5,
          child: Bone(
            height: MediaQuery.textScalerOf(context).scale(10),
            uniRadius: 3,
          ),
        ),
      ],
    ),
  );
}

class SkeletonPosters extends StatelessWidget {
  const SkeletonPosters({
    super.key,
    this.horizontal = true,
    this.count = 4,
    this.gridDelegate,
    this.infoExtent = 48,
  });
  final bool horizontal;
  final int count;
  final SliverGridDelegate? gridDelegate;
  final double infoExtent;
  @override
  Widget build(BuildContext context) => ContentSkeleton(
    key: const ValueKey('content-skeleton-posters'),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        if (horizontal) {
          final width = (bounds.maxWidth / 3.1 - 8).clamp(104.0, 144.0);
          return SizedBox(
            height: width * 1.42 + infoExtent * scale,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) =>
                  SizedBox(width: width, child: const SkeletonPosterCard()),
            ),
          );
        }
        final columns = (bounds.maxWidth / (116 * scale)).floor().clamp(2, 6);
        final width = (bounds.maxWidth - 12 * (columns - 1)) / columns;
        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate:
              gridDelegate ??
              SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                mainAxisExtent: width * 1.42 + infoExtent * scale,
              ),
          itemBuilder: (_, _) => const SkeletonPosterCard(),
        );
      },
    ),
  );
}

class SkeletonFeature extends StatelessWidget {
  const SkeletonFeature({super.key, this.height = 176, this.bento = false});
  final double height;
  final bool bento;
  @override
  Widget build(BuildContext context) => ContentSkeleton(
    key: const ValueKey('content-skeleton-feature'),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (bento) {
          final columns = bounds.maxWidth >= 320 && scale <= 1.3 ? 2 : 1;
          final rowHeight = columns == 1
              ? 140.0 + 64 * (scale - 1).clamp(0, 3)
              : ((bounds.maxWidth - 10) / 2 * .75).clamp(124.0, 152.0);
          return Column(
            children: [
              for (var i = 0; i < 4 ~/ columns; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: rowHeight,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Bone(
                                width: (bounds.maxWidth - 10) / columns * .36,
                                height: rowHeight - 16,
                                uniRadius: 9,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(height: 6),
                                    Bone(height: 12, uniRadius: 3),
                                    SizedBox(height: 8),
                                    Bone(height: 12, uniRadius: 3),
                                    Spacer(),
                                    FractionallySizedBox(
                                      widthFactor: .55,
                                      alignment: Alignment.centerLeft,
                                      child: Bone(height: 10, uniRadius: 3),
                                    ),
                                    SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Center(child: Bone(width: 88, height: 32, uniRadius: 16)),
            ],
          );
        }
        return Container(
          height: height,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: .4,
                          child: Bone(height: 10, uniRadius: 3),
                        ),
                        const SizedBox(height: 16),
                        const Bone(height: 18, uniRadius: 4),
                        const SizedBox(height: 8),
                        const FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: .7,
                          child: Bone(height: 12, uniRadius: 3),
                        ),
                      ],
                    ),
                    const Bone(width: 96, height: 36, uniRadius: 12),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Bone(
                width: math.min(bounds.maxWidth * .32, 116),
                height: height - 36,
                uniRadius: 12,
              ),
            ],
          ),
        );
      },
    ),
  );
}

class SkeletonInfoList extends StatelessWidget {
  const SkeletonInfoList({super.key, this.count = 4});
  final int count;
  @override
  Widget build(BuildContext context) => ContentSkeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Bone(width: 82, height: 122, uniRadius: 10),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Bone(height: 16, uniRadius: 4),
                        SizedBox(height: 12),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: .6,
                          child: Bone(height: 11, uniRadius: 3),
                        ),
                        SizedBox(height: 24),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: .45,
                          child: Bone(height: 28, uniRadius: 8),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class SkeletonEpisodes extends StatelessWidget {
  const SkeletonEpisodes({super.key});
  @override
  Widget build(BuildContext context) => ContentSkeleton(
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(
        8,
        (_) => const Bone(width: 60, height: 44, uniRadius: 10),
      ),
    ),
  );
}

class SkeletonComments extends StatelessWidget {
  const SkeletonComments({super.key});
  @override
  Widget build(BuildContext context) => ContentSkeleton(
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 32, height: 32, uniRadius: 16),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: .3,
                        child: Bone(height: 12, uniRadius: 3),
                      ),
                      SizedBox(height: 14),
                      Bone(height: 12, uniRadius: 3),
                      SizedBox(height: 8),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: .7,
                        child: Bone(height: 12, uniRadius: 3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
