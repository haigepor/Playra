/// 只接受实际解码尺寸；来源名、码率和“高清”文案不能证明达到 1080p。
String? automaticAnimeQualityError({
  int? width,
  int? height,
  Duration? duration,
}) {
  // 实测站点会返回 3 秒 1080p 占位片；不能把它确认成番剧正片。手动播放不受限。
  if (duration != null &&
      duration > Duration.zero &&
      duration < const Duration(seconds: 10)) {
    return 'MEDIA_TOO_SHORT';
  }
  if (width == null || width <= 0 || height == null || height <= 0) {
    return 'QUALITY_UNCONFIRMED';
  }
  return height >= 1080 ? null : 'QUALITY_BELOW_MINIMUM';
}
