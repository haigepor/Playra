import 'package:dio/dio.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'rule_engine.dart';
import 'rule_engine_models.dart';

RuleRequestExecutor createRuleRequestExecutor() =>
    PlatformRuleRequestExecutor();
void logRuleWarning(String message, {Object? error, StackTrace? stackTrace}) =>
    KazumiLogger().w(message, error: error, stackTrace: stackTrace);
void logRuleInfo(String message) => KazumiLogger().i(message);

class PlatformRuleRequestExecutor implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async => throw const SearchErrorException('站点规则已移除，当前仅保留 Lumina');
}
