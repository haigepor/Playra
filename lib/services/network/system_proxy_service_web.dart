/// 浏览器网络代理由浏览器或 Web 服务配置，无法读取 WinINET 注册表。
class SystemProxyService {
  static void init() {}
  static bool refresh() => false;
  static bool get isActive => false;
  static (String, int)? proxyFor(String scheme) => null;
  static String findProxy(Uri url) => 'DIRECT';
}
