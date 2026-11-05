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
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('sdk-playback-notice'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(PlayraRadius.control),
          border: Border(left: BorderSide(color: colors.primary, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
            if (onRetry != null)
              PlayraButton.ghost(onPressed: onRetry, child: const Text('重试')),
            if (onSwitch != null)
              PopupMenuButton<String>(
                tooltip: '更多恢复操作',
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
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
