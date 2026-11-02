/// 官方 C 后端会校验播放请求上下文；必须保留原查询串及其编码。
String luminaResponsePath(Uri uri) =>
    uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
