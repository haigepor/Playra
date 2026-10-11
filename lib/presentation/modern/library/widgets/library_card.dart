import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../widgets/modern_anime_cover.dart';
import '../modern_library_controller.dart';

class LibraryCard extends StatefulWidget {
  const LibraryCard({
    super.key,
    required this.entry,
    required this.showRating,
    required this.pending,
    required this.onDetails,
    this.onResume,
    this.onManage,
  });
  final LibraryEntry entry;
  final bool showRating, pending;
  final VoidCallback onDetails;
  final VoidCallback? onResume, onManage;
  static double heightFor(BuildContext context) =>
      146 +
      100 * math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1);
  @override
  State<LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<LibraryCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final colors = Theme.of(context).colorScheme;
    final cover = ['large', 'common', 'medium', 'small']
        .map((key) => entry.item.images[key] ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final year = DateTime.tryParse(entry.item.airDate)?.year;
    final hasHistory = entry.history != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onDetails,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModernAnimeCover(
                  src: cover,
                  score: entry.item.ratingScore,
                  votes: entry.item.votes,
                  showRating: widget.showRating,
                  hovered: _hovered,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final compact =
                          bounds.maxWidth < 210 ||
                          MediaQuery.textScalerOf(context).scale(14) > 18;
                      return Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 34,
                                  top: 1,
                                ),
                                child: Text(
                                  entry.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(
                                        alpha: .09,
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      entry.status.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colors.primary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  if (year != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '$year',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          entry.episodeLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.4,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                        if (entry.positionLabel != null)
                                          Text(
                                            entry.positionLabel!,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.5,
                                              color: colors.primary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Tooltip(
                                    message: hasHistory
                                        ? '继续观看${entry.title}'
                                        : '查看${entry.title}详情',
                                    child: TextButton(
                                      key: ValueKey(
                                        'library-resume-${entry.item.id}',
                                      ),
                                      onPressed: hasHistory
                                          ? widget.onResume
                                          : widget.onDetails,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(44, 44),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: compact ? 8 : 10,
                                        ),
                                        backgroundColor: hasHistory
                                            ? colors.primary.withValues(
                                                alpha: .1,
                                              )
                                            : Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!compact) ...[
                                            Text(
                                              hasHistory ? '续播' : '详情',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Icon(
                                            hasHistory
                                                ? LucideIcons.play
                                                : LucideIcons.chevronRight,
                                            size: 15,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // 菜单保留 44px 触控区域，但不再撑高标题所在的文字行。
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              key: ValueKey('library-manage-${entry.item.id}'),
                              tooltip: '管理${entry.title}',
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(top: 2),
                              onPressed: widget.onManage,
                              icon: widget.pending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      LucideIcons.ellipsis,
                                      size: 18,
                                      color: colors.onSurfaceVariant,
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
