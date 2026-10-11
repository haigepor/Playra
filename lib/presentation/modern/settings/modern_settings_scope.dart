import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/presentation/interface_style.dart';
import '../home/home_theme.dart';

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
    final base = Theme.of(context);
    return Theme(
      data: enabled ? modernSettingsTheme(base) : base,
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

ThemeData modernSettingsTheme(ThemeData base) {
  final theme = modernHomeTheme(base, forceDark: true);
  final c = theme.colorScheme;
  final muted = c.surfaceContainerHighest;
  return theme.copyWith(
    colorScheme: c.copyWith(
      primaryContainer: muted,
      onPrimaryContainer: c.primary,
      tertiaryContainer: muted,
      onTertiaryContainer: c.primary,
    ),
    iconTheme: IconThemeData(color: c.onSurfaceVariant, size: 20),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: c.onSurfaceVariant, size: 20),
      actionsIconTheme: IconThemeData(color: c.onSurfaceVariant, size: 20),
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    textTheme: theme.textTheme.copyWith(
      headlineLarge: theme.textTheme.headlineLarge?.copyWith(fontSize: 22),
      headlineMedium: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
      headlineSmall: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
      titleLarge: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
      titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
      titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.5),
      bodyMedium: theme.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.5),
      labelLarge: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
      labelMedium: theme.textTheme.labelMedium?.copyWith(fontSize: 12),
      labelSmall: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
    ),
    // 收紧视觉尺寸，保留系统大字体与 48dp 触摸目标。
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // 焦点和按压局限于控件内，避免大面积彩色波纹。
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.onSurface.withValues(alpha: .035),
    hoverColor: c.onSurface.withValues(alpha: .025),
    focusColor: c.primary.withValues(alpha: .12),
    dividerColor: c.outline.withValues(alpha: .4),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? c.onSurfaceVariant.withValues(alpha: .35)
            : s.contains(WidgetState.selected)
            ? c.primary
            : c.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? muted.withValues(alpha: .5)
            : s.contains(WidgetState.selected)
            ? c.primary.withValues(alpha: .25)
            : muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(c.outline),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      activeTrackColor: c.primary,
      inactiveTrackColor: muted,
      thumbColor: c.primary,
      trackHeight: 2,
      trackGap: 0,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 5,
        disabledThumbRadius: 4,
        elevation: 0,
        pressedElevation: 0,
      ),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      overlayColor: c.primary.withValues(alpha: .08),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? c.onSurfaceVariant.withValues(alpha: .35)
            : s.contains(WidgetState.selected)
            ? c.primary
            : c.onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: c.onSurfaceVariant),
      hintStyle: TextStyle(color: c.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        side: BorderSide(color: c.outline),
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      backgroundColor: c.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
      backgroundColor: c.surfaceContainerLow,
      modalBackgroundColor: c.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.outline),
          ),
        ),
      ),
    ),
  );
}

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
