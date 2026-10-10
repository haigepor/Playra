import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
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
      152 +
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 112,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          scale: _hovered ? 1.035 : 1,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: NetworkImgLayer(
                            src: cover,
                            width: 78,
                            height: 112,
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 36,
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
                        if (widget.showRating &&
                            entry.item.ratingScore > 0 &&
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                entry.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              key: ValueKey('library-manage-${entry.item.id}'),
                              tooltip: '管理${entry.title}',
                              padding: EdgeInsets.zero,
                              onPressed: widget.onManage,
                              icon: widget.pending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.status.label}${year == null ? '' : ' · $year'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.primary),
                      ),
                      const Spacer(),
                      Text(
                        entry.episodeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.positionLabel ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          ShadButton.ghost(
                            key: ValueKey('library-resume-${entry.item.id}'),
                            size: ShadButtonSize.sm,
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            foregroundColor: colors.primary,
                            hoverBackgroundColor: Colors.transparent,
                            onPressed: entry.history == null
                                ? widget.onDetails
                                : widget.onResume,
                            leading: Icon(
                              entry.history == null
                                  ? LucideIcons.chevronRight
                                  : LucideIcons.play,
                              size: 13,
                            ),
                            child: Text(
                              entry.history == null ? '详情' : '续播',
                              style: const TextStyle(fontSize: 12),
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
    );
  }
}
