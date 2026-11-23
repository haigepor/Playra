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

  static String? openFailureMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('failed to recognize file format')) return '无法识别视频格式';
    if (message.contains('failed to open')) return '视频未能打开，请重试';
    return null;
  }
}
