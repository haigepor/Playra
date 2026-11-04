import 'package:flutter/material.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'package:kazumi/presentation/widgets/playra_component_scope.dart';

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
  Widget build(BuildContext context) =>
      PlayraComponentScope.enabledOf(context) ||
          ModernSettingsScope.isActiveOf(context)
      ? PlayraCard(padding: padding, child: child)
      : Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tonalCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        );
}
