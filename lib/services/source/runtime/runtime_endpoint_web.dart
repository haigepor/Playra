// Web 固定同源调用，不使用规则提供的运行服务地址。
String defaultRuntimeEndpoint() =>
    Uri.base.resolve('/api/runtime/v1/').toString();

Future<String?> invokeEmbeddedRequest(
  Map<String, dynamic> request,
  int timeoutMs,
  Future<Object?> cancelled,
) async => null;
