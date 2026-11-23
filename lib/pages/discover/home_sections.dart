import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
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
  });

  final HomeLayoutMetrics layout;
  final MediaSection section;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final items = section.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final t = PlayraHomeTokens.of(context);
    final hasMore = onMore != null;
    return Padding(
      padding: EdgeInsets.only(top: layout.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
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
                if (hasMore) ...[
                  const SizedBox(width: PlayraSpace.xs),
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: onMore,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PlayraSpace.sm,
                        ),
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: t.textSecondary,
                      ),
                      child: Text(
                        '更多',
                        style: TextStyle(fontSize: PlayraType.caption),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
                  scaler.scale(PlayraType.item) * 1.2 * 2 +
                  3 +
                  scaler.scale(PlayraType.caption) * 1.2 +
                  PlayraSpace.tiny;
              final itemHeight = cardWidth * 3 / 2 + textHeight;
              final cacheWidth =
                  (cardWidth * MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(160, 720);
              return SizedBox(
                height: itemHeight,
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
                      cacheWidth: cacheWidth,
                      onTap: () => onTap(items[index]),
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

double _sectionCardWidth(HomeLayoutMetrics layout) {
  if (layout.isPhoneCompact) return 112;
  if (layout.isPhone) return 118;
  if (layout.isTabletLandscape) return 180;
  return 170;
}

class HomePosterCard extends StatelessWidget {
  const HomePosterCard({
    super.key,
    required this.item,
    this.rank,
    this.cacheWidth,
    this.onTap,
  });

  final MediaItem item;
  final int? rank;
  final int? cacheWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final coverRadius = BorderRadius.circular(PlayraRadius.poster);
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label:
          '查看 ${item.title}${item.subtitle.isEmpty ? '' : '，${item.subtitle}'}',
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
                    if (rank != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$rank',
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: PlayraSpace.sm),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.textScalerOf(context).scale(PlayraType.item) *
                    2.4,
              ),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: PlayraType.item,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            if (item.subtitle.isNotEmpty || item.metaText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  item.subtitle.isNotEmpty ? item.subtitle : item.metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: PlayraType.caption,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
