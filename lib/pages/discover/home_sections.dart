import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

/// Home shelf with a section heading and a horizontally scrolling poster rail.
///
/// Each shelf can expose the full feed list; users swipe horizontally instead
/// of opening the browse page for every extra item.
class HomeSectionGrid extends StatelessWidget {
  const HomeSectionGrid({
    super.key,
    required this.layout,
    required this.section,
    required this.onTap,
    this.onMore,
    this.moreLabel = '更多',
    this.showScore = false,
  });

  final HomeLayoutMetrics layout;
  final MediaSection section;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback? onMore;
  final String moreLabel;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final items = section.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: layout.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeadingRow(
            gutter: layout.gutter,
            title: section.title,
            moreLabel: moreLabel,
            onMore: onMore,
          ),
          const SizedBox(height: PlayraSpace.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final columns = scaler.scale(14) > 19 ? 2 : 3;
              final cardWidth = layout.isPhone
                  ? (constraints.maxWidth -
                            layout.gutter * 2 -
                            layout.cardGap * (columns - 1)) /
                        columns
                  : _sectionCardWidth(layout);
              final textHeight =
                  PlayraSpace.sm +
                  scaler.scale(PlayraType.label) * 1.2 +
                  PlayraSpace.tiny;
              final itemHeight = cardWidth * 3 / 2 + textHeight;
              final cacheWidth =
                  (cardWidth * MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(160, 720);
              return SizedBox(
                height: itemHeight,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
                    itemBuilder: (context, index) => SizedBox(
                      width: cardWidth,
                      child: HomePosterCard(
                        item: items[index],
                        rank: section.ranked ? index + 1 : null,
                        showScore: showScore,
                        cacheWidth: cacheWidth,
                        onTap: () => onTap(items[index]),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Multi-row poster grid section used by curated grid / waterfall shelves.
class HomeSectionPosterGrid extends StatelessWidget {
  const HomeSectionPosterGrid({
    super.key,
    required this.layout,
    required this.section,
    required this.onTap,
    this.onMore,
    this.moreLabel = '查看更多',
    this.maxItems,
    this.showScore = false,
  });

  final HomeLayoutMetrics layout;
  final MediaSection section;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback? onMore;
  final String moreLabel;
  final int? maxItems;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final items = maxItems == null
        ? section.items
        : section.items.take(maxItems!).toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: layout.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeadingRow(
            gutter: layout.gutter,
            title: section.title,
            moreLabel: moreLabel,
            onMore: onMore,
          ),
          const SizedBox(height: PlayraSpace.sm),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final columns = layout.isPhone
                    ? (scaler.scale(14) > 19 ? 2 : 3)
                    : layout.sectionColumns;
                final gap = layout.cardGap;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                final cacheWidth =
                    (cardWidth * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(160, 720);
                final rowCount = (items.length + columns - 1) ~/ columns;
                return Column(
                  children: [
                    for (var row = 0; row < rowCount; row++) ...[
                      if (row > 0) const SizedBox(height: PlayraSpace.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var col = 0; col < columns; col++) ...[
                            if (col > 0) SizedBox(width: gap),
                            Expanded(
                              child: row * columns + col < items.length
                                  ? HomePosterCard(
                                      item: items[row * columns + col],
                                      rank: section.ranked
                                          ? row * columns + col + 1
                                          : null,
                                      showScore: showScore,
                                      cacheWidth: cacheWidth,
                                      onTap: () =>
                                          onTap(items[row * columns + col]),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeadingRow extends StatelessWidget {
  const _SectionHeadingRow({
    required this.gutter,
    required this.title,
    required this.moreLabel,
    this.onMore,
  });

  final double gutter;
  final String title;
  final String moreLabel;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: PlayraSpace.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: PlayraType.section,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          if (onMore != null) ...[
            const SizedBox(width: PlayraSpace.xs),
            SizedBox(
              height: 40,
              child: TextButton(
                onPressed: onMore,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PlayraSpace.sm,
                  ),
                  minimumSize: const Size(48, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: t.textSecondary,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      moreLabel,
                      style: const TextStyle(fontSize: PlayraType.caption),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

double _sectionCardWidth(HomeLayoutMetrics layout) {
  if (layout.isPhoneCompact) return 112;
  if (layout.isPhone) return 118;
  if (layout.isTabletLandscape) return 180;
  return 170;
}

class _PosterRankBadge extends StatelessWidget {
  const _PosterRankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    const cornerRadius = BorderRadius.only(
      topLeft: Radius.circular(PlayraRadius.thumbnail),
      bottomRight: Radius.circular(10),
    );
    final label = '$rank'.padLeft(2, '0');
    final isTop3 = rank <= 3;

    if (!isTop3) {
      return ClipRRect(
        borderRadius: cornerRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 3, 9, 4),
            decoration: BoxDecoration(
              color: const Color(0x8212151E),
              borderRadius: cornerRadius,
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.75,
                ),
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.75,
                ),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
                color: Colors.white,
                height: 1.15,
              ),
            ),
          ),
        ),
      );
    }

    final (gradientColors, textColor) = switch (rank) {
      1 => (
        const [Color(0xFFFFE58F), Color(0xFFF59E0B)],
        const Color(0xFF2B1600),
      ),
      2 => (
        const [Color(0xFFF8FAFC), Color(0xFF94A3B8)],
        const Color(0xFF0F172A),
      ),
      _ => (
        const [Color(0xFFFDBA74), Color(0xFFC2410C)],
        Colors.white,
      ),
    };

    final style = TextStyle(
      fontSize: 11,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w900,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
      color: textColor,
      height: 1.15,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: cornerRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('TOP ', style: style),
          Text(label, style: style),
        ],
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({required this.child, this.frosted = false});

  final Widget child;
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(frosted ? 6 : 5);
    if (!frosted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xB8000000),
          borderRadius: radius,
        ),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x6612151E),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.75,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class HomePosterCard extends StatelessWidget {
  const HomePosterCard({
    super.key,
    required this.item,
    this.rank,
    this.showScore = false,
    this.cacheWidth,
    this.onTap,
  });

  final MediaItem item;
  final int? rank;
  final bool showScore;
  final int? cacheWidth;
  final VoidCallback? onTap;

  static String _scoreText(double score) => score == score.roundToDouble()
      ? score.toStringAsFixed(0)
      : score.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final coverRadius = BorderRadius.circular(PlayraRadius.thumbnail);
    final status = item.subtitle.isNotEmpty ? item.subtitle : item.metaText;
    final hasScore = showScore && (item.score ?? 0) > 0;
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label:
          '查看 ${item.title}${status.isEmpty ? '' : '，$status'}${hasScore ? '，评分 ${_scoreText(item.score!)}' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: coverRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: coverRadius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: t.cardPlaceholder,
                      child: MediaCoverImage(
                        url: item.cover,
                        fallbackUrl: item.fallbackCover,
                        cacheWidth: cacheWidth,
                        errorWidget: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [t.cardPlaceholder, t.railSelected],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: t.textSecondary,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (rank != null && rank! > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _PosterRankBadge(rank: rank!),
                      ),
                    if (hasScore)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: PosterScoreCornerBadge(
                          scoreText: _scoreText(item.score!),
                          topRightRadius: PlayraRadius.thumbnail,
                        ),
                      ),
                    if (status.isNotEmpty)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: _PosterBadge(
                            frosted: true,
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: PlayraType.micro,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: PlayraSpace.sm),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: PlayraType.label,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
