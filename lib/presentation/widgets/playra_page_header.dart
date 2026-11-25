import 'package:flutter/material.dart';

import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Editorial page header shared by search, browse, favorites and profile.
///
/// Root tabs use the large title variant; pushed pages show a circular back
/// button and keep the title on the same visual axis as the home brand row.
class PlayraPageHeader extends StatelessWidget {
  const PlayraPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const <Widget>[],
    this.bottom,
    this.largeTitle = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom;
  final bool largeTitle;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final stacked =
        onBack == null && MediaQuery.textScalerOf(context).scale(14) > 20;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayraSpace.lg,
        6,
        PlayraSpace.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Flex(
              direction: stacked ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (onBack != null) ...[
                  _CircleIconButton(
                    tooltip: '返回',
                    icon: Icons.arrow_back_rounded,
                    color: t.textPrimary,
                    onTap: onBack!,
                  ),
                  const SizedBox(width: PlayraSpace.sm),
                ],
                Flexible(
                  flex: stacked ? 0 : 1,
                  fit: stacked ? FlexFit.loose : FlexFit.tight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: largeTitle ? null : 2,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: largeTitle ? 22 : 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: largeTitle ? -0.3 : -0.1,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: PlayraType.small,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: PlayraSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
              ],
            ),
          ),
          if (bottom != null) ...[
            const SizedBox(height: PlayraSpace.sm),
            bottom!,
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class PlayraCircleAction extends StatelessWidget {
  const PlayraCircleAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.foreground,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return _CircleIconButton(
      tooltip: tooltip,
      icon: icon,
      color: foreground ?? t.textPrimary,
      onTap: onTap,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 36,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
