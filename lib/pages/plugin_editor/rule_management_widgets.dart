import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/secondary/utility_page_art.dart';

class RulePageIntro extends StatelessWidget {
  const RulePageIntro({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.actions = const [],
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return UtilityPageIntro(
      icon: UtilityIconKind.rules,
      title: title,
      description: description,
      artwork: 'modern-library-header-art',
      actions: actions,
    );
  }
}

class RuleSection extends StatelessWidget {
  const RuleSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.icon,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PlayraTokens.of(context);
    final modern = ModernSettingsScope.isActiveOf(context);
    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(modern ? 14 : PlayraRadius.overlay),
        side: BorderSide(
          color: tokens.borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(modern ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: tokens.primary),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.foregroundMuted,
                ),
              ),
            ],
            SizedBox(height: modern ? 16 : 24),
            child,
          ],
        ),
      ),
    );
  }
}

InputDecoration ruleInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? prefix,
  Widget? suffix,
}) {
  final tokens = PlayraTokens.of(context);
  final modern = ModernSettingsScope.isActiveOf(context);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: tokens.surface,
    contentPadding: EdgeInsets.symmetric(
      horizontal: modern ? 14 : 20,
      vertical: modern ? 14 : 18,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(modern ? 14 : PlayraRadius.card),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(modern ? 14 : PlayraRadius.card),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(modern ? 14 : PlayraRadius.card),
      borderSide: BorderSide(color: tokens.primary, width: 1.5),
    ),
  );
}
