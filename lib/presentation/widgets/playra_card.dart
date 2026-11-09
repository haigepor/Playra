import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

import '../theme/playra_forui_theme.dart';
import '../theme/playra_tokens.dart';

enum PlayraCardKind { content, poster, hero }

/// Shared surface for product cards; layout and business actions stay with callers.
class PlayraCard extends StatelessWidget with PlayraForuiComponent {
  const PlayraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PlayraSpace.lg),
    this.kind = PlayraCardKind.content,
    this.onTap,
    this.width,
    this.height,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final PlayraCardKind kind;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget buildForui(BuildContext context) {
    final theme = f.FTheme.of(context);
    final decoration = theme.cardStyle.decoration as ShapeDecoration;
    final shape = decoration.shape as RoundedSuperellipseBorder;
    final radius =
        borderRadius ??
        BorderRadius.circular(switch (kind) {
          PlayraCardKind.content => PlayraRadius.card,
          PlayraCardKind.poster => PlayraRadius.poster,
          PlayraCardKind.hero => PlayraRadius.hero,
        });
    final content = Padding(padding: padding, child: child);
    final isPoster = kind == PlayraCardKind.poster;

    Widget surface(Set<f.FTappableVariant> states) => f.FCard(
      clipBehavior: isPoster ? Clip.none : Clip.antiAlias,
      style: f.FCardStyleDelta.delta(
        decoration: f.DecorationDelta.value(
          ShapeDecoration(
            image: decoration.image,
            gradient: decoration.gradient,
            shadows: decoration.shadows,
            color: isPoster
                ? Colors.transparent
                : states.contains(f.FTappableVariant.hovered) ||
                      states.contains(f.FTappableVariant.pressed)
                ? theme.colors.secondary
                : decoration.color,
            shape: shape.copyWith(
              borderRadius: radius,
              side: isPoster ? BorderSide.none : shape.side,
            ),
          ),
        ),
      ),
      child: content,
    );
    return SizedBox(
      width: width,
      height: height,
      child: onTap == null
          ? surface({})
          : f.FTappable(
              onPress: onTap,
              builder: (_, states, _) => surface(states),
            ),
    );
  }
}
