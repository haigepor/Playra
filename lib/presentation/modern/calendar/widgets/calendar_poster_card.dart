import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';

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
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onDetails,
          hoverColor: Colors.transparent,
          child: SizedBox(
            height: math.max(126, 126 + 66 * (scale - 1).clamp(0, 3)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedScale(
                            scale: hovered ? 1.035 : 1,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            child: NetworkImgLayer(
                              src: entry.cover,
                              width: 74,
                              height: 106,
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 38,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x52000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (entry.item.ratingScore > 0 &&
                              entry.item.votes > 0)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(0xffe9b754),
                                  borderRadius: BorderRadius.only(
                                    bottomRight: Radius.circular(7),
                                  ),
                                ),
                                child: Text(
                                  entry.item.ratingScore.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff292416),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 5,
                            bottom: 5,
                            child: Text(
                              entry.time ?? '时间待定',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (widget.collection != CollectType.none) ...[
                              Text(
                                widget.collection.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.primary,
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
                              child: Text(
                                widget.history == null
                                    ? '查看详情'
                                    : '上次看到${widget.history!.lastWatchEpisodeName.isEmpty ? '第${widget.history!.lastWatchEpisode}话' : widget.history!.lastWatchEpisodeName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (widget.onResume != null)
                              ShadButton.ghost(
                                size: ShadButtonSize.sm,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                onPressed: widget.onResume,
                                foregroundColor: colors.primary,
                                trailing: const Icon(
                                  LucideIcons.chevronRight,
                                  size: 13,
                                ),
                                child: const Text(
                                  '继续',
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            else
                              Icon(
                                LucideIcons.chevronRight,
                                size: 15,
                                color: colors.onSurfaceVariant,
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
