import 'dart:async';
import 'package:dio/dio.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

/// 同源服务使用受限制的 Chromium 上下文执行原有视频页解析。
class VideoWebviewBrowserImpl extends VideoWebviewController {
  final _client = Dio();
  CancelToken? _request;
  bool _disposed = false;
  @override
  Future<void> init() async {
    initEventController.add(true);
  }

  @override
  Future<void> loadUrl(
    String url,
    bool useLegacyParser, {
    int offset = 0,
  }) async {
    await unloadPage();
    this.offset = offset;
    final request = CancelToken();
    _request = request;
    videoLoadingEventController.add(true);
    // 先返回以便调用方安装事件订阅，防止立即解析完成时丢失广播事件。
    unawaited(_resolve(url, request));
  }

  Future<void> _resolve(String url, CancelToken request) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        Uri.base.resolve('/api/parse').toString(),
        data: {'url': url},
        options: Options(
          headers: {'X-Kazumi-Request': '1'},
          receiveTimeout: const Duration(seconds: 45),
        ),
        cancelToken: request,
      );
      if (_disposed || request.isCancelled || !identical(_request, request)) {
        return;
      }
      final source = response.data?['url'] as String?;
      if (source == null || source.isEmpty) throw StateError('未找到视频地址');
      isVideoSourceLoaded = true;
      videoLoadingEventController.add(false);
      notifyVideoSourceResolved(
        source,
        format: Uri.parse(source).path.toLowerCase().endsWith('.m3u8')
            ? VideoSourceFormat.hls
            : VideoSourceFormat.auto,
      );
    } catch (error) {
      if (!_disposed && !request.isCancelled) {
        logEventController.add('浏览器解析失败：$error');
        videoLoadingEventController.add(false);
      }
    }
  }

  @override
  Future<void> unloadPage() async {
    _request?.cancel();
    _request = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await unloadPage();
    _client.close(force: true);
    disposeEventControllers();
  }
}
