import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// Forui owns component colors, typography, radii and interaction states.
/// Only brand colors are overridden; touch accessibility is configured below.
f.FThemeData playraDesign(Brightness brightness, {String? fontFamily}) {
  final base = brightness == Brightness.dark
      ? f.FTheme.neutral.dark.touch
      : f.FTheme.neutral.light.touch;
  final colors = base.colors.copyWith(
    primary: brightness == Brightness.dark
        ? const Color(0xffa7b7ff)
        : const Color(0xff5267d9),
    primaryForeground: brightness == Brightness.dark
        ? const Color(0xff182142)
        : Colors.white,
  );
  final typeface = f.FTypeface.inherit(
    colors: colors,
    touch: true,
    fontFamily: fontFamily ?? f.FTypeface.defaultFontFamily,
  );
  final typography = f.FTypography(body: typeface, display: typeface);
  final style = f.FStyle.inherit(
    colors: colors,
    typography: typography,
    touch: true,
  );
  final navigation = f.FBottomNavigationBarStyle.inherit(
    colors: colors,
    typography: typography,
    style: style,
  );
  return f.FThemeData(
    colors: colors,
    typography: typography,
    style: style,
    touch: true,
    tabsStyle:
        f.FTabsStyle.inherit(
          colors: colors,
          typography: typography,
          style: style,
        ).copyWith(
          minHeight: 48,
          padding: const f.EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
          decoration: f.DecorationDelta.value(
            BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
          ),
          indicatorDecoration: f.DecorationDelta.value(
            BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.primary, width: 2),
              ),
            ),
          ),
          indicatorSize: f.FTabBarIndicatorSize.label,
        ),
    bottomNavigationBarStyle: navigation.copyWith(
      itemStyle: navigation.itemStyle.copyWith(
        // Navigation labels remain readable on phones at the caption size.
        textStyle: f.FVariants.from(
          typeface.xs2.copyWith(color: colors.mutedForeground, height: 1.5),
          variants: {
            [f.FTappableVariant.selected]: f.TextStyleDelta.delta(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          },
        ),
      ),
    ),
  );
}
