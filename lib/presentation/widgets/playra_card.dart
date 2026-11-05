import 'package:flutter/material.dart';

import '../theme/playra_tokens.dart';

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
    final isPoster = kind == PlayraCardKind.poster;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: isPoster ? Colors.transparent : t.surface,
        borderRadius: radius,
        clipBehavior: isPoster ? Clip.none : Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: isPoster ? null : Border.all(color: t.borderSubtle),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: content,
          ),
        ),
      ),
    );
  }
}
