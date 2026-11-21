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
    final topPadding = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        PlayraSpace.xl,
        (topPadding > 0 ? 6 : PlayraSpace.md) + 2,
        PlayraSpace.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: 48),
            child: Row(
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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: largeTitle
                              ? PlayraType.pageTitle
                              : PlayraType.title,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                for (final action in actions) ...[
                  const SizedBox(width: PlayraSpace.xs),
                  action,
                ],
              ],
            ),
          ),
          if (bottom != null) ...[
            const SizedBox(height: PlayraSpace.sm),
            bottom!,
          ],
          const SizedBox(height: PlayraSpace.sm),
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
    final t = PlayraHomeTokens.of(context);
    return Material(
      color: t.cardSurface.withValues(alpha: .62),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, size: 21, color: color),
          ),
        ),
      ),
    );
  }
}
