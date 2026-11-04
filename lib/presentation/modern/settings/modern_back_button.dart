import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

/// 小尺寸视觉反馈，保留 48dp 点击区域，与新版列表图标一致。
class ModernBackButton extends StatelessWidget {
  const ModernBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PlayraIconButton(
      tooltip: '返回',
      onPressed: onPressed ?? () => context.maybePop(),
      icon: const Icon(LucideIcons.chevronLeft, size: 20),
    );
  }
}
