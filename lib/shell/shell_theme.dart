import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// 空壳项目的基础主题：只使用 Playra 设计 token，不依赖旧版页面主题。
ThemeData buildShellTheme(Brightness brightness) {
  final t = brightness == Brightness.dark
      ? PlayraTokens.dark
      : PlayraTokens.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: t.primary,
    brightness: brightness,
  ).copyWith(
    primary: t.primary,
    onPrimary: t.primaryForeground,
    secondary: t.primary,
    onSecondary: t.primaryForeground,
    surface: t.background,
    onSurface: t.foreground,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceRaised,
    surfaceContainerLow: t.surfaceOverlay,
    error: t.destructive,
    outline: t.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'MI_Sans_Regular',
    scaffoldBackgroundColor: t.background,
    extensions: [t],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.foreground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelSmall?.copyWith(color: t.mutedForeground),
      ),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.card),
        side: BorderSide(color: t.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.primaryForeground,
        minimumSize: const Size(0, PlayraLayout.touchTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlayraRadius.control),
        ),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: t.foreground,
      displayColor: t.foreground,
    ),
  );
}
