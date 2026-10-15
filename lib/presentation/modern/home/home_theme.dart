import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ShadColorScheme modernHomeColors(Brightness brightness) =>
    brightness == Brightness.dark
    ? const ShadZincColorScheme.dark(
        background: Color(0xff11141c),
        foreground: Color(0xffedf0f8),
        card: Color(0xff1b202c),
        cardForeground: Color(0xffedf0f8),
        primary: Color(0xffa7b7ff),
        primaryForeground: Color(0xff182142),
        muted: Color(0xff202638),
        mutedForeground: Color(0xffa5afc5),
        border: Color(0xff30384a),
        input: Color(0xff30384a),
        ring: Color(0xffa7b7ff),
      )
    : const ShadZincColorScheme.light(
        background: Color(0xfff7f8fc),
        foreground: Color(0xff22293c),
        card: Colors.white,
        cardForeground: Color(0xff22293c),
        primary: Color(0xff5267d9),
        primaryForeground: Colors.white,
        muted: Color(0xffe9edfb),
        mutedForeground: Color(0xff647087),
        border: Color(0xffe3e7f0),
        input: Color(0xffe3e7f0),
        ring: Color(0xff5267d9),
      );

/// 首页可独立使用暗色，保留旧版和其他页面的全局主题偏好。
ThemeData modernHomeTheme(ThemeData base, {bool forceDark = false}) {
  final brightness = forceDark ? Brightness.dark : base.brightness;
  final zinc = modernHomeColors(brightness);
  return base.copyWith(
    // Web 即使运行在桌面系统的小窗，也保留移动页面的操作命中尺寸。
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    brightness: brightness,
    scaffoldBackgroundColor: zinc.background,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: zinc.primary,
      onPrimary: zinc.primaryForeground,
      surface: zinc.background,
      onSurface: zinc.foreground,
      surfaceContainer: zinc.card,
      surfaceContainerHigh: zinc.card,
      surfaceContainerLowest: zinc.background,
      surfaceContainerHighest: zinc.muted,
      surfaceContainerLow: zinc.card,
      onSurfaceVariant: zinc.mutedForeground,
      outline: zinc.border,
      outlineVariant: zinc.border,
      secondaryContainer: zinc.muted,
      onSecondaryContainer: zinc.primary,
      primaryContainer: zinc.muted,
      onPrimaryContainer: zinc.primary,
      secondary: zinc.primary,
      tertiary: zinc.primary,
      surfaceTint: Colors.transparent,
    ),
    // Material 弹层也使用新版色板，避免从全局种子色继承绿色表面。
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: zinc.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: zinc.foreground,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: zinc.mutedForeground,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: zinc.card,
      modalBackgroundColor: zinc.card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: zinc.mutedForeground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: zinc.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: zinc.mutedForeground),
      helperStyle: TextStyle(color: zinc.mutedForeground),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: zinc.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: zinc.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: zinc.primary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: zinc.primary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        overlayColor: zinc.primary.withValues(alpha: .08),
      ),
    ),
    // 强制暗色页面不能继续继承全局浅色Chip表面，否则浅色文字会落在白底上。
    chipTheme: base.chipTheme.copyWith(
      brightness: brightness,
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return zinc.muted.withValues(alpha: .6);
        }
        if (states.contains(WidgetState.selected)) {
          return zinc.primary.withValues(alpha: .14);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return zinc.muted;
        }
        return zinc.card;
      }),
      backgroundColor: zinc.card,
      selectedColor: zinc.muted,
      disabledColor: zinc.muted,
      labelStyle: base.textTheme.labelLarge?.copyWith(
        color: zinc.foreground,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: base.textTheme.labelLarge?.copyWith(
        color: zinc.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: zinc.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      checkmarkColor: zinc.primary,
      deleteIconColor: zinc.mutedForeground,
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    hoverColor: zinc.primary.withValues(alpha: .04),
    highlightColor: zinc.primary.withValues(alpha: .06),
    focusColor: zinc.primary.withValues(alpha: .12),
    textTheme: base.textTheme.apply(
      bodyColor: zinc.foreground,
      displayColor: zinc.foreground,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: zinc.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: zinc.muted,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? zinc.primary
              : zinc.mutedForeground,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? zinc.primary
              : zinc.mutedForeground,
        ),
      ),
    ),
  );
}

class ModernHomeScope extends StatelessWidget {
  const ModernHomeScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final material = modernHomeTheme(Theme.of(context), forceDark: true);
    return Theme(
      data: material,
      child: ShadTheme(
        data: ShadThemeData(
          brightness: material.brightness,
          colorScheme: modernHomeColors(material.brightness),
          textTheme: ShadTextTheme(
            family: material.textTheme.bodyMedium?.fontFamily,
          ),
          radius: BorderRadius.circular(12),
        ),
        child: Localizations.override(
          context: context,
          delegates: const [GlobalShadLocalizations.delegate],
          child: ContentSkeletonTheme(child: child),
        ),
      ),
    );
  }
}
