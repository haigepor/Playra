import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// 空壳项目的基础主题：只使用 Playra 设计 token，不依赖旧版页面主题。
ThemeData buildShellTheme(Brightness brightness) {
  final t = brightness == Brightness.dark
      ? PlayraTokens.dark
      : PlayraTokens.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: t.primary,
        brightness: brightness,
      ).copyWith(
        primary: t.primary,
        onPrimary: t.primaryForeground,
        primaryContainer: t.primaryContainer,
        onPrimaryContainer: t.primary,
        secondary: t.primary,
        onSecondary: t.primaryForeground,
        surface: t.background,
        onSurface: t.foreground,
        surfaceContainerLow: t.surface,
        surfaceContainer: t.surface,
        surfaceContainerHigh: t.surfaceRaised,
        surfaceContainerHighest: t.surfaceOverlay,
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
    hoverColor: t.primary.withValues(alpha: 0.07),
    splashColor: t.primary.withValues(alpha: 0.10),
    highlightColor: t.primary.withValues(alpha: 0.08),
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.foreground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.primary.withValues(alpha: .12),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return base.textTheme.labelSmall?.copyWith(
          color: selected ? t.primary : t.mutedForeground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? t.primary : t.mutedForeground,
          size: 24,
        );
      }),
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
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
        hoverColor: t.foreground.withValues(alpha: 0.07),
        highlightColor: t.foreground.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(52, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return t.primary.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return t.primary.withValues(alpha: 0.08);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.padded,
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.primaryForeground,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(56, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.border),
      ),
      dayShape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      yearShape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return t.primary.withValues(alpha: 0.16);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return t.primary.withValues(alpha: 0.09);
        }
        return null;
      }),
      yearOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return t.primary.withValues(alpha: 0.16);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return t.primary.withValues(alpha: 0.09);
        }
        return null;
      }),
      todayBorder: BorderSide(color: t.primary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: t.border),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: TextStyle(
        color: brightness == Brightness.dark ? t.foreground : Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: brightness == Brightness.dark
            ? t.surfaceRaised
            : const Color(0xFF1A1D29),
        borderRadius: BorderRadius.circular(8),
        border: brightness == Brightness.dark
            ? Border.all(color: Colors.white.withValues(alpha: 0.10))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: t.foreground,
      displayColor: t.foreground,
    ),
  );
}
