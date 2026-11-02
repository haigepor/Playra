import 'dart:async';
import 'package:dio/dio.dart';
import '../source_models.dart';

/// 网络可重叠，C 仍由单 worker 使用；取消只能阻止尚未进入 C 的后台计算。
class LuminaWorkScheduler {
  LuminaWorkScheduler({this.idleDelay = const Duration(seconds: 3)}) {
    _armIdle();
  }
  final Duration idleDelay;
  var _idle = Completer<void>();
  Timer? _timer;
  int _foreground = 0;
  CancelToken? _background;
  Completer<void>? _backgroundDone;

  void _armIdle() {
    _timer?.cancel();
    if (_foreground == 0) {
      if (_idle.isCompleted) _idle = Completer<void>();
      _timer = Timer(idleDelay, () {
        if (!_idle.isCompleted) _idle.complete();
      });
    }
  }

  void _check(CancelToken? token) {
    if (token?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
  }

  Future<void> _wait(Future<void> work, CancelToken? cancel) async {
    await Future.any([
      work,
      if (cancel != null) cancel.whenCancel.then((_) {}),
    ]);
    _check(cancel);
  }

  Future<T> run<T>(
    Future<T> Function(CancelToken) action, {
    required bool background,
    CancelToken? cancel,
  }) async {
    _check(cancel);
    final token = CancelToken();
    if (cancel != null) {
      unawaited(cancel.whenCancel.then((_) => token.cancel()));
    }
    if (!background) {
      _foreground++;
      _timer?.cancel();
      if (_idle.isCompleted) _idle = Completer<void>();
      _background?.cancel('foreground request');
      try {
        return await action(token);
      } finally {
        _foreground--;
        _armIdle();
      }
    }
    while (true) {
      await _wait(_idle.future, cancel);
      if (_foreground != 0 || !_idle.isCompleted) continue;
      final previous = _backgroundDone;
      if (previous != null) {
        await _wait(previous.future, cancel);
        continue;
      }
      _check(cancel);
      _background = token;
      final done = _backgroundDone = Completer<void>();
      try {
        return await action(token);
      } finally {
        _background = null;
        _backgroundDone = null;
        done.complete();
        _armIdle();
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _background?.cancel();
  }
}
