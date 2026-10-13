import 'dart:io';
import 'embedded_runtime.dart';

String defaultRuntimeEndpoint() =>
    const String.fromEnvironment('PLAYRA_SOURCE_RUNTIME_URL');

Future<String?> invokeEmbeddedRequest(
  Map<String, dynamic> request,
  int timeoutMs,
  Future<Object?> cancelled,
) async => Platform.isAndroid
    ? invokeEmbeddedRuntime(request, timeoutMs, cancelled)
    : null;
