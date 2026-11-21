import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// 空壳占位页：新页面接入前统一使用这一版式。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.action,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<PlayraTokens>()!;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(PlayraSpace.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // 居中显示：文案长短不同的占位页左边界才不会跳来跳去。
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: t.primary),
                const SizedBox(height: PlayraSpace.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: PlayraType.pageTitle,
                    color: t.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: PlayraSpace.sm),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: t.mutedForeground,
                    height: PlayraType.bodyHeight,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: PlayraSpace.xl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
