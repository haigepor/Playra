/// 仅恢复同一集且时长相容的进度；不把旧版本的偏移写进另一版视频。
Duration? sdkResumePosition({
  required Duration position,
  required Duration previousDuration,
  required Duration targetDuration,
}) {
  if (position.isNegative ||
      previousDuration <= Duration.zero ||
      targetDuration <= Duration.zero ||
      position >= targetDuration) {
    return null;
  }
  final difference = (targetDuration - previousDuration).inMilliseconds.abs();
  final tolerance = previousDuration.inMilliseconds * .02 + 2000;
  return difference <= tolerance ? position : null;
}

/// seek完成Future早于位置流回报时，禁止用瞬时0覆盖已保存的续播进度。
class SdkResumeProgressGuard {
  Duration? _pending;
  void waitFor(Duration target) {
    _pending = target > Duration.zero ? target : null;
  }

  bool accepts(Duration position) {
    final target = _pending;
    if (target != null && position < target - const Duration(seconds: 1)) {
      return false;
    }
    _pending = null;
    return true;
  }
}
