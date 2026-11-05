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

/// Static semantic colors for standalone/static contexts.
abstract final class PlayraColors {
  // Functional semantics
  static const success = Color(0xff4ade80);
  static const successContainer = Color(0xff152e22);
  static const warning = Color(0xfffbbf24);
  static const warningContainer = Color(0xff362a12);
  static const destructive = Color(0xfff87171);
  static const destructiveContainer = Color(0xff381a1c);
  static const info = Color(0xff60a5fa);
  static const infoContainer = Color(0xff172a42);

  // Rank medals
  static const rankGold = Color(0xfffbbf24);
  static const rankSilver = Color(0xffcbd5e1);
  static const rankBronze = Color(0xfff97316);

  // Media collection states
  static const watching = Color(0xff34d399);
  static const planToWatch = Color(0xffa7b7ff);
  static const watched = Color(0xff94a3b8);
  static const onHold = Color(0xfffbbf24);
  static const abandoned = Color(0xfff87171);

  // Skeleton shimmer
  static const shimmerBase = Color(0xff1e2433);
  static const shimmerHighlight = Color(0xff2a3245);
}

/// Product colors are resolved once; component and platform themes consume them.
@immutable
class PlayraTokens extends ThemeExtension<PlayraTokens> {
  const PlayraTokens({
    required this.background,
    required this.foreground,
    required this.surface,
    this.surfaceRaised = const Color(0xff222838),
    this.surfaceOverlay = const Color(0xff283042),
    required this.muted,
    required this.mutedForeground,
    this.foregroundSubtle = const Color(0xff737f99),
    required this.primary,
    required this.primaryForeground,
    this.primaryContainer = const Color(0xff242c4c),
    required this.border,
    this.borderSubtle = const Color(0xff222a3a),
    this.success = PlayraColors.success,
    this.successContainer = PlayraColors.successContainer,
    this.warning = PlayraColors.warning,
    this.warningContainer = PlayraColors.warningContainer,
    this.destructive = PlayraColors.destructive,
    this.destructiveContainer = PlayraColors.destructiveContainer,
    this.info = PlayraColors.info,
    this.infoContainer = PlayraColors.infoContainer,
    this.rankGold = PlayraColors.rankGold,
    this.rankSilver = PlayraColors.rankSilver,
    this.rankBronze = PlayraColors.rankBronze,
    this.watching = PlayraColors.watching,
    this.planToWatch = PlayraColors.planToWatch,
    this.watched = PlayraColors.watched,
    this.onHold = PlayraColors.onHold,
    this.abandoned = PlayraColors.abandoned,
    this.shimmerBase = PlayraColors.shimmerBase,
    this.shimmerHighlight = PlayraColors.shimmerHighlight,
    this.modern = false,
  });

  static const dark = PlayraTokens(
    background: Color(0xff11141c),
    foreground: Color(0xffedf0f8),
    surface: Color(0xff1b202c),
    surfaceRaised: Color(0xff222838),
    surfaceOverlay: Color(0xff283042),
    muted: Color(0xff202638),
    mutedForeground: Color(0xffa5afc5),
    foregroundSubtle: Color(0xff737f99),
    primary: Color(0xffa7b7ff),
    primaryForeground: Color(0xff182142),
    primaryContainer: Color(0xff242c4c),
    border: Color(0xff30384a),
    borderSubtle: Color(0xff222a3a),
    success: PlayraColors.success,
    successContainer: PlayraColors.successContainer,
    warning: PlayraColors.warning,
    warningContainer: PlayraColors.warningContainer,
    destructive: PlayraColors.destructive,
    destructiveContainer: PlayraColors.destructiveContainer,
    info: PlayraColors.info,
    infoContainer: PlayraColors.infoContainer,
    rankGold: PlayraColors.rankGold,
    rankSilver: PlayraColors.rankSilver,
    rankBronze: PlayraColors.rankBronze,
    watching: PlayraColors.watching,
    planToWatch: PlayraColors.planToWatch,
    watched: PlayraColors.watched,
    onHold: PlayraColors.onHold,
    abandoned: PlayraColors.abandoned,
    shimmerBase: PlayraColors.shimmerBase,
    shimmerHighlight: PlayraColors.shimmerHighlight,
    modern: true,
  );

  static const light = PlayraTokens(
    background: Color(0xfff7f8fc),
    foreground: Color(0xff22293c),
    surface: Colors.white,
    surfaceRaised: Color(0xfff0f3fa),
    surfaceOverlay: Color(0xffe8ecf6),
    muted: Color(0xffe9edfb),
    mutedForeground: Color(0xff647087),
    foregroundSubtle: Color(0xff939eb5),
    primary: Color(0xff5267d9),
    primaryForeground: Colors.white,
    primaryContainer: Color(0xffe0e6ff),
    border: Color(0xffe3e7f0),
    borderSubtle: Color(0xffedf0f7),
    success: Color(0xff16a34a),
    successContainer: Color(0xffdcfce7),
    warning: Color(0xffd97706),
    warningContainer: Color(0xfffef3c7),
    destructive: Color(0xffdc2626),
    destructiveContainer: Color(0xfffee2e2),
    info: Color(0xff2563eb),
    infoContainer: Color(0xffdbeafe),
    rankGold: Color(0xffd97706),
    rankSilver: Color(0xff64748b),
    rankBronze: Color(0xffc2410c),
    watching: Color(0xff059669),
    planToWatch: Color(0xff4f46e5),
    watched: Color(0xff64748b),
    onHold: Color(0xffd97706),
    abandoned: Color(0xffdc2626),
    shimmerBase: Color(0xffe2e8f0),
    shimmerHighlight: Color(0xfff1f5f9),
    modern: true,
  );

  factory PlayraTokens.fromScheme(ColorScheme c) => PlayraTokens(
    background: c.surface,
    foreground: c.onSurface,
    surface: c.surfaceContainerLow,
    surfaceRaised: c.surfaceContainer,
    surfaceOverlay: c.surfaceContainerHigh,
    muted: c.surfaceContainerHighest,
    mutedForeground: c.onSurfaceVariant,
    foregroundSubtle: c.onSurfaceVariant.withValues(alpha: .75),
    primary: c.primary,
    primaryForeground: c.onPrimary,
    primaryContainer: c.primaryContainer,
    border: c.outlineVariant,
    borderSubtle: c.outlineVariant.withValues(alpha: .5),
    destructive: c.error,
    destructiveContainer: c.errorContainer,
  );

  static const radiusXs = 4.0;
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 20.0;

  static PlayraTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PlayraTokens>() ??
        PlayraTokens.fromScheme(theme.colorScheme);
  }

  final Color background;
  final Color foreground;
  Color get foregroundMuted => mutedForeground;
  Color get cardBackground => surface;
  final Color foregroundSubtle;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color muted;
  final Color mutedForeground;
  final Color primary;
  final Color primaryForeground;
  final Color primaryContainer;
  final Color border;
  final Color borderSubtle;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color destructive;
  final Color destructiveContainer;
  final Color info;
  final Color infoContainer;
  final Color rankGold;
  final Color rankSilver;
  final Color rankBronze;
  final Color watching;
  final Color planToWatch;
  final Color watched;
  final Color onHold;
  final Color abandoned;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final bool modern;

  Color get barrier => Colors.black.withValues(alpha: .6);

  @override
  PlayraTokens copyWith({
    Color? background,
    Color? foreground,
    Color? foregroundMuted,
    Color? foregroundSubtle,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? muted,
    Color? mutedForeground,
    Color? primary,
    Color? primaryForeground,
    Color? primaryContainer,
    Color? border,
    Color? borderSubtle,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? destructive,
    Color? destructiveContainer,
    Color? info,
    Color? infoContainer,
    Color? rankGold,
    Color? rankSilver,
    Color? rankBronze,
    Color? watching,
    Color? planToWatch,
    Color? watched,
    Color? onHold,
    Color? abandoned,
    Color? shimmerBase,
    Color? shimmerHighlight,
    bool? modern,
  }) => PlayraTokens(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    foregroundSubtle: foregroundSubtle ?? this.foregroundSubtle,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    border: border ?? this.border,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
    destructive: destructive ?? this.destructive,
    destructiveContainer: destructiveContainer ?? this.destructiveContainer,
    info: info ?? this.info,
    infoContainer: infoContainer ?? this.infoContainer,
    rankGold: rankGold ?? this.rankGold,
    rankSilver: rankSilver ?? this.rankSilver,
    rankBronze: rankBronze ?? this.rankBronze,
    watching: watching ?? this.watching,
    planToWatch: planToWatch ?? this.planToWatch,
    watched: watched ?? this.watched,
    onHold: onHold ?? this.onHold,
    abandoned: abandoned ?? this.abandoned,
    shimmerBase: shimmerBase ?? this.shimmerBase,
    shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    modern: modern ?? this.modern,
  );

  @override
  PlayraTokens lerp(covariant PlayraTokens? other, double t) {
    if (other == null) return this;
    return PlayraTokens(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      foregroundSubtle: Color.lerp(foregroundSubtle, other.foregroundSubtle, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      destructiveContainer: Color.lerp(
        destructiveContainer,
        other.destructiveContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      rankGold: Color.lerp(rankGold, other.rankGold, t)!,
      rankSilver: Color.lerp(rankSilver, other.rankSilver, t)!,
      rankBronze: Color.lerp(rankBronze, other.rankBronze, t)!,
      watching: Color.lerp(watching, other.watching, t)!,
      planToWatch: Color.lerp(planToWatch, other.planToWatch, t)!,
      watched: Color.lerp(watched, other.watched, t)!,
      onHold: Color.lerp(onHold, other.onHold, t)!,
      abandoned: Color.lerp(abandoned, other.abandoned, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
      modern: t < .5 ? modern : other.modern,
    );
  }
}

extension PlayraTokensContextExtension on BuildContext {
  PlayraTokens get playraTokens => PlayraTokens.of(this);
}
