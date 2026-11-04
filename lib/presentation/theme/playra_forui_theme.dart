import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart' as f;

import 'playra_tokens.dart';

f.FThemeData playraForuiTheme(ThemeData material) {
  final t =
      material.extension<PlayraTokens>() ??
      PlayraTokens.fromScheme(material.colorScheme);
  final base = material.brightness == Brightness.dark
      ? f.FTheme.neutral.dark.touch
      : f.FTheme.neutral.light.touch;
  final colors = base.colors.copyWith(
    background: t.background,
    foreground: t.foreground,
    primary: t.primary,
    primaryForeground: t.primaryForeground,
    secondary: t.muted,
    secondaryForeground: t.foreground,
    muted: t.muted,
    mutedForeground: t.mutedForeground,
    card: t.surface,
    border: t.border,
    barrier: t.barrier,
    error: material.colorScheme.error,
    errorForeground: material.colorScheme.onError,
  );
  final family =
      material.textTheme.bodyMedium?.fontFamily ??
      f.FTypeface.defaultFontFamily;
  TextStyle text(double size) => TextStyle(
    fontFamily: family,
    color: t.foreground,
    fontSize: size,
    height: PlayraType.bodyHeight,
  );
  final typography = f.FTypography(
    body: f.FTypeface(
      fontFamily: family,
      xs2: text(PlayraType.small),
      xs: text(PlayraType.caption),
      sm: text(PlayraType.body),
      md: text(PlayraType.body),
      lg: text(PlayraType.item),
      xl: text(PlayraType.section),
      xl2: text(PlayraType.title),
    ),
    display: f.FTypeface(
      fontFamily: family,
      xs: text(PlayraType.label),
      sm: text(PlayraType.item),
      md: text(PlayraType.section),
      lg: text(PlayraType.title),
      xl: text(PlayraType.pageTitle),
    ),
  );
  final inherited = f.FStyle.inherit(
    colors: colors,
    typography: typography,
    touch: true,
  );
  final style = f.FStyle(
    formFieldStyle: inherited.formFieldStyle,
    focusedOutlineStyle: f.FFocusedOutlineStyle(
      color: t.primary,
      borderRadius: BorderRadius.circular(PlayraRadius.control),
    ),
    iconStyle: IconThemeData(size: PlayraLayout.icon, color: t.foreground),
    sizes: inherited.sizes,
    tappableStyle: inherited.tappableStyle,
    borderRadius: f.FBorderRadius(
      sm: BorderRadius.circular(PlayraRadius.thumbnail),
      md: BorderRadius.circular(PlayraRadius.control),
      lg: BorderRadius.circular(PlayraRadius.card),
      xl: BorderRadius.circular(PlayraRadius.overlay),
    ),
    pagePadding: const EdgeInsets.all(PlayraSpace.lg),
    shadow: const [],
  );
  return f.FThemeData(
    colors: colors,
    typography: typography,
    style: style,
    touch: true,
    tileGroupStyle:
        f.FTileGroupStyle.inherit(
          colors: colors,
          typography: typography,
          style: style,
          hapticFeedback: base.hapticFeedback,
        ).copyWith(
          decoration: f.DecorationDelta.value(
            ShapeDecoration(
              color: t.surface,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(PlayraRadius.card),
                side: BorderSide(color: t.border),
              ),
            ),
          ),
        ),
    dialogStyle: f.FDialogStyle(
      decoration: ShapeDecoration(
        color: t.surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(PlayraRadius.overlay),
          side: BorderSide(color: t.border),
        ),
      ),
      titleTextStyle: text(
        PlayraType.section,
      ).copyWith(fontWeight: FontWeight.w600, height: 1.25),
      bodyTextStyle: text(PlayraType.body).copyWith(color: t.mutedForeground),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: PlayraSpace.lg,
        vertical: PlayraSpace.xxl,
      ),
      slidePressHapticFeedback: HapticFeedback.selectionClick,
    ),
  );
}

class PlayraForuiScope extends StatelessWidget {
  const PlayraForuiScope({
    super.key,
    required this.child,
    this.withOverlays = false,
  });
  final Widget child;
  final bool withOverlays;

  /// Standalone recovery pages also need Forui's platform and accessibility scopes.
  static Widget ensure(BuildContext context, WidgetBuilder builder) =>
      context.dependOnInheritedWidgetOfExactType<_ForuiHost>() != null
      ? builder(context)
      : PlayraForuiScope(child: Builder(builder: builder));

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    delegates: f.FLocalizations.localizationsDelegates,
    child: f.FTheme(
      data: playraForuiTheme(Theme.of(context)),
      accessibility: MediaQuery.disableAnimationsOf(context)
          ? f.FAccessibility(
              accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
              motion: f.FAccessibilityMotion.disabled,
              focusHighlight:
                  FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional,
            )
          : null,
      motion: f.FThemeMotion(
        duration: PlayraMotion.duration(context, PlayraMotion.state),
        curve: PlayraMotion.curve,
      ),
      child: _ForuiHost(
        child: withOverlays
            ? f.FToaster(child: f.FTooltipGroup(child: child))
            : child,
      ),
    ),
  );
}

class _ForuiHost extends InheritedWidget {
  const _ForuiHost({required super.child});
  @override
  bool updateShouldNotify(_ForuiHost oldWidget) => false;
}

mixin PlayraForuiComponent on StatelessWidget {
  Widget buildForui(BuildContext context);
  @override
  Widget build(BuildContext context) =>
      PlayraForuiScope.ensure(context, buildForui);
}
