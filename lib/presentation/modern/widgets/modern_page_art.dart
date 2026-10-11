import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum ModernPageArtKind { discover, calendar, library }

/// 装饰只覆盖页头，不参与布局、点击命中或读屏，列表滚动区域保持纯净。
class ModernPageArt extends StatelessWidget {
  const ModernPageArt({super.key, required this.kind, required this.child});

  final ModernPageArtKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 0,
        right: 0,
        width: 248,
        height: 132,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: SvgPicture.asset(
              'assets/images/modern-${kind.name}-decoration.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.primary.withValues(alpha: .11),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}
