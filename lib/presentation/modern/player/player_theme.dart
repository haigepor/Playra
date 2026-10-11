import 'package:flutter/material.dart';
import '../home/home_theme.dart';

/// 播放页保持紧凑内容密度，触控目标不随桌面主题压缩为 40dp。
class ModernPlayerScope extends StatelessWidget {
  const ModernPlayerScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.padded,
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
