/// 空壳阶段 Web 直接使用原始媒体地址，不依赖同源代理。
///
/// 需要 `Referer`/`Cookie` 等浏览器无法设置的请求头时，再在 `tool/` 下提供
/// 最小媒体代理，并只在此函数内接入；不要把代理地址写进播放器或来源页面。
String platformResourceUrl(
  String url, {
  Map<String, dynamic> headers = const {},
}) => url;
