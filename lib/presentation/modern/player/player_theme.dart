import 'package:flutter/material.dart';
import '../secondary/secondary_theme.dart';

/// 播放页保持紧凑内容密度，触控目标不随桌面主题压缩为 40dp。
class ModernPlayerScope extends StatelessWidget {
  const ModernPlayerScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ModernSecondaryScope(
    child: Builder(
      builder: (context) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            // 半透明Chip绘制在Material画布上，画布同样使用新版卡片表面。
            canvasColor: base.colorScheme.surfaceContainerLow,
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            // Material2 的 ChoiceChip 忽略状态色，桥接同一新版Token，避免继承全局浅色选中底。
            chipTheme: base.chipTheme.copyWith(
              selectedColor: base.chipTheme.color?.resolve({
                WidgetState.selected,
              }),
              secondarySelectedColor: base.chipTheme.color?.resolve({
                WidgetState.selected,
              }),
            ),
            textButtonTheme: TextButtonThemeData(
              style: (base.textButtonTheme.style ?? const ButtonStyle())
                  .copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                    visualDensity: VisualDensity.standard,
                  ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: (base.iconButtonTheme.style ?? const ButtonStyle())
                  .copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                    visualDensity: VisualDensity.standard,
                    foregroundColor: WidgetStatePropertyAll(
                      base.colorScheme.onSurfaceVariant,
                    ),
                  ),
            ),
          ),
          child: child,
        );
      },
    ),
  );
}
