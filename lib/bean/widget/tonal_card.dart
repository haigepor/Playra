import 'package:flutter/material.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

const double tonalCardRadius = 24;

class TonalCard extends StatelessWidget {
  const TonalCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        ModernSettingsScope.isActiveOf(context) ? 16 : tonalCardRadius,
      ),
      side: ModernSettingsScope.isActiveOf(context)
          ? BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: .5),
            )
          : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}
