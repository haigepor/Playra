import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum ModernSectionKind { ranking, curated, resume }

/// 栏目名称承担语义；小图仅辅助识别，避免读屏重复朗读或产生额外点击目标。
class ModernSectionMark extends StatelessWidget {
  const ModernSectionMark({super.key, required this.kind});

  final ModernSectionKind kind;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/modern-section-${kind.name}.svg',
    width: 24,
    height: 24,
    excludeFromSemantics: true,
  );
}
