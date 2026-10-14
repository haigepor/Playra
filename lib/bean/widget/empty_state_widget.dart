import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

/// Shrink-wraps in slivers and scrolls within bounded viewports.
class GeneralEmptyState extends StatelessWidget {
  const GeneralEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.actions = const [],
    this.compact = false,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final List<Widget> actions;
  final bool compact;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final modern = ModernSettingsScope.isActiveOf(context);

    // 页面/栏目仍由外层决定可用空间，共享标题、图形和操作之间的节奏。
    if (modern && !compact) {
      return Center(
        child: SingleChildScrollView(
          primary: false,
          child: SecondaryEmptyState(
            title: title,
            artwork: SizedBox(
              width: 132,
              height: 86,
              child:
                  illustration ??
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: 48,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
            ),
            action: actions.isEmpty
                ? null
                : Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        primary: false,
        padding: compact || modern
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              illustration ??
                  StateIconBadge(
                    icon: icon,
                    size: modern
                        ? 48
                        : compact
                        ? 56
                        : 88,
                    iconSize: modern
                        ? 22
                        : compact
                        ? 28
                        : 36,
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                  ),
              SizedBox(height: compact || modern ? 16 : 24),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style:
                      (compact ? textTheme.titleMedium : textTheme.titleLarge)
                          ?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                SizedBox(height: compact || modern ? 16 : 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
