import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';
import '../../widgets/modern_anime_cover.dart';

class CalendarPosterCard extends StatefulWidget {
  const CalendarPosterCard({
    super.key,
    required this.entry,
    required this.collection,
    required this.onDetails,
    required this.onVisible,
    this.history,
    this.onResume,
  });
  final ScheduleEntry entry;
  final CollectType collection;
  final History? history;
  final VoidCallback onDetails, onVisible;
  final VoidCallback? onResume;
  @override
  State<CalendarPosterCard> createState() => _CalendarPosterCardState();
}

class _CalendarPosterCardState extends State<CalendarPosterCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
    final entry = widget.entry;
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final tags = entry.item.metaTags.take(3).join(' · ');
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onDetails,
          child: SizedBox(
            height: 146 + 100 * math.max(0, scale - 1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModernAnimeCover(
                    src: entry.cover,
                    score: entry.item.ratingScore,
                    votes: entry.item.votes,
                    hovered: hovered,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            if (widget.collection != CollectType.none) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: .09),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  widget.collection.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    height: 1.4,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                tags,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.clock3,
                                        size: 12,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          entry.time ?? '时间待定',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.5,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.history != null)
                                    Text(
                                      '上次看到${widget.history!.lastWatchEpisodeName.isEmpty ? '第${widget.history!.lastWatchEpisode}话' : widget.history!.lastWatchEpisodeName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: widget.onResume != null
                                  ? '继续观看${entry.title}'
                                  : '查看${entry.title}详情',
                              onPressed: widget.onResume ?? widget.onDetails,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: widget.onResume != null
                                    ? colors.primary.withValues(alpha: .1)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                widget.onResume != null
                                    ? LucideIcons.play
                                    : LucideIcons.chevronRight,
                                size: 15,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
