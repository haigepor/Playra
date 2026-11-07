class PlayerErrorMapper {
  const PlayerErrorMapper._();

  /// 采集站直链 CDN 在打开阶段常见瞬时失败：对端重置/提前断流（EOF）/超时。
  /// 只应在「打开后的短窗口」内用于自动重试判断，避免误伤播放中的错误。
  static bool isTransientOpenFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed to open') ||
        message.contains('ffurl_read') ||
        message.contains('connection reset') ||
        message.contains('averror_eof') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  static String? toActionableMessage(
    Object error, {
    required bool isBuffering,
  }) {
    final message = error.toString();
    if (message.contains('Failed to recognize file format') ||
        (isBuffering && message.contains('Failed to open'))) {
      return '加载失败, 请尝试更换其他视频来源';
    }
    return null;
  }
}
