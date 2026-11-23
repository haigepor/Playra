import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Page-scoped palette for the discovery/home surface.
///
/// The target visual is a soft lavender "magazine" surface. The global
/// PlayraTokens palette follows the same editorial direction; this extension
/// keeps the home/calendar specific surfaces (search fill, rail, decoration)
/// explicit without overloading the semantic component colors.
@immutable
class PlayraHomeTokens extends ThemeExtension<PlayraHomeTokens> {
  const PlayraHomeTokens({
    required this.pageBackground,
    required this.pageHighlight,
    required this.railBackground,
    required this.railSelected,
    required this.accent,
    required this.accentForeground,
    required this.vipSurfaceStart,
    required this.vipSurfaceEnd,
    required this.searchFill,
    required this.cardSurface,
    required this.cardPlaceholder,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.sectionMarkStart,
    required this.sectionMarkEnd,
  });

  static const light = PlayraHomeTokens(
    pageBackground: Color(0xfff8f8fa),
    pageHighlight: Color(0xfff8f8fa),
    railBackground: Color(0xFFE1DAF7),
    railSelected: Color(0xFFF7F2FF),
    accent: Color(0xFF7044C2),
    accentForeground: Color(0xFFFFFFFF),
    vipSurfaceStart: Color(0xFFF2E8FF),
    vipSurfaceEnd: Color(0xFFEADFFE),
    searchFill: Color(0xfff0f0f3),
    cardSurface: Color(0xFFFFFFFF),
    cardPlaceholder: Color(0xFFE4DDF0),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xff62636d),
    divider: Color(0xffd8d9df),
    sectionMarkStart: Color(0xFFFF6B6B),
    sectionMarkEnd: Color(0xFF6A7BFF),
  );

  static final dark = PlayraHomeTokens(
    pageBackground: PlayraTokens.dark.background,
    pageHighlight: PlayraTokens.dark.background,
    railBackground: PlayraTokens.dark.surface,
    railSelected: PlayraTokens.dark.primaryContainer,
    accent: PlayraTokens.dark.primary,
    accentForeground: PlayraTokens.dark.primaryForeground,
    vipSurfaceStart: PlayraTokens.dark.surface,
    vipSurfaceEnd: PlayraTokens.dark.surfaceRaised,
    searchFill: PlayraTokens.dark.surfaceRaised,
    cardSurface: PlayraTokens.dark.surface,
    cardPlaceholder: PlayraTokens.dark.muted,
    textPrimary: PlayraTokens.dark.foreground,
    textSecondary: PlayraTokens.dark.foregroundSubtle,
    divider: PlayraTokens.dark.border,
    sectionMarkStart: PlayraTokens.dark.primary,
    sectionMarkEnd: PlayraTokens.dark.primary,
  );

  final Color pageBackground;
  final Color pageHighlight;
  final Color railBackground;
  final Color railSelected;
  final Color accent;
  final Color accentForeground;
  final Color vipSurfaceStart;
  final Color vipSurfaceEnd;
  final Color searchFill;
  final Color cardSurface;
  final Color cardPlaceholder;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color sectionMarkStart;
  final Color sectionMarkEnd;

  static PlayraHomeTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  @override
  PlayraHomeTokens copyWith({
    Color? pageBackground,
    Color? pageHighlight,
    Color? railBackground,
    Color? railSelected,
    Color? accent,
    Color? accentForeground,
    Color? vipSurfaceStart,
    Color? vipSurfaceEnd,
    Color? searchFill,
    Color? cardSurface,
    Color? cardPlaceholder,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? sectionMarkStart,
    Color? sectionMarkEnd,
  }) => PlayraHomeTokens(
    pageBackground: pageBackground ?? this.pageBackground,
    pageHighlight: pageHighlight ?? this.pageHighlight,
    railBackground: railBackground ?? this.railBackground,
    railSelected: railSelected ?? this.railSelected,
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    vipSurfaceStart: vipSurfaceStart ?? this.vipSurfaceStart,
    vipSurfaceEnd: vipSurfaceEnd ?? this.vipSurfaceEnd,
    searchFill: searchFill ?? this.searchFill,
    cardSurface: cardSurface ?? this.cardSurface,
    cardPlaceholder: cardPlaceholder ?? this.cardPlaceholder,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    divider: divider ?? this.divider,
    sectionMarkStart: sectionMarkStart ?? this.sectionMarkStart,
    sectionMarkEnd: sectionMarkEnd ?? this.sectionMarkEnd,
  );

  @override
  PlayraHomeTokens lerp(covariant PlayraHomeTokens? other, double t) {
    if (other == null) return this;
    Color lerp(Color a, Color b) => Color.lerp(a, b, t)!;
    return PlayraHomeTokens(
      pageBackground: lerp(pageBackground, other.pageBackground),
      pageHighlight: lerp(pageHighlight, other.pageHighlight),
      railBackground: lerp(railBackground, other.railBackground),
      railSelected: lerp(railSelected, other.railSelected),
      accent: lerp(accent, other.accent),
      accentForeground: lerp(accentForeground, other.accentForeground),
      vipSurfaceStart: lerp(vipSurfaceStart, other.vipSurfaceStart),
      vipSurfaceEnd: lerp(vipSurfaceEnd, other.vipSurfaceEnd),
      searchFill: lerp(searchFill, other.searchFill),
      cardSurface: lerp(cardSurface, other.cardSurface),
      cardPlaceholder: lerp(cardPlaceholder, other.cardPlaceholder),
      textPrimary: lerp(textPrimary, other.textPrimary),
      textSecondary: lerp(textSecondary, other.textSecondary),
      divider: lerp(divider, other.divider),
      sectionMarkStart: lerp(sectionMarkStart, other.sectionMarkStart),
      sectionMarkEnd: lerp(sectionMarkEnd, other.sectionMarkEnd),
    );
  }
}

extension PlayraHomeTokensContext on BuildContext {
  PlayraHomeTokens get playraHomeTokens => PlayraHomeTokens.of(this);
}
