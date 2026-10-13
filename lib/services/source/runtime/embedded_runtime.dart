import 'dart:convert';
import 'package:flutter/services.dart';
import '../source_models.dart';

const _channel = MethodChannel('com.predidit.kazumi/source-runtime');
int _sequence = 0;

/// 仅固定业务 JSON，取消使用相同 requestId，不传入模块或私有存储路径。
Future<String?> invokeEmbeddedRuntime(
  Map<String, dynamic> request,
  int timeoutMs,
  Future<Object?> cancelled,
) async {
  final id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
  var finished = false;
  try {
    final response = _channel.invokeMethod<String>('request', {
      'requestId': id,
      'payloadJson': jsonEncode(request),
      'timeoutMs': timeoutMs,
    });
    final cancellation = cancelled.then<String?>((_) {
      if (!finished) {
        _channel
            .invokeMethod<void>('cancel', {'requestId': id})
            .catchError((Object _) {});
      }
      throw const SourceException('CANCELLED', '请求已取消');
    });
    return await Future.any([response, cancellation]);
  } on MissingPluginException {
    throw const SourceException('RUNTIME_UNAVAILABLE', '应用内 Python 运行入口未就绪');
  } on PlatformException {
    throw const SourceException('RUNTIME_ERROR', '应用内算法运行失败');
  } finally {
    finished = true;
  }
}
