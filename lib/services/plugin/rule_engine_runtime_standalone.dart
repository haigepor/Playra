import 'rule_engine.dart';
import 'rule_engine_models.dart';

// 独立服务必须显式注入请求器，防止绕过 HTTP 网关的公网地址校验。
RuleRequestExecutor createRuleRequestExecutor() => _MissingExecutor();
void logRuleWarning(String message, {Object? error, StackTrace? stackTrace}) {}
void logRuleInfo(String message) {}

class _MissingExecutor implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    RuleCancelToken? cancelToken,
  }) async {
    throw UnsupportedError('Standalone RuleEngine requires a request executor');
  }
}
