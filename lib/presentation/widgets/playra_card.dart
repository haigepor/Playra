import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:shadcn_ui/shadcn_ui.dart' show ShadCard, ShadBorder;

import '../theme/playra_tokens.dart';
import '../theme/playra_forui_theme.dart';
import 'playra_component_scope.dart';

enum PlayraCardKind { content, poster, hero }

/// Shared surface for product cards; layout and business actions stay with callers.
class PlayraCard extends StatelessWidget {
  const PlayraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PlayraSpace.lg),
    this.kind = PlayraCardKind.content,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final PlayraCardKind kind;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final radius = BorderRadius.circular(switch (kind) {
      PlayraCardKind.content => PlayraRadius.card,
      PlayraCardKind.poster => PlayraRadius.poster,
      PlayraCardKind.hero => PlayraRadius.hero,
    });
    final content = Padding(padding: padding, child: child);
    if (!PlayraComponentScope.enabledOf(context)) {
      return ShadCard(
        width: width,
        height: height,
        padding: EdgeInsets.zero,
        radius: radius,
        backgroundColor: t.surface,
        border: ShadBorder.all(color: t.border.withValues(alpha: .5)),
        shadows: const [],
        rowMainAxisSize: MainAxisSize.max,
        columnCrossAxisAlignment: CrossAxisAlignment.stretch,
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null
              ? content
              : InkWell(onTap: onTap, borderRadius: radius, child: content),
        ),
      );
    }
    final theme = playraForuiTheme(Theme.of(context));
    final card = f.FCard(
      style: f.FCardStyle(
        decoration: ShapeDecoration(
          color: t.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(color: t.border),
          ),
        ),
        titleTextStyle: theme.typography.display.lg,
        subtitleTextStyle: theme.typography.body.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
    return PlayraForuiScope(
      child: SizedBox(width: width, height: height, child: card),
    );
  }
}
