import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/presentation/theme/playra_theme.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/theme/playra_forui_theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ShadColorScheme modernHomeColors(Brightness brightness) => playraShadColors(
  brightness == Brightness.dark ? PlayraTokens.dark : PlayraTokens.light,
  brightness,
);

ThemeData modernHomeTheme(ThemeData base, {bool forceDark = false}) =>
    playraTheme(base, forceDark: forceDark);

class ModernHomeScope extends StatelessWidget {
  const ModernHomeScope({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final material = enabled && base.extension<PlayraTokens>()?.modern != true
        ? playraTheme(base)
        : base;
    return Theme(
      data: material,
      child: ShadTheme(
        data: playraShadTheme(
          material,
          textScaler: MediaQuery.textScalerOf(context),
          reduceMotion: MediaQuery.disableAnimationsOf(context),
        ),
        child: Localizations.override(
          context: context,
          delegates: const [GlobalShadLocalizations.delegate],
          child: PlayraForuiScope(child: ContentSkeletonTheme(child: child)),
        ),
      ),
    );
  }
}
