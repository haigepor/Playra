import 'package:dio/dio.dart' show CancelToken;
import 'package:kazumi/services/source/source_models.dart' show SourceException;

/// 仅保留旧调用者的拒绝边界，不再创建网络客户端。
class DanmakuClient {
  DanmakuClient._();
  static final DanmakuClient instance = DanmakuClient._();
  Never _removed() =>
      throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async => _removed();
}
