import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kazumi/services/platform/video_fullscreen_mode.dart';
import 'package:mobx/mobx.dart';

/// Explicit fullscreen owns a local history entry; rotation does not.
///
/// `landscape` preserves the previous behaviour. `portrait` is a manual
/// alternative entered from the player's top bar; it uses the same history
/// entry so back always exits fullscreen before leaving the page.
class VideoFullscreenController {
  VideoFullscreenController({
    required Future<void> Function(VideoFullscreenMode mode) applyFullscreen,
  }) : _applyFullscreen = applyFullscreen;

  final Future<void> Function(VideoFullscreenMode mode) _applyFullscreen;
  final Observable<VideoFullscreenMode> _mode = Observable(
    VideoFullscreenMode.none,
  );
  final Observable<LocalHistoryEntry?> _entry = Observable(null);
  ModalRoute<dynamic>? _route;
  int _revision = 0;
  int _pendingRequests = 0;
  Future<void> _lastRequest = Future.value();
  Future<void>? _closeFuture;

  VideoFullscreenMode get mode => _mode.value;
  bool get isFullscreen => mode.isFullscreen;

  void attach(ModalRoute<dynamic> route) {
    assert(_route == null || identical(_route, route));
    _route = route;
  }

  /// Default fullscreen button: normal page <-> landscape fullscreen.
  Future<void> toggle() =>
      setMode(isFullscreen ? VideoFullscreenMode.none : VideoFullscreenMode.landscape);

  /// Top-bar button: normal/landscape -> portrait; portrait -> exit.
  Future<void> togglePortrait() => setMode(
    mode == VideoFullscreenMode.portrait
        ? VideoFullscreenMode.none
        : VideoFullscreenMode.portrait,
  );

  Future<void> setFullscreen(bool fullscreen) => setMode(
    fullscreen ? VideoFullscreenMode.landscape : VideoFullscreenMode.none,
  );

  Future<void> setMode(VideoFullscreenMode next) =>
      _setMode(next, updatePlatform: true);

  Future<void> _setMode(
    VideoFullscreenMode next, {
    required bool updatePlatform,
  }) {
    if (_closeFuture != null || next == mode) return _lastRequest;
    final route = _route;
    if (route == null) {
      throw StateError('Attach the video route before entering fullscreen.');
    }
    _revision++;
    final wasFullscreen = isFullscreen;
    final willFullscreen = next.isFullscreen;
    if (!wasFullscreen && willFullscreen) {
      late final LocalHistoryEntry entry;
      entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (!identical(_entry.value, entry)) return;
          _revision++;
          _setEntry(null);
          _setModeValue(VideoFullscreenMode.none);
          unawaited(_requestFullscreen(VideoFullscreenMode.none));
        },
      );
      route.addLocalHistoryEntry(entry);
      _setEntry(entry);
    } else if (wasFullscreen && !willFullscreen) {
      _removeEntry();
    } else if (!wasFullscreen) {
      _setEntry(null);
    }
    _setModeValue(next);
    return updatePlatform ? _requestFullscreen(next) : Future.value();
  }

  void _setModeValue(VideoFullscreenMode value) {
    runInAction(() => _mode.value = value);
  }

  void _setEntry(LocalHistoryEntry? entry) {
    runInAction(() => _entry.value = entry);
  }

  void _removeEntry() {
    final entry = _entry.value;
    _setEntry(null);
    entry?.remove();
  }

  void onDesktopFullscreenChanged(bool fullscreen) {
    // Ignore acknowledgements of commands still in flight.
    if (_pendingRequests != 0) return;
    if (!fullscreen) {
      unawaited(_setMode(VideoFullscreenMode.none, updatePlatform: false));
    } else if (!isFullscreen) {
      unawaited(
        _setMode(VideoFullscreenMode.landscape, updatePlatform: false),
      );
    }
  }

  Future<void> initializeDesktop(Future<bool> Function() readFullscreen) async {
    final revision = _revision;
    final fullscreen = await readFullscreen();
    if (revision == _revision) onDesktopFullscreenChanged(fullscreen);
  }

  Future<void> _requestFullscreen(VideoFullscreenMode mode) {
    _pendingRequests++;
    return _lastRequest = _applyFullscreen(mode).whenComplete(() {
      _pendingRequests--;
    });
  }

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    return _closeFuture = detach();
  }

  /// 切换新旧界面只卸载视图，路由控制器仍需支持重新挂载。
  Future<void> detach() {
    _revision++;
    _removeEntry();
    _setModeValue(VideoFullscreenMode.none);
    _route = null;
    return _requestFullscreen(VideoFullscreenMode.none);
  }
}
