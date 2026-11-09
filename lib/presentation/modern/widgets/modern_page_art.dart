import 'package:flutter/material.dart';

enum ModernPageArtKind { discover, calendar, library }

/// Content pages use a quiet background; illustrations belong to empty states.
class ModernPageArt extends StatelessWidget {
  const ModernPageArt({
    super.key,
    required this.kind,
    required this.child,
    this.contentMaxWidth,
  });

  final ModernPageArtKind kind;
  final Widget child;
  final double? contentMaxWidth;

  @override
  Widget build(BuildContext context) => child;
}

/// 这一组素材均为 3:1，完整展示右侧主体；越界部分只是原图的透明留白。
class ModernMaterialArt extends StatelessWidget {
  const ModernMaterialArt({
    super.key,
    required this.asset,
    required this.width,
    this.opacity = .18,
  });

  final String asset;
  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) => opacity == 0
      ? const SizedBox.shrink()
      : IgnorePointer(
          child: ExcludeSemantics(
            child: SizedBox(
              width: width,
              height: width / 3,
              child: Opacity(
                opacity: opacity,
                child: Image.asset(
                  'assets/images/$asset',
                  fit: BoxFit.contain,
                  alignment: Alignment.topRight,
                  // 小尺寸装饰按物理显示宽度解码；大图沿用既有上限。
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1440),
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        );
}
