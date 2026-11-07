import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

/// 错误与恢复动作同行；窄屏只让文案换行，不为空白操作区预留整行。
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(PlayraRadius.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface,
                  height: 1.4,
                ),
              ),
            ),
            if (onRetry != null)
              PlayraButton.ghost(onPressed: onRetry, child: const Text('重试')),
            if (onSwitch != null)
              PopupMenuButton<String>(
                tooltip: '更多恢复操作',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                onSelected: (_) => onSwitch!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'line', child: Text('切换线路')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
