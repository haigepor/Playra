import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/presentation/interface_style.dart';
import '../home/home_theme.dart';
import '../../theme/playra_theme.dart';

/// 路由保持同一个子树，只切换呈现，避免设置中途丢失表单和返回栈。
class SettingsAppearanceHost extends StatelessWidget {
  const SettingsAppearanceHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final modern =
        context.watch<InterfaceStyleController>().style ==
        InterfaceStyle.modern;
    return ModernSettingsScope(enabled: modern, child: child);
  }
}

class ModernSettingsScope extends StatelessWidget {
  const ModernSettingsScope({
    super.key,
    this.enabled = true,
    required this.child,
  });
  final bool enabled;
  final Widget child;
  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_SettingsAppearance>()
          ?.modern ??
      false;

  @override
  Widget build(BuildContext context) {
    return ModernHomeScope(
      enabled: enabled,
      child: _SettingsAppearance(modern: enabled, child: child),
    );
  }
}

class _SettingsAppearance extends InheritedWidget {
  const _SettingsAppearance({required this.modern, required super.child});
  final bool modern;
  @override
  bool updateShouldNotify(_SettingsAppearance oldWidget) =>
      modern != oldWidget.modern;
}

ThemeData modernSettingsTheme(ThemeData base) => playraTheme(base);

/// 现有设置语义不变，仅替换新版图标。
IconData modernSettingsIcon(IconData icon) => switch (icon) {
  Icons.display_settings_rounded => LucideIcons.slidersHorizontal,
  Icons.subtitles_rounded => LucideIcons.messageSquare,
  Icons.keyboard_rounded => LucideIcons.keyboard,
  Icons.extension_rounded => LucideIcons.puzzle,
  Icons.downloading_rounded => LucideIcons.download,
  Icons.palette_rounded => LucideIcons.palette,
  Icons.pages_rounded => LucideIcons.layoutGrid,
  Icons.cloud_rounded => LucideIcons.cloud,
  Icons.language_rounded => LucideIcons.globe,
  Icons.update_rounded => LucideIcons.refreshCw,
  Icons.storage_rounded => LucideIcons.hardDrive,
  Icons.info_outline_rounded => LucideIcons.info,
  Icons.dark_mode_rounded => LucideIcons.moon,
  Icons.home_rounded => LucideIcons.house,
  Icons.star_rounded => LucideIcons.star,
  Icons.folder_rounded => LucideIcons.folder,
  Icons.history_rounded => LucideIcons.history,
  _ => icon,
};
