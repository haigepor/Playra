import 'package:flutter/widgets.dart';

/// Keeps explicitly excluded surfaces on their existing component rendering.
class PlayraComponentScope extends InheritedTheme {
  const PlayraComponentScope({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PlayraComponentScope>()
          ?.enabled ??
      true;
  @override
  bool updateShouldNotify(PlayraComponentScope oldWidget) =>
      enabled != oldWidget.enabled;
  @override
  Widget wrap(BuildContext context, Widget child) =>
      PlayraComponentScope(enabled: enabled, child: child);
}
