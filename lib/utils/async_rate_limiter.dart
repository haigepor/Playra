import 'dart:async';
import 'async_serial_queue.dart';

/// Ensures asynchronous operations are spaced apart by at least a minimum interval.
class AsyncRateLimiter {
  AsyncRateLimiter(this.period);

  final Duration period;
  final Stopwatch _clock = Stopwatch()..start();
  final AsyncSerialQueue _queue = AsyncSerialQueue();
  int _nextAllowedMicroseconds = 0;

  /// Waits until the next allowed time slot and reserves the following slot.
  Future<void> acquire() => _queue.run(() async {
    // 按实际放行时刻排队，避免定时器延迟或系统时钟调整压缩后续请求间隔。
    while (_clock.elapsedMicroseconds < _nextAllowedMicroseconds) {
      final remaining = _nextAllowedMicroseconds - _clock.elapsedMicroseconds;
      await Future<void>.delayed(
        Duration(milliseconds: (remaining + 999) ~/ 1000),
      );
    }
    _nextAllowedMicroseconds =
        _clock.elapsedMicroseconds + period.inMicroseconds;
  });

  /// Runs [action] after acquiring a rate-limited time slot.
  Future<T> run<T>(Future<T> Function() action) async {
    await acquire();
    return await action();
  }
}
