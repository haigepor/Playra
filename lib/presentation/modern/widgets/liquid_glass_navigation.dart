import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Samples only the area beneath the dock; the dock itself is outside this layer.
class LiquidGlassBackdropController extends ChangeNotifier {
  final sourceKey = GlobalKey();
  final _clock = Stopwatch()..start();
  Rect? _surface;
  double _pixelRatio = 1.5;
  _GlassSnapshot? _snapshot;
  Timer? _timer;
  bool _queued = false, _busy = false, _dirty = false, _disposed = false;
  bool _buildingSnapshot = false;
  int _lastCapture = -100000;
  VoidCallback? _nativeSourceFrame;

  void setNativeSourceFrame(VoidCallback? callback) {
    _nativeSourceFrame = callback;
    if (callback != null) {
      _timer?.cancel();
      _timer = null;
      _dirty = false;
      _snapshot?.image.dispose();
      _snapshot = null;
    }
  }

  void setSurface(Rect surface, double devicePixelRatio) {
    final pixelRatio = math.min(devicePixelRatio, 1.5);
    if (_surface == surface && _pixelRatio == pixelRatio && _snapshot != null) {
      return;
    }
    _surface = surface;
    _pixelRatio = pixelRatio;
    invalidate();
  }

  void sourceDidComposite() {
    if (_nativeSourceFrame != null) {
      _nativeSourceFrame!();
      return;
    }
    if (!_buildingSnapshot) invalidate();
  }

  void invalidate() {
    if (_disposed || _nativeSourceFrame != null) return;
    _dirty = true;
    if (_busy || _queued || _timer != null || _surface == null) return;
    final wait = 42000 - (_clock.elapsedMicroseconds - _lastCapture);
    if (wait > 0) {
      _timer = Timer(Duration(microseconds: wait), () {
        _timer = null;
        invalidate();
      });
      return;
    }
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed && _dirty) unawaited(_capture());
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  Future<void> _capture() async {
    if (_nativeSourceFrame != null) return;
    final render = sourceKey.currentContext?.findRenderObject();
    if (render is! _GlassSource || !render.canCapture) {
      return;
    }
    final surface = _surface!;
    final region = surface.inflate(18).intersect(Offset.zero & render.size);
    if (region.isEmpty) return;
    _dirty = false;
    _busy = true;
    _lastCapture = _clock.elapsedMicroseconds;
    try {
      // toImage builds a separate scene synchronously; it must not invalidate itself.
      _buildingSnapshot = true;
      late Future<ui.Image> pending;
      try {
        pending = render.capture(region, pixelRatio: _pixelRatio);
      } finally {
        _buildingSnapshot = false;
      }
      final image = await pending;
      if (_disposed || _nativeSourceFrame != null || surface != _surface) {
        image.dispose();
      } else {
        final previous = _snapshot;
        _snapshot = _GlassSnapshot(
          image,
          region.size,
          surface.topLeft - region.topLeft,
        );
        notifyListeners();
        previous?.image.dispose();
      }
    } catch (error) {
      debugPrint('Liquid glass backdrop unavailable: ${error.runtimeType}');
    } finally {
      _busy = false;
      if (_dirty && !_disposed) invalidate();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _snapshot?.image.dispose();
    _snapshot = null;
    super.dispose();
  }
}

class _GlassSnapshot {
  const _GlassSnapshot(this.image, this.size, this.offset);
  final ui.Image image;
  final Size size;
  final Offset offset;
}

class LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  LiquidGlassBackdrop({required this.controller, required Widget child})
    : super(key: controller.sourceKey, child: child);
  final LiquidGlassBackdropController controller;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _GlassSource(controller);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _GlassSource).controller = controller;
  }
}

class _GlassSource extends RenderRepaintBoundary {
  _GlassSource(this.controller);
  LiquidGlassBackdropController controller;
  bool get canCapture => hasSize && layer is OffsetLayer;

  Future<ui.Image> capture(Rect region, {required double pixelRatio}) =>
      (layer! as OffsetLayer).toImage(region, pixelRatio: pixelRatio);

  @override
  OffsetLayer updateCompositedLayer({
    required covariant _GlassSourceLayer? oldLayer,
  }) =>
      (oldLayer ?? _GlassSourceLayer())
        ..onComposite = controller.sourceDidComposite;
}

class _GlassSourceLayer extends OffsetLayer {
  VoidCallback? onComposite;
  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    onComposite?.call();
  }
}

/// Flutter counterpart to the backdrop/lens interaction in AndroidLiquidGlass.
/// Reference: github.com/Kyant0/AndroidLiquidGlass, LiquidBottomTabs.
class LiquidGlassNavigationBar extends StatefulWidget {
  const LiquidGlassNavigationBar({
    super.key,
    required this.backdrop,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });
  final LiquidGlassBackdropController backdrop;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  @override
  State<LiquidGlassNavigationBar> createState() =>
      _LiquidGlassNavigationBarState();
}

class _LiquidGlassNavigationBarState extends State<LiquidGlassNavigationBar>
    with TickerProviderStateMixin {
  static final _program = ui.FragmentProgram.fromAsset(
    'assets/runtime_shaders/liquid_navigation.frag',
  );
  final _surfaceKey = GlobalKey();
  late final _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late Listenable _updates;
  ui.FragmentShader? _shader;
  bool _dragging = false;
  double _width = 1;
  int? _target;

  @override
  void initState() {
    super.initState();
    _updates = Listenable.merge([_position, _press, widget.backdrop]);
    _program
        .then((program) {
          if (mounted) setState(() => _shader = program.fragmentShader());
        })
        .catchError((Object error) {
          debugPrint('Liquid glass shader unavailable: ${error.runtimeType}');
        });
  }

  @override
  void didUpdateWidget(LiquidGlassNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backdrop != widget.backdrop) {
      _updates = Listenable.merge([_position, _press, widget.backdrop]);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex && !_dragging) {
      _settle(widget.selectedIndex);
    }
  }

  void _settle(int index) {
    if (_target == index && _position.isAnimating) return;
    _target = index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = index.toDouble();
    } else {
      _position.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 420, damping: 34),
          _position.value,
          index.toDouble(),
          _position.velocity,
        ),
      );
    }
  }

  void _syncSurface() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final surface = _surfaceKey.currentContext?.findRenderObject();
      final source = widget.backdrop.sourceKey.currentContext
          ?.findRenderObject();
      if (surface is RenderBox &&
          source is RenderBox &&
          surface.hasSize &&
          source.hasSize) {
        final offset = source.globalToLocal(surface.localToGlobal(Offset.zero));
        widget.backdrop.setSurface(
          offset & surface.size,
          MediaQuery.devicePixelRatioOf(context),
        );
      }
    });
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final height = 60.0 + 20 * (scale - 1).clamp(0, 2);
    final theme = Theme.of(context);
    final tokens = PlayraTokens.of(context);
    _syncSurface();
    return LayoutBuilder(
      builder: (context, bounds) {
        _width = bounds.maxWidth;
        return SizedBox(
          key: _surfaceKey,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x65000000),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: Listener(
                onPointerDown: (_) => _press.forward(),
                onPointerUp: (_) => _press.reverse(),
                onPointerCancel: (_) => _press.reverse(),
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    _dragging = true;
                    _position.stop();
                  },
                  onHorizontalDragUpdate: (details) {
                    var value =
                        details.localPosition.dx /
                            (_width / widget.destinations.length) -
                        .5;
                    if (Directionality.of(context) == TextDirection.rtl) {
                      value = widget.destinations.length - 1 - value;
                    }
                    _position.value = value
                        .clamp(0, widget.destinations.length - 1)
                        .toDouble();
                  },
                  onHorizontalDragEnd: (_) {
                    _dragging = false;
                    final index = _position.value.round().clamp(
                      0,
                      widget.destinations.length - 1,
                    );
                    _settle(index);
                    widget.onDestinationSelected(index);
                  },
                  onHorizontalDragCancel: () {
                    _dragging = false;
                    _settle(widget.selectedIndex);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: _updates,
                        builder: (context, _) {
                          final snapshot = widget.backdrop._snapshot;
                          if (_shader == null || snapshot == null) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: tokens.surface.withValues(alpha: 0.85),
                                border: Border.all(
                                  color: tokens.borderSubtle.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(height / 2),
                              ),
                            );
                          }
                          final logical = _position.value.clamp(
                            0.0,
                            widget.destinations.length - 1.0,
                          );
                          final physical =
                              Directionality.of(context) == TextDirection.rtl
                              ? widget.destinations.length - 1 - logical
                              : logical;
                          return CustomPaint(
                            key: const ValueKey('liquid-navigation-refraction'),
                            painter: _GlassPainter(
                              _shader!,
                              snapshot,
                              (physical + .5) *
                                  _width /
                                  widget.destinations.length,
                              _width / widget.destinations.length,
                              Curves.easeOutCubic.transform(_press.value),
                              (_position.velocity * .025).clamp(-1.0, 1.0),
                              theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                      NavigationBarTheme(
                        data: theme.navigationBarTheme.copyWith(
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          indicatorColor: Colors.transparent,
                          elevation: 0,
                          iconTheme: WidgetStateProperty.resolveWith(
                            (states) => IconThemeData(
                              size: 20,
                              color: states.contains(WidgetState.selected)
                                  ? tokens.primary
                                  : tokens.mutedForeground,
                            ),
                          ),
                          labelTextStyle: WidgetStateProperty.resolveWith(
                            (states) => theme.textTheme.labelMedium?.copyWith(
                              fontSize: 11.5,
                              fontWeight: states.contains(WidgetState.selected)
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: states.contains(WidgetState.selected)
                                  ? tokens.primary
                                  : tokens.mutedForeground,
                            ),
                          ),
                        ),
                        child: NavigationBar(
                          key: const ValueKey('modern-navigation'),
                          height: height,
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          indicatorColor: Colors.transparent,
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                          elevation: 0,
                          selectedIndex: widget.selectedIndex,
                          onDestinationSelected: (index) {
                            _settle(index);
                            widget.onDestinationSelected(index);
                          },
                          destinations: widget.destinations,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassPainter extends CustomPainter {
  const _GlassPainter(
    this.shader,
    this.snapshot,
    this.selection,
    this.slot,
    this.press,
    this.motion,
    this.accent,
  );
  final ui.FragmentShader shader;
  final _GlassSnapshot snapshot;
  final double selection, slot, press, motion;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      size.width,
      size.height,
      snapshot.size.width,
      snapshot.size.height,
      snapshot.offset.dx,
      snapshot.offset.dy,
      selection,
      slot,
      press,
      motion,
      .045,
      .055,
      .085,
      .72,
      accent.r,
      accent.g,
      accent.b,
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, snapshot.image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) => true;
}
