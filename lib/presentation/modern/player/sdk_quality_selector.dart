import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';

/// 画质偏好独立于线路锁；控件完全继承新版播放页的主题与触控约束。
class SdkQualitySelector extends StatelessWidget {
  const SdkQualitySelector({
    super.key,
    required this.qualities,
    required this.automaticLabel,
    required this.onSelected,
    this.selectedCode,
    this.status = 'ready',
    this.busy = false,
    this.showStatus = true,
    this.onRetry,
  });
  final List<SdkQuality> qualities;
  final String automaticLabel, status;
  final String? selectedCode;
  final bool busy;
  final bool showStatus;
  final VoidCallback? onRetry;
  final ValueChanged<String?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = qualities.where((q) => q.height != null).toList();
    final message = switch (status) {
      'loading' => '正在获取画质…',
      'timeout' => '画质查询超时，可重试当前线路',
      'failed' => '画质查询失败，可重试当前线路',
      _ =>
        selectedCode != null && !known.any((q) => q.code == selectedCode)
            ? '当前集没有所选画质，请选择其他画质或自动'
            : known.isEmpty
            ? '来源未声明画质'
            : null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 10),
              child: Text('画质', style: theme.textTheme.labelLarge),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 自动偏好的完整说明保留在提示中，避免长标签把档位挤到下一行。
                  if (known.isNotEmpty || selectedCode != null)
                    Tooltip(
                      message: automaticLabel,
                      child: ChoiceChip(
                        key: const ValueKey('sdk-quality-auto'),
                        label: const Text('自动'),
                        selected: selectedCode == null,
                        onSelected: onSelected == null
                            ? null
                            : (_) => onSelected!(null),
                      ),
                    ),
                  for (final quality in known)
                    ChoiceChip(
                      key: ValueKey('sdk-quality-${quality.code}'),
                      label: Text(quality.choiceLabel),
                      selected: selectedCode == quality.code,
                      onSelected: onSelected == null
                          ? null
                          : (_) => onSelected!(quality.code),
                    ),
                ],
              ),
            ),
            if (onRetry != null && (status == 'failed' || status == 'timeout'))
              PlayraIconButton(
                onPressed: onRetry,
                tooltip: '重新获取画质',
                icon: const Icon(Icons.refresh_rounded, size: 16),
              ),
          ],
        ),
        if (busy)
          Semantics(
            liveRegion: true,
            child: Text(
              '正在准备所选画质…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (message != null && showStatus)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
