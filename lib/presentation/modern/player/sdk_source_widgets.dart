import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

Duration sdkMotion(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// SVG 只提供结构，颜色完全跟随现有主题 token。
class SdkSourceGlyph extends StatelessWidget {
  const SdkSourceGlyph({super.key, this.automatic = false, this.size = 22});
  final bool automatic;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    automatic ? 'assets/images/sdk-auto.svg' : 'assets/images/sdk-route.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      Theme.of(context).colorScheme.primary,
      BlendMode.srcIn,
    ),
  );
}

class SdkSourceDecoration extends StatelessWidget {
  const SdkSourceDecoration({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: .12,
      child: SvgPicture.asset(
        'assets/images/sdk-orbit.svg',
        width: 150,
        height: 94,
        excludeFromSemantics: true,
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.primary,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

class SdkLineOption extends StatelessWidget {
  const SdkLineOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.automatic = false,
    this.selected = false,
    this.current = false,
  });
  final String title, subtitle;
  final VoidCallback onTap;
  final bool automatic, selected, current;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: sdkMotion(context),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AnimatedContainer(
            duration: sdkMotion(context, 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: .10)
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? colors.primary.withValues(alpha: .45)
                    : colors.outline,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: SdkSourceGlyph(automatic: automatic, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            if (current && !selected) ...[
                              const SizedBox(height: 5),
                              Text(
                                '当前使用',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 10),
                        ExcludeSemantics(
                          child: Icon(
                            Icons.check_rounded,
                            size: 21,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
