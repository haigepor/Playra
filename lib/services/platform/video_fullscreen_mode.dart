/// 播放器全屏方向。
///
/// `landscape` 是原来的默认全屏；`portrait` 由顶部按钮手动切换，
/// 不改变普通全屏按钮的行为。
enum VideoFullscreenMode {
  none,
  landscape,
  portrait;

  bool get isFullscreen => this != VideoFullscreenMode.none;
}
