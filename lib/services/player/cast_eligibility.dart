/// Explains why a renderer cannot safely fetch this playback source directly.
/// DLNA renderers receive only the URL, not the player's required HTTP headers.
String? castUnavailableReason({
  required bool isLocalPlayback,
  required String url,
  required String referer,
  required bool hasPlaybackHeaders,
}) {
  if (isLocalPlayback) return '暂不支持投屏本地视频';
  if (referer.trim().isNotEmpty || hasPlaybackHeaders) {
    return '该视频需要请求头，暂不支持直接投屏';
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '当前视频地址不支持投屏';
  }
  return null;
}
