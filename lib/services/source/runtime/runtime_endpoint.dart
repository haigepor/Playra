import 'dart:io';
// 独立 Dart HTTP 服务没有 Flutter engine；仅 Android Flutter 绑定原生桥。
import 'embedded_runtime_stub.dart'
    if (dart.library.ui) 'embedded_runtime.dart';

String defaultRuntimeEndpoint() =>
    const String.fromEnvironment('PLAYRA_SOURCE_RUNTIME_URL');

Future<String?> invokeEmbeddedRequest(
  Map<String, dynamic> request,
  int timeoutMs,
  Future<Object?> cancelled,
) async => Platform.isAndroid
    ? invokeEmbeddedRuntime(request, timeoutMs, cancelled)
    : null;
