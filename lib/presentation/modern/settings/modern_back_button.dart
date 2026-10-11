import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

/// 小尺寸视觉反馈，保留 48dp 点击区域，与新版列表图标一致。
class ModernBackButton extends StatelessWidget {
  const ModernBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '返回',
      onPressed: onPressed ?? () => context.maybePop(),
      icon: const Icon(LucideIcons.chevronLeft, size: 20),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(36)),
        minimumSize: const WidgetStatePropertyAll(Size.square(36)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? c.primary
              : c.onSurfaceVariant,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? c.primary.withValues(alpha: .1)
              : c.onSurface.withValues(alpha: .035),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
      ),
    );
  }
}
