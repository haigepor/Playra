import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:web/web.dart' as web;

@JS('PlayraArtPlayer.mountHandle')
external JSObject _mount(
  web.HTMLElement container,
  int handle,
  JSObject options,
);

/// 复用 media_kit 的 video，保留选集状态与同源媒体代理，只替换 Web 控件。
class WebPlayerSurface extends StatefulWidget {
  const WebPlayerSurface({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.onNext,
    this.onDanmaku,
  });
  final VideoController controller;
  final BoxFit fit;
  final VoidCallback? onNext, onDanmaku;
  @override
  State<WebPlayerSurface> createState() => _WebPlayerSurfaceState();
}

class _WebPlayerSurfaceState extends State<WebPlayerSurface> {
  web.HTMLElement? _container;
  JSObject? _controls;
  int _generation = 0;
  String _theme = '#a7b7ff';

  Future<void> _attach(web.HTMLElement container) async {
    final generation = ++_generation;
    final controller = widget.controller;
    final handle = await controller.player.handle;
    if (!mounted || generation != _generation) return;
    final options =
        <String, Object>{
              'theme': _theme,
              'fit': widget.fit == BoxFit.cover ? 'cover' : 'contain',
            }.jsify()!
            as JSObject;
    if (widget.onNext != null) {
      options.setProperty('onNext'.toJS, (() => widget.onNext?.call()).toJS);
    }
    if (widget.onDanmaku != null) {
      options.setProperty(
        'onDanmaku'.toJS,
        (() => widget.onDanmaku?.call()).toJS,
      );
    }
    _controls = _mount(container, handle, options);
  }

  void _detach() {
    _generation++;
    _controls?.callMethod<JSAny?>('destroy'.toJS);
    _controls = null;
  }

  @override
  void didUpdateWidget(WebPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller && _container != null) {
      _detach();
      unawaited(_attach(_container!));
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.toARGB32() & 0xffffff;
    _theme = '#${color.toRadixString(16).padLeft(6, '0')}';
    // Flutter 官方 HtmlElementView 生命周期；DOM 与 Widget 一起创建和释放。
    // https://api.flutter.dev/flutter/widgets/HtmlElementView-class.html
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        final container = _container = element as web.HTMLElement;
        container.style
          ..width = '100%'
          ..height = '100%'
          ..backgroundColor = '#000';
        container.setAttribute('aria-label', 'Playra Web 播放器');
        unawaited(_attach(container));
      },
    );
  }
}
