import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:flutter/material.dart';

enum ExitDialogAction { exit, minimizeToTray }

class ExitDialogResult {
  const ExitDialogResult({required this.action, required this.rememberChoice});

  final ExitDialogAction action;
  final bool rememberChoice;
}

class ExitConfirmationDialog extends StatefulWidget {
  const ExitConfirmationDialog({super.key});

  @override
  State<ExitConfirmationDialog> createState() => _ExitConfirmationDialogState();
}

class _ExitConfirmationDialogState extends State<ExitConfirmationDialog> {
  ExitDialogAction _action = ExitDialogAction.minimizeToTray;
  bool _rememberChoice = false;

  Duration get _animationDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PlayraDialog(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 440),

      scrollable: true,

      icon: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.exit_to_app_rounded,
            color: colors.onPrimaryContainer,
            size: 28,
          ),
        ),
      ),

      title: const Text('关闭 Playra？', textAlign: TextAlign.center),

      content: SizedBox(
        width: 392,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '选择关闭窗口后的操作',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            RadioGroup<ExitDialogAction>(
              groupValue: _action,
              onChanged: (value) {
                if (value != null) setState(() => _action = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildOption(
                    ExitDialogAction.minimizeToTray,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                      bottom: Radius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildOption(
                    ExitDialogAction.exit,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                      bottom: Radius.circular(20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PlayraCheckboxTile(
              value: _rememberChoice,
              onChanged: (value) {
                setState(() => _rememberChoice = value ?? false);
              },

              title: Text('记住我的选择', style: theme.textTheme.bodyMedium),
              subtitle: Text(
                '下次关闭窗口时不再询问',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),

      actions: [
        PlayraButton.ghost(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        PlayraButton(
          onPressed: () => Navigator.of(context).pop(
            ExitDialogResult(action: _action, rememberChoice: _rememberChoice),
          ),
          child: Text(switch (_action) {
            ExitDialogAction.minimizeToTray => '最小化至托盘',
            ExitDialogAction.exit => '退出',
          }),
        ),
      ],
    );
  }

  Widget _buildOption(
    ExitDialogAction action, {
    required BorderRadius borderRadius,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, description) = switch (action) {
      ExitDialogAction.minimizeToTray => (
        Icons.minimize_rounded,
        '最小化至托盘',
        '隐藏窗口，继续在后台运行',
      ),
      ExitDialogAction.exit => (
        Icons.power_settings_new_rounded,
        '退出 Playra',
        '结束运行并关闭应用',
      ),
    };
    final selected = _action == action;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurface;

    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      animationDuration: _animationDuration,
      child: PlayraRadioTile<ExitDialogAction>(
        value: action,
        selected: selected,

        secondary: Icon(icon, color: foreground),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(color: foreground),
        ),
        subtitle: Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
