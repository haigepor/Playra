import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

void _showMessage(BuildContext context, String message) {
  KazumiDialog.showToast(context: context, message: message);
}

class AboutContent extends StatelessWidget {
  const AboutContent({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ModernSettingsScope.isActiveOf(context) ? 760 : 880,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class AboutLinkTile extends StatelessWidget {
  const AboutLinkTile.route({
    super.key,
    required this.icon,
    required this.title,
    required String route,
    this.subtitle,
  }) : _route = route;

  final IconData icon;
  final String title;
  final String? subtitle;
  final String _route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final modern = ModernSettingsScope.isActiveOf(context);
    return InkWell(
      onTap: () => context.pushNamed(_route),
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: modern ? 14 : 16,
          vertical: modern ? 12 : 16,
        ),
        child: Row(
          children: [
            StateIconBadge(
              icon: icon,
              size: 36,
              iconSize: 20,
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
            ),
            SizedBox(width: modern ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style:
                          (modern
                                  ? theme.textTheme.bodySmall
                                  : theme.textTheme.bodyMedium)
                              ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              size: modern ? 16 : 20,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class CheckUpdateButton extends StatefulWidget {
  const CheckUpdateButton({super.key, required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  State<CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<CheckUpdateButton> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.onCheckUpdate();
    } catch (_) {
      if (mounted) _showMessage(context, '检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => StateActionButton(
    onPressed: _checking ? null : _check,
    text: _checking ? '正在检查…' : '检查更新',
    reserveText: '正在检查…',
    icon: Icons.update_rounded,
  );
}
