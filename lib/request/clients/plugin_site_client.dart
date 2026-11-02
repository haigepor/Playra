import 'package:dio/dio.dart' show CancelToken;
import 'package:kazumi/services/source/source_models.dart' show SourceException;

/// 仅保留旧调用者的拒绝边界，不再创建网络客户端。
class PluginSiteClient {
  PluginSiteClient._();
  static final PluginSiteClient instance = PluginSiteClient._();
  Never _removed() =>
      throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  Future<String> requestText(
    String url, {
    required String method,
    Map<String, dynamic> headers = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? data,
    CancelToken? cancelToken,
  }) async => _removed();
}
