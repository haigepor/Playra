import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'source_models.dart';
import 'source_service.dart';

/// 保留现有平台 WebView，只在来源服务边界统一超时、取消与健康记录。
class SourcePlaybackService extends WebViewVideoSourceService {
  SourcePlaybackService({this.providerId = 'unknown'});
  final String providerId;
  SourceContext? _context;
  @override
  Future<VideoSource> resolve(
    String episodeUrl, {
    required bool useLegacyParser,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
    SourceContext? context,
  }) async {
    _context?.cancelToken.cancel('replaced');
    final effective = kIsWeb && timeout < const Duration(seconds: 45)
        ? const Duration(seconds: 45)
        : timeout;
    final ctx =
        context ??
        SourceContext(
          providerId: providerId,
          timeout: effective + const Duration(seconds: 10),
        );
    _context = ctx;
    // 外部会话取消必须关闭底层 WebView，旧请求不能取消后来创建的解析。
    unawaited(
      ctx.cancelToken.whenCancel.then((_) {
        if (identical(_context, ctx)) super.cancel();
      }),
    );
    try {
      return await SourceService.shared.observe(
        ctx.providerId ?? providerId,
        'resolve',
        ctx,
        () async {
          try {
            return await super.resolve(
              episodeUrl,
              useLegacyParser: useLegacyParser,
              offset: offset,
              timeout: effective,
            );
          } on VideoSourceTimeoutException {
            throw const SourceException('TIMEOUT', '视频解析超时');
          } on VideoSourceCancelledException {
            throw const SourceException('CANCELLED', '视频解析已取消');
          }
        },
      );
    } on SourceException catch (error) {
      if (error.code == 'CANCELLED') {
        throw const VideoSourceCancelledException();
      }
      if (error.code == 'TIMEOUT') throw VideoSourceTimeoutException(effective);
      throw VideoSourceNotFoundException(error.message);
    } finally {
      if (identical(_context, ctx)) _context = null;
    }
  }

  @override
  void cancel() {
    _context?.cancelToken.cancel();
    super.cancel();
  }

  @override
  Future<void> dispose() {
    cancel();
    return super.dispose();
  }
}
