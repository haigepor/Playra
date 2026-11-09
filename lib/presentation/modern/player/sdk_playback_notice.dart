import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

/// 先说明播放状态，再给出恢复动作；大字与窄屏不挤压消息正文。
class SdkPlaybackNotice extends StatelessWidget {
  const SdkPlaybackNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.onSwitch,
  });
  final String message;
  final VoidCallback? onRetry, onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = PlayraTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('sdk-playback-notice'),
        constraints: const BoxConstraints(minHeight: 48),
        margin: const EdgeInsets.only(bottom: PlayraSpace.md),
        padding: const EdgeInsets.all(PlayraSpace.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(PlayraRadius.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: PlayraSpace.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (onRetry != null || onSwitch != null) ...[
              const SizedBox(height: PlayraSpace.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onRetry != null)
                    PlayraButton.tonal(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      child: const Text('重试'),
                    ),
                  if (onSwitch != null)
                    PlayraButton.ghost(
                      onPressed: onSwitch,
                      child: const Text('切换线路'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
