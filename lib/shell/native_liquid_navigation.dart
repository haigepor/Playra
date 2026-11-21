import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/shell/playra_bottom_nav.dart';

/// Dart bridge for the official Kyant0 AndroidLiquidGlass
/// `LiquidBottomTabs` component. The native Compose view paints the real
/// liquid-glass surface; this widget only reserves its Flutter layout slot.
class NativeLiquidNavigationController extends ChangeNotifier {
  NativeLiquidNavigationController({required this.onSelected});

  static const channel = MethodChannel('com.predidit.kazumi/liquid_navigation');

  final ValueChanged<int> onSelected;
  bool supported = false;
  bool _disposed = false;
  bool _visible = false;
  bool _frameQueued = false;
  Map<String, Object?>? _configuration;

  Future<Map<String, dynamic>?> diagnostics() =>
      channel.invokeMapMethod<String, dynamic>('diagnostics');

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'selectTab' && !_disposed) {
        final index = call.arguments;
        if (index is int && index >= 0 && index < 4) onSelected(index);
      }
    });
    try {
      final ready = await channel.invokeMethod<bool>('initialize') ?? false;
      if (_disposed) {
        if (ready) await channel.invokeMethod<void>('dispose');
        return;
      }
      supported = ready;
      notifyListeners();
    } on MissingPluginException {
      // Non-Android targets keep the Flutter fallback.
    } on PlatformException catch (error) {
      debugPrint('Native liquid navigation unavailable: ${error.code}');
    }
  }

  void configure(Map<String, Object?> configuration) {
    if (_disposed || !supported || mapEquals(_configuration, configuration)) {
      return;
    }
    _configuration = configuration;
    _visible = configuration['visible'] == true;
    unawaited(channel.invokeMethod<void>('update', configuration));
  }

  void invalidateBackdrop() {
    if (_disposed || !supported || !_visible || _frameQueued) return;
    _frameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (!_disposed && supported && _visible) {
        unawaited(channel.invokeMethod<void>('invalidateBackdrop'));
      }
    });
  }

  void hide() {
    if (_disposed || !supported || !_visible) return;
    _visible = false;
    _configuration = null;
    unawaited(channel.invokeMethod<void>('hide'));
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    if (supported) unawaited(channel.invokeMethod<void>('dispose'));
    super.dispose();
  }
}

/// Reserves the native Compose bar's layout slot.
///
/// The actual pixels are painted in the Android window overlay by
/// [LiquidNavigationHost], using a PixelCopy of the Flutter surface as the
/// backdrop for the real lens/blur effect.
class NativeLiquidNavigationBar extends StatefulWidget {
  const NativeLiquidNavigationBar({
    super.key,
    required this.controller,
    required this.selectedIndex,
    required this.destinations,
  });

  final NativeLiquidNavigationController controller;
  final int selectedIndex;
  final List<PlayraNavDestination> destinations;

  @override
  State<NativeLiquidNavigationBar> createState() =>
      _NativeLiquidNavigationBarState();
}

class _NativeLiquidNavigationBarState extends State<NativeLiquidNavigationBar>
    with WidgetsBindingObserver {
  final _surface = GlobalKey();
  bool _foreground = true;
  Animation<double>? _routeAnimation;
  Animation<double>? _secondaryAnimation;
  bool _routeSettled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _bindAnimations(route?.animation, route?.secondaryAnimation);
  }

  void _bindAnimations(
    Animation<double>? primary,
    Animation<double>? secondary,
  ) {
    if (_routeAnimation != primary) {
      _routeAnimation?.removeListener(_handleRouteAnimationChanged);
      _routeAnimation?.removeStatusListener(_handleRouteAnimationStatusChanged);
      _routeAnimation = primary;
      _routeAnimation?.addListener(_handleRouteAnimationChanged);
      _routeAnimation?.addStatusListener(_handleRouteAnimationStatusChanged);
    }
    if (_secondaryAnimation != secondary) {
      _secondaryAnimation?.removeListener(_handleRouteAnimationChanged);
      _secondaryAnimation?.removeStatusListener(
        _handleRouteAnimationStatusChanged,
      );
      _secondaryAnimation = secondary;
      _secondaryAnimation?.addListener(_handleRouteAnimationChanged);
      _secondaryAnimation?.addStatusListener(
        _handleRouteAnimationStatusChanged,
      );
    }
    _routeSettled = _computeRouteSettled();
  }

  bool _computeRouteSettled() =>
      (_routeAnimation?.isCompleted ?? true) &&
      (_secondaryAnimation?.isDismissed ?? true);

  void _handleRouteAnimationChanged() {
    final settled = _computeRouteSettled();
    if (settled != _routeSettled && mounted) {
      setState(() => _routeSettled = settled);
    }
  }

  void _handleRouteAnimationStatusChanged(AnimationStatus _) {
    _handleRouteAnimationChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      widget.controller.hide();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void deactivate() {
    widget.controller.hide();
    super.deactivate();
  }

  @override
  void dispose() {
    _bindAnimations(null, null);
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final visible =
        _foreground &&
        _routeSettled &&
        (route?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final render = _surface.currentContext?.findRenderObject();
          if (render is! RenderBox || !render.hasSize) return;
          final scaffold = Scaffold.maybeOf(
            context,
          )?.context.findRenderObject();
          final offset =
              render.localToGlobal(
                Offset.zero,
                ancestor: scaffold is RenderBox && scaffold.hasSize
                    ? scaffold
                    : null,
              ) *
              ratio;
          widget.controller.configure({
            'visible': visible,
            'selectedIndex': widget.selectedIndex,
            'left': offset.dx,
            'top': offset.dy,
            'width': render.size.width * ratio,
            'height': render.size.height * ratio,
            'textScale': textScale.clamp(1.0, 1.3),
            'reduceMotion': MediaQuery.disableAnimationsOf(context),
            'rtl': rtl,
            'dark': dark,
            for (var i = 0; i < widget.destinations.length; i++)
              'label$i': widget.destinations[i].label,
            for (var i = 0; i < widget.destinations.length; i++)
              'icon$i': widget.destinations[i].icon.codePoint,
          });
        });
        return SizedBox(
          key: _surface,
          width: constraints.maxWidth,
          height: 48 + 14 * (textScale - 1).clamp(0, 2),
        );
      },
    );
  }
}
