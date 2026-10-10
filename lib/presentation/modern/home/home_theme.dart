import 'package:flutter/material.dart';
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

/// 页内杂志主题继承字体和明暗模式，品牌色集中定义，便于统一调整。
ThemeData modernHomeTheme(ThemeData base) {
  final zinc = modernHomeColors(base.brightness);
  return base.copyWith(
    scaffoldBackgroundColor: zinc.background,
    colorScheme: base.colorScheme.copyWith(
      primary: zinc.primary,
      onPrimary: zinc.primaryForeground,
      surface: zinc.background,
      onSurface: zinc.foreground,
      surfaceContainerHighest: zinc.muted,
      surfaceContainerLow: zinc.card,
      onSurfaceVariant: zinc.mutedForeground,
      outline: zinc.border,
      outlineVariant: zinc.border,
      secondaryContainer: zinc.muted,
      onSecondaryContainer: zinc.primary,
    ),
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
    final material = modernHomeTheme(Theme.of(context));
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
          child: child,
        ),
      ),
    );
  }
}
