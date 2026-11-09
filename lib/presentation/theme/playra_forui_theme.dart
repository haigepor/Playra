import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

import 'playra_tokens.dart';
import 'playra_design.dart';

/// Legacy appearance keeps its user-selected palette; modern pages use Forui.
f.FThemeData playraForuiTheme(ThemeData material) {
  final design = playraDesign(
    material.brightness,
    fontFamily: material.textTheme.bodyMedium?.fontFamily,
  );
  if (material.extension<PlayraTokens>()?.modern == true) return design;
  final c = material.colorScheme;
  final colors = design.colors.copyWith(
    background: c.surface,
    foreground: c.onSurface,
    primary: c.primary,
    primaryForeground: c.onPrimary,
    secondary: c.surfaceContainer,
    secondaryForeground: c.onSurface,
    muted: c.surfaceContainerHighest,
    mutedForeground: c.onSurfaceVariant,
    card: c.surfaceContainerLow,
    border: c.outlineVariant,
    destructive: c.error,
    destructiveForeground: c.onError,
    error: c.error,
    errorForeground: c.onError,
  );
  final typeface = f.FTypeface.inherit(
    colors: colors,
    touch: true,
    fontFamily: design.typography.body.fontFamily,
  );
  return f.FThemeData(
    colors: colors,
    typography: f.FTypography(body: typeface, display: typeface),
    touch: true,
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
      accessibility: PlayraMotion.reduceOf(context)
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
