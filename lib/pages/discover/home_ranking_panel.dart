import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

/// Compact top-five column shown beside the hero on tablet landscape.
///
/// It reuses the first ranked section already returned by the home feed, so
/// it adds no request and no source-specific logic.
class HomeRankingPanel extends StatelessWidget {
  const HomeRankingPanel({
    super.key,
    required this.layout,
    required this.section,
    required this.onTap,
  });

  final HomeLayoutMetrics layout;
  final MediaSection? section;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    final ranked = section;
    if (ranked == null || ranked.items.isEmpty) return const SizedBox.shrink();
    final t = PlayraHomeTokens.of(context);
    final items = ranked.items.take(5).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(PlayraRadius.card),
        border: Border.all(color: t.divider.withValues(alpha: .72)),
      ),
      padding: const EdgeInsets.fromLTRB(
        PlayraSpace.lg,
        PlayraSpace.md,
        PlayraSpace.sm,
        PlayraSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: PlayraSpace.sm),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.sectionMarkStart, t.sectionMarkEnd],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: PlayraSpace.sm),
                Text(
                  ranked.tabs.isNotEmpty ? ranked.tabs.first : '热播榜',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: PlayraType.item,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'TOP 5',
                  style: TextStyle(
                    color: t.accent,
                    fontSize: PlayraType.micro,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PlayraSpace.sm),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: t.divider.withValues(alpha: .56)),
              itemBuilder: (context, index) => _RankingRow(
                rank: index + 1,
                item: items[index],
                onTap: () => onTap(items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.item,
    required this.onTap,
  });

  final int rank;
  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PlayraRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PlayraSpace.compact),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3 ? t.accent : t.textSecondary,
                  fontSize: PlayraType.item,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: PlayraSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(PlayraRadius.thumbnail),
              child: SizedBox(
                width: 40,
                height: 52,
                child: MediaCoverImage(
                  url: item.cover,
                  cacheWidth: 120,
                  errorWidget: ColoredBox(color: t.cardPlaceholder),
                ),
              ),
            ),
            const SizedBox(width: PlayraSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle.isEmpty ? item.metaText : item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: PlayraType.small,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}
