import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';

class EpisodeCommentsPicker extends StatelessWidget {
  const EpisodeCommentsPicker({
    super.key,
    required this.episodes,
    required this.selectedEpisode,
  });

  final List<EpisodeInfo> episodes;
  final int selectedEpisode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = Theme.of(context).textTheme;
    final tokens = PlayraTokens.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.overlay),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择讨论分集',
                      style: type.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('切换想看的讨论，视频会继续播放。',
                      style: type.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: episodes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 3),
                itemBuilder: (context, index) {
                  final info = episodes[index];
                  final title =
                      info.nameCn.isNotEmpty ? info.nameCn : info.name;
                  final selected = index + 1 == selectedEpisode;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.primaryContainer
                          : tokens.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(index == 0 ? 20 : 4),
                        bottom: Radius.circular(
                            index == episodes.length - 1 ? 20 : 4),
                      ),
                      border: Border.all(
                        color: selected ? tokens.primary : tokens.borderSubtle,
                      ),
                    ),
                    child: PlayraListTile(
                      onTap: () => Navigator.pop(context, index + 1),
                      title: Text(
                        '${info.readType().toUpperCase()} ${info.episode}'
                            .trim(),
                        style: type.labelLarge?.copyWith(
                          color: selected
                              ? tokens.primary
                              : tokens.foreground,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: title.isEmpty
                          ? null
                          : Text(
                              title,
                              style: type.bodyMedium?.copyWith(
                                color: selected
                                    ? tokens.foreground
                                    : tokens.foregroundMuted,
                              ),
                            ),
                      trailing: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.chevron_right_rounded,
                        color:
                            selected ? tokens.primary : tokens.foregroundMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: PlayraButton.ghost(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
