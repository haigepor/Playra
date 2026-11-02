import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';

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
      // Other platforms keep the existing Flutter navigation.
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

/// Reserves Flutter layout space; the official Compose view paints the surface.
class NativeLiquidNavigationBar extends StatefulWidget {
  const NativeLiquidNavigationBar({
    super.key,
    required this.controller,
    required this.selectedIndex,
    required this.destinations,
  });
  final NativeLiquidNavigationController controller;
  final int selectedIndex;
  final List<NavigationDestination> destinations;

  @override
  State<NativeLiquidNavigationBar> createState() =>
      _NativeLiquidNavigationBarState();
}

class _NativeLiquidNavigationBarState extends State<NativeLiquidNavigationBar>
    with WidgetsBindingObserver {
  final _surface = GlobalKey();
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _foreground &&
        !RouteVisibility.isCoveredOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final render = _surface.currentContext?.findRenderObject();
          if (render is! RenderBox || !render.hasSize) return;
          final offset = render.localToGlobal(Offset.zero) * ratio;
          widget.controller.configure({
            'visible': visible,
            'selectedIndex': widget.selectedIndex,
            'left': offset.dx,
            'top': offset.dy,
            'width': render.size.width * ratio,
            'height': render.size.height * ratio,
            'textScale': textScale.clamp(1.0, 2.0),
            'reduceMotion': reducedMotion,
            'rtl': rtl,
            'dark': true,
            for (var i = 0; i < widget.destinations.length; i++)
              'label$i': widget.destinations[i].label,
            for (var i = 0; i < widget.destinations.length; i++)
              'icon$i': (widget.destinations[i].icon as Icon).icon!.codePoint,
          });
        });
        return SizedBox(
          key: _surface,
          width: constraints.maxWidth,
          height: 64 + 20 * (textScale - 1).clamp(0, 2),
        );
      },
    );
  }
}
