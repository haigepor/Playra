import 'package:kazumi/request/config/api_endpoints.dart';

/// 请求级别覆盖加速方式，不修改用户的全局网络设置。
const bangumiAccelerationOverride = 'bangumiAccelerationOverride';

bool isProtectedBangumiMirrorRequest(String url, String method) {
  final uri = Uri.parse(url);
  if (!ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) return false;
  if (method == 'POST' && uri.path == '/v0/search/subjects') return true;
  return method == 'GET' &&
      uri.path.endsWith('/comments') &&
      const [
        '/p1/subjects/',
        '/p1/episodes/',
        '/p1/characters/',
      ].any(uri.path.startsWith);
}
