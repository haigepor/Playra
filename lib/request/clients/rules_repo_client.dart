import 'package:dio/dio.dart' show CancelToken;
import 'package:kazumi/services/source/source_models.dart' show SourceException;

/// 仅保留旧调用者的拒绝边界，不再创建网络客户端。
class RulesRepoClient {
  RulesRepoClient._();
  static final RulesRepoClient instance = RulesRepoClient._();
  Never _removed() =>
      throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  Future<String> getText(String url, {CancelToken? cancelToken}) async =>
      _removed();
}
