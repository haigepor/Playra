import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/modern_page_art.dart';

enum UtilityIconKind {
  history,
  offline,
  rules,
  sdk,
  synchronization,
  collection,
  devices,
  pending,
  resolving,
  downloading,
  paused,
  failed,
  completed,
}

/// 装饰符号由邻近文字提供语义；颜色遵循当前页面主题。
class UtilitySvgIcon extends StatelessWidget {
  const UtilitySvgIcon(this.kind, {super.key, this.size = 24, this.color});

  final UtilityIconKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/modern-utility-${kind.name}.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ?? Theme.of(context).colorScheme.primary,
      BlendMode.srcIn,
    ),
    excludeFromSemantics: true,
  );
}

/// 原图左侧为透明留白，空态只展示右侧主体，避免把主体缩得过小。
class UtilityMaterialArtwork extends StatelessWidget {
  const UtilityMaterialArtwork({
    super.key,
    required this.asset,
    this.width = 200,
    this.height = 124,
  });

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          'assets/images/$asset.png',
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          cacheWidth: 1080,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

class UtilityPageIntro extends StatelessWidget {
  const UtilityPageIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.artwork,
    this.actions = const [],
  });

  final UtilityIconKind icon;
  final String title;
  final String description;
  final String? artwork;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      constraints: artwork == null
          ? null
          : const BoxConstraints(minHeight: 144),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .35)),
      ),
      child: Stack(
        children: [
          if (artwork != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 600,
              child: ModernMaterialArt(
                asset: '$artwork.png',
                width: 600,
                opacity: .16,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: UtilitySvgIcon(icon, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
