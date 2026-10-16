import 'package:flutter/material.dart';

enum ModernPageArtKind { discover, calendar, library }

/// 大幅透明素材位于内容下层，不占布局、不拦截点击或进入读屏。
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final discover = kind == ModernPageArtKind.discover;
      final artwork = switch (kind) {
        ModernPageArtKind.discover => 'modern-cinema-header-art.png',
        ModernPageArtKind.calendar => 'modern-calendar-header-art.png',
        ModernPageArtKind.library => 'modern-library-header-art.png',
      };
      final contentWidth = contentMaxWidth == null
          ? constraints.maxWidth
          : constraints.maxWidth.clamp(0.0, contentMaxWidth!).toDouble();
      // 原图左侧约一半是透明留白，按画布放大才能让右侧主体达到背景尺寸。
      final artWidth = (contentWidth * 1.6).clamp(0.0, 1020.0).toDouble();
      return Stack(
        children: [
          Positioned(
            top: 0,
            right: (constraints.maxWidth - contentWidth) / 2,
            width: artWidth,
            child: ModernMaterialArt(
              asset: artwork,
              width: artWidth,
              opacity: discover ? .2 : .16,
            ),
          ),
          child,
        ],
      );
    },
  );
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
  Widget build(BuildContext context) => IgnorePointer(
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
