import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart'
    show FadeEffect, ScaleEffect;
import 'package:shadcn_ui/shadcn_ui.dart' hide FadeEffect, ScaleEffect;

import 'playra_tokens.dart';
import 'playra_design.dart';

ShadColorScheme playraShadColors(PlayraTokens t, Brightness brightness) {
  return brightness == Brightness.dark
      ? ShadZincColorScheme.dark(
          background: t.background,
          foreground: t.foreground,
          card: t.surface,
          cardForeground: t.foreground,
          primary: t.primary,
          primaryForeground: t.primaryForeground,
          secondary: t.muted,
          secondaryForeground: t.foreground,
          muted: t.muted,
          mutedForeground: t.mutedForeground,
          border: t.border,
          input: t.border,
          ring: t.primary,
          popover: t.surface,
          popoverForeground: t.foreground,
        )
      : ShadZincColorScheme.light(
          background: t.background,
          foreground: t.foreground,
          card: t.surface,
          cardForeground: t.foreground,
          primary: t.primary,
          primaryForeground: t.primaryForeground,
          secondary: t.muted,
          secondaryForeground: t.foreground,
          muted: t.muted,
          mutedForeground: t.mutedForeground,
          border: t.border,
          input: t.border,
          ring: t.primary,
          popover: t.surface,
          popoverForeground: t.foreground,
        );
}

/// Material is a consumer of the same Forui tokens used by native controls.
ThemeData playraTheme(
  ThemeData base, {
  bool modern = true,
  bool forceDark = true,
}) {
  final brightness = modern && forceDark ? Brightness.dark : base.brightness;
  final design = playraDesign(
    brightness,
    fontFamily: base.textTheme.bodyMedium?.fontFamily,
  );
  final t = modern
      ? PlayraTokens.fromForui(design.colors)
      : PlayraTokens.fromScheme(base.colorScheme);
  final extensions =
      base.extensions.values
          .where((e) => e is! PlayraTokens)
          .toList(growable: true)
        ..add(t);
  if (!modern) return base.copyWith(extensions: extensions);

  final c = base.colorScheme.copyWith(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.primaryForeground,
    secondary: design.colors.secondary,
    onSecondary: design.colors.secondaryForeground,
    tertiary: t.primary,
    onTertiary: t.primaryForeground,
    error: design.colors.error,
    onError: design.colors.errorForeground,
    errorContainer: design.colors.error.withValues(alpha: .1),
    onErrorContainer: design.colors.error,
    surface: t.background,
    onSurface: t.foreground,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surface,
    surfaceContainerLow: t.surface,
    surfaceContainerLowest: t.background,
    surfaceContainerHighest: t.muted,
    onSurfaceVariant: t.mutedForeground,
    outline: t.border,
    outlineVariant: t.border,
    primaryContainer: t.muted,
    onPrimaryContainer: t.primary,
    secondaryContainer: t.muted,
    onSecondaryContainer: t.primary,
    tertiaryContainer: t.muted,
    onTertiaryContainer: t.primary,
    surfaceTint: Colors.transparent,
  );
  final text = base.textTheme.apply(
    bodyColor: t.foreground,
    displayColor: t.foreground,
  );
  final body = design.typography.body;
  final display = design.typography.display;
  // Material needs complete text styles (including baseline/spacing) for fields
  // and interpolates inherit=false styles when switching appearance.
  TextStyle bridge(TextStyle? material, TextStyle forui) => material!
      .merge(forui)
      .copyWith(inherit: false, textBaseline: TextBaseline.alphabetic);
  final typography = text.copyWith(
    headlineLarge: bridge(text.headlineLarge, display.xl),
    headlineMedium: bridge(text.headlineMedium, display.xl),
    headlineSmall: bridge(text.headlineSmall, display.lg),
    titleLarge: bridge(
      text.titleLarge,
      body.sm,
    ).copyWith(fontWeight: FontWeight.w600),
    titleMedium: bridge(text.titleMedium, body.sm),
    titleSmall: bridge(text.titleSmall, body.xs),
    bodyLarge: bridge(text.bodyLarge, body.sm),
    bodyMedium: bridge(text.bodyMedium, body.sm),
    bodySmall: bridge(text.bodySmall, body.xs2),
    labelLarge: bridge(text.labelLarge, body.xs),
    labelMedium: bridge(text.labelMedium, body.xs2),
    labelSmall: bridge(text.labelSmall, body.xs2),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(PlayraRadius.control),
  );
  final button = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size(PlayraLayout.touchTarget, PlayraLayout.touchTarget),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: PlayraSpace.lg, vertical: 10),
    ),
    shape: WidgetStatePropertyAll(controlShape),
    textStyle: WidgetStatePropertyAll(typography.labelLarge),
    animationDuration: PlayraMotion.press,
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );
  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(PlayraRadius.control),
    borderSide: BorderSide(color: color),
  );

  return base.copyWith(
    extensions: extensions,
    brightness: brightness,
    colorScheme: c,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: typography,
    iconTheme: IconThemeData(color: t.mutedForeground, size: PlayraLayout.icon),
    splashFactory: NoSplash.splashFactory,
    // 保留轻量状态底色，让触控、鼠标和键盘都有可见反馈。
    highlightColor: t.primary.withValues(alpha: .12),
    hoverColor: t.primary.withValues(alpha: .08),
    focusColor: t.primary.withValues(alpha: .18),
    tabBarTheme: base.tabBarTheme.copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return t.primary.withValues(alpha: .18);
        }
        if (states.contains(WidgetState.pressed)) {
          return t.primary.withValues(alpha: .12);
        }
        if (states.contains(WidgetState.hovered)) {
          return t.primary.withValues(alpha: .08);
        }
        return null;
      }),
      splashFactory: NoSplash.splashFactory,
    ),
    dividerColor: t.border.withValues(alpha: .4),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: PlayraLayout.toolbar,
      titleTextStyle: typography.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(
        color: t.mutedForeground,
        size: PlayraLayout.icon,
      ),
      actionsIconTheme: IconThemeData(
        color: t.mutedForeground,
        size: PlayraLayout.icon,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.card),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? t.muted : t.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? t.mutedForeground
              : t.primaryForeground,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        foregroundColor: WidgetStatePropertyAll(t.primary),
        side: WidgetStatePropertyAll(BorderSide(color: t.border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        foregroundColor: WidgetStatePropertyAll(t.primary),
        minimumSize: const WidgetStatePropertyAll(
          Size(PlayraLayout.touchTarget, PlayraLayout.touchTarget),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: PlayraSpace.md,
            vertical: PlayraSpace.sm,
          ),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.mutedForeground,
        minimumSize: const Size.square(PlayraLayout.touchTarget),
        iconSize: PlayraLayout.icon,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: typography.bodyMedium?.copyWith(color: t.mutedForeground),
      hintStyle: typography.bodyMedium?.copyWith(color: t.mutedForeground),
      helperStyle: typography.bodySmall,
      border: inputBorder(t.border),
      enabledBorder: inputBorder(t.border),
      focusedBorder: inputBorder(t.primary),
      errorBorder: inputBorder(c.error),
      focusedErrorBorder: inputBorder(c.error),
      constraints: const BoxConstraints(minHeight: PlayraLayout.inputHeight),
    ),
    chipTheme: base.chipTheme.copyWith(
      brightness: brightness,
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return t.muted.withValues(alpha: .6);
        }
        if (s.contains(WidgetState.selected)) {
          return t.primary.withValues(alpha: .14);
        }
        if (s.contains(WidgetState.hovered) ||
            s.contains(WidgetState.focused)) {
          return t.muted;
        }
        return t.surface;
      }),
      backgroundColor: t.surface,
      selectedColor: t.muted,
      disabledColor: t.muted,
      labelStyle: typography.labelMedium?.copyWith(fontWeight: FontWeight.w500),
      secondaryLabelStyle: typography.labelMedium?.copyWith(
        color: t.primary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: t.border),
      shape: controlShape,
      padding: const EdgeInsets.symmetric(
        horizontal: PlayraSpace.sm,
        vertical: PlayraSpace.compact,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: PlayraSpace.xs),
      checkmarkColor: t.primary,
      deleteIconColor: t.mutedForeground,
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? t.mutedForeground.withValues(alpha: .35)
            : s.contains(WidgetState.selected)
            ? t.primary
            : t.mutedForeground,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? t.muted.withValues(alpha: .5)
            : s.contains(WidgetState.selected)
            ? t.primary.withValues(alpha: .25)
            : t.muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.border),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: t.primary,
      inactiveTrackColor: t.muted,
      thumbColor: t.primary,
      trackHeight: 2,
      trackGap: 0,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 5,
        disabledThumbRadius: 4,
        elevation: 0,
        pressedElevation: 0,
      ),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      overlayColor: t.primary.withValues(alpha: .08),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? t.mutedForeground.withValues(alpha: .35)
            : s.contains(WidgetState.selected)
            ? t.primary
            : t.mutedForeground,
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: t.barrier,
      titleTextStyle: typography.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: typography.bodyMedium?.copyWith(
        color: t.mutedForeground,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.overlay),
      ),
      constraints: const BoxConstraints(
        maxWidth: PlayraLayout.actionSheetWidth,
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: t.surface,
      modalBackgroundColor: t.surface,
      modalBarrierColor: t.barrier,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: t.mutedForeground,
      constraints: const BoxConstraints(maxWidth: PlayraLayout.sheetWidth),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PlayraRadius.overlay),
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          controlShape.copyWith(side: BorderSide(color: t.border)),
        ),
      ),
    ),
    // Navigation keeps its existing contract during the page migration.
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.muted,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.control),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
          fontSize: PlayraType.caption,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? t.primary
              : t.mutedForeground,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? t.primary
              : t.mutedForeground,
        ),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: t.surface,
      contentTextStyle: typography.bodyMedium,
      actionTextColor: t.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayraRadius.control),
        side: BorderSide(color: t.border),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      minTileHeight: PlayraLayout.listRow,
    ),
  );
}

ShadThemeData playraShadTheme(
  ThemeData material, {
  TextScaler textScaler = TextScaler.noScaling,
  bool reduceMotion = false,
}) {
  final t =
      material.extension<PlayraTokens>() ??
      PlayraTokens.fromScheme(material.colorScheme);
  final text = material.textTheme;
  final buttonHeight =
      PlayraLayout.touchTarget +
      (textScaler.scale(PlayraType.label) - PlayraType.label).clamp(
            0,
            double.infinity,
          ) *
          PlayraType.bodyHeight;
  final dialog = ShadDialogTheme(
    radius: BorderRadius.circular(PlayraRadius.overlay),
    backgroundColor: t.surface,
    padding: const EdgeInsets.all(PlayraSpace.xxl),
    gap: PlayraSpace.lg,
    titleStyle: text.headlineSmall,
    descriptionStyle: text.bodyMedium,
    constraints: const BoxConstraints(maxWidth: PlayraLayout.actionSheetWidth),
    animateIn: reduceMotion
        ? []
        : [
            FadeEffect(
              duration: PlayraMotion.dialogEnter,
              curve: PlayraMotion.curve,
            ),
            ScaleEffect(
              begin: const Offset(.98, .98),
              end: const Offset(1, 1),
              duration: PlayraMotion.dialogEnter,
              curve: PlayraMotion.curve,
            ),
          ],
    animateOut: reduceMotion
        ? []
        : [FadeEffect(begin: 1, end: 0, duration: PlayraMotion.dialogExit)],
  );
  return ShadThemeData(
    brightness: material.brightness,
    colorScheme: playraShadColors(t, material.brightness),
    radius: BorderRadius.circular(PlayraRadius.control),
    textTheme: ShadTextTheme(
      family: text.bodyMedium?.fontFamily,
      h1Large: text.headlineLarge,
      h1: text.headlineLarge,
      h2: text.headlineMedium,
      h3: text.headlineSmall,
      h4: text.titleLarge,
      p: text.bodyMedium,
      large: text.titleLarge,
      lead: text.titleMedium,
      small: text.labelLarge,
      muted: text.bodySmall,
      list: text.bodyMedium,
    ),
    cardTheme: ShadCardTheme(
      radius: BorderRadius.circular(PlayraRadius.card),
      backgroundColor: t.surface,
      padding: const EdgeInsets.all(PlayraSpace.lg),
      border: ShadBorder.all(color: t.border.withValues(alpha: .5)),
      shadows: const [],
    ),
    buttonSizesTheme: ShadButtonSizesTheme(
      regular: ShadButtonSizeTheme(
        height: buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.lg),
      ),
      sm: ShadButtonSizeTheme(
        height: buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
      ),
      lg: ShadButtonSizeTheme(
        height: buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.xxl),
      ),
      icon: ShadButtonSizeTheme(
        height: buttonHeight,
        width: buttonHeight,
        padding: EdgeInsets.zero,
      ),
    ),
    primaryButtonTheme: ShadButtonTheme(textStyle: text.labelLarge),
    outlineButtonTheme: ShadButtonTheme(textStyle: text.labelLarge),
    ghostButtonTheme: ShadButtonTheme(textStyle: text.labelLarge),
    inputTheme: ShadInputTheme(
      constraints: const BoxConstraints(minHeight: PlayraLayout.inputHeight),
      style: text.bodyMedium,
      placeholderStyle: text.bodyMedium?.copyWith(color: t.mutedForeground),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    primaryDialogTheme: dialog,
    alertDialogTheme: dialog,
    sheetTheme: ShadSheetTheme(
      backgroundColor: t.surface,
      radius: BorderRadius.circular(PlayraRadius.overlay),
      titleStyle: text.headlineSmall,
      descriptionStyle: text.bodyMedium,
      padding: const EdgeInsets.all(PlayraSpace.xl),
      animateIn: reduceMotion
          ? []
          : [
              FadeEffect(
                duration: PlayraMotion.sheetEnter,
                curve: PlayraMotion.curve,
              ),
            ],
      animateOut: reduceMotion
          ? []
          : [FadeEffect(begin: 1, end: 0, duration: PlayraMotion.sheetExit)],
      snapAnimationDuration: reduceMotion
          ? Duration.zero
          : PlayraMotion.sheetEnter,
    ),
  );
}
