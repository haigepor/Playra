import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

class StateIconBadge extends StatelessWidget {
  const StateIconBadge({
    super.key,
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipPath(
      clipper: const _StateShapeClipper(),
      child: ColoredBox(
        color: backgroundColor,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: iconSize, color: foregroundColor),
        ),
      ),
    ),
  );
}

class _StateShapeClipper extends CustomClipper<Path> {
  const _StateShapeClipper();

  static final _path = MaterialShapes.cookie4Sided.toPath();

  @override
  Path getClip(Size size) => _path.transform(
    Matrix4.diagonal3Values(size.width, size.height, 1).storage,
  );

  @override
  bool shouldReclip(_StateShapeClipper oldClipper) => false;
}

class StateActionButton extends StatelessWidget {
  const StateActionButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.reserveText,
  }) : _tonal = false;

  const StateActionButton.tonal({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.reserveText,
  }) : _tonal = true;

  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;

  /// Reserves label space for a longer status without changing button size.
  final String? reserveText;
  final bool _tonal;

  static ButtonStyle styleOf(BuildContext context) {
    if (ModernSettingsScope.isActiveOf(context)) {
      return Theme.of(context).filledButtonTheme.style ?? const ButtonStyle();
    }
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: PlayraSpace.xxl,
          vertical: PlayraSpace.md,
        ),
      ),
      shape: WidgetStateProperty.resolveWith(
        (states) => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            states.contains(WidgetState.pressed) ? 16 : 28,
          ),
        ),
      ),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(text, textAlign: TextAlign.center);
    final content = reserveText == null
        ? label
        : Stack(
            alignment: Alignment.center,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: Text(reserveText!, textAlign: TextAlign.center),
              ),
              label,
            ],
          );
    if (PlayraComponentScope.enabledOf(context)) {
      final button = _tonal ? PlayraButton.tonal : PlayraButton.new;
      return button(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: PlayraLayout.compactIcon),
        child: content,
      );
    }
    if (ModernSettingsScope.isActiveOf(context)) {
      final button = _tonal ? ShadButton.secondary : ShadButton.new;
      return button(
        onPressed: onPressed,
        leading: icon == null
            ? null
            : Icon(icon, size: PlayraLayout.compactIcon),
        child: content,
      );
    }
    final button = _tonal ? FilledButton.tonalIcon : FilledButton.icon;
    return button(
      onPressed: onPressed,
      style: styleOf(context),
      icon: icon == null ? null : Icon(icon, size: PlayraLayout.icon),
      label: content,
    );
  }
}
