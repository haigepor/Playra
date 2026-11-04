import 'package:flutter/material.dart';

abstract final class PlayraSpace {
  static const tiny = 2.0;
  static const xs = 4.0;
  static const compact = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const section = 32.0;
}

abstract final class PlayraRadius {
  static const thumbnail = 8.0;
  static const control = 12.0;
  static const poster = 12.0;
  static const card = 16.0;
  static const hero = 20.0;
  static const overlay = 20.0;
  static const brand = 24.0;
}

abstract final class PlayraType {
  static const pageTitle = 22.0;
  static const title = 20.0;
  static const section = 18.0;
  static const item = 16.0;
  static const body = 14.0;
  static const label = 13.0;
  static const caption = 12.0;
  static const small = 11.0;
  static const micro = 10.0;
  static const bodyHeight = 1.5;
  static const readingHeight = 1.8;
}

abstract final class PlayraLayout {
  static const compactWidth = 600.0;
  static const expandedWidth = 840.0;
  static const touchTarget = 48.0;
  static const compactControl = 40.0;
  static const inputHeight = 48.0;
  static const listRow = 56.0;
  static const toolbar = 56.0;
  static const compactToolbar = 52.0;
  static const icon = 20.0;
  static const compactIcon = 18.0;
  static const actionSheetWidth = 520.0;
  static const sheetWidth = 640.0;
  static const formWidth = 760.0;
  static const readingWidth = 880.0;
  static const catalogWidth = 1120.0;

  static bool isCompact(Size size) => size.width < 380 || size.height < 700;

  static double pageInset(Size size) =>
      isCompact(size) ? PlayraSpace.lg : PlayraSpace.xl;

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final inset = pageInset(MediaQuery.sizeOf(context));
    return EdgeInsets.fromLTRB(inset, top, inset, bottom);
  }
}

abstract final class PlayraMotion {
  static const press = Duration(milliseconds: 120);
  static const state = Duration(milliseconds: 200);
  static const dialogEnter = Duration(milliseconds: 220);
  static const dialogExit = Duration(milliseconds: 180);
  static const sheetEnter = Duration(milliseconds: 250);
  static const sheetExit = Duration(milliseconds: 200);
  static const curve = Curves.easeOutCubic;
  static const reverseCurve = Curves.easeInCubic;

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

  static AnimationStyle dialog(BuildContext context, {Duration? duration}) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: duration ?? dialogEnter,
          reverseDuration: duration ?? dialogExit,
          curve: curve,
          reverseCurve: reverseCurve,
        );

  static AnimationStyle sheet(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: sheetEnter,
          reverseDuration: sheetExit,
          curve: curve,
          reverseCurve: reverseCurve,
        );
}

/// Product colors are resolved once; component and platform themes consume them.
@immutable
class PlayraTokens extends ThemeExtension<PlayraTokens> {
  const PlayraTokens({
    required this.background,
    required this.foreground,
    required this.surface,
    required this.muted,
    required this.mutedForeground,
    required this.primary,
    required this.primaryForeground,
    required this.border,
    this.modern = false,
  });

  static const dark = PlayraTokens(
    background: Color(0xff11141c),
    foreground: Color(0xffedf0f8),
    surface: Color(0xff1b202c),
    muted: Color(0xff202638),
    mutedForeground: Color(0xffa5afc5),
    primary: Color(0xffa7b7ff),
    primaryForeground: Color(0xff182142),
    border: Color(0xff30384a),
    modern: true,
  );

  static const light = PlayraTokens(
    background: Color(0xfff7f8fc),
    foreground: Color(0xff22293c),
    surface: Colors.white,
    muted: Color(0xffe9edfb),
    mutedForeground: Color(0xff647087),
    primary: Color(0xff5267d9),
    primaryForeground: Colors.white,
    border: Color(0xffe3e7f0),
    modern: true,
  );

  factory PlayraTokens.fromScheme(ColorScheme c) => PlayraTokens(
    background: c.surface,
    foreground: c.onSurface,
    surface: c.surfaceContainerLow,
    muted: c.surfaceContainerHighest,
    mutedForeground: c.onSurfaceVariant,
    primary: c.primary,
    primaryForeground: c.onPrimary,
    border: c.outlineVariant,
  );

  static PlayraTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PlayraTokens>() ??
        PlayraTokens.fromScheme(theme.colorScheme);
  }

  final Color background;
  final Color foreground;
  final Color surface;
  final Color muted;
  final Color mutedForeground;
  final Color primary;
  final Color primaryForeground;
  final Color border;
  final bool modern;

  Color get barrier => Colors.black.withValues(alpha: .6);

  @override
  PlayraTokens copyWith({
    Color? background,
    Color? foreground,
    Color? surface,
    Color? muted,
    Color? mutedForeground,
    Color? primary,
    Color? primaryForeground,
    Color? border,
    bool? modern,
  }) => PlayraTokens(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    surface: surface ?? this.surface,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    border: border ?? this.border,
    modern: modern ?? this.modern,
  );

  @override
  PlayraTokens lerp(covariant PlayraTokens? other, double t) {
    if (other == null) return this;
    return PlayraTokens(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      border: Color.lerp(border, other.border, t)!,
      modern: t < .5 ? modern : other.modern,
    );
  }
}
