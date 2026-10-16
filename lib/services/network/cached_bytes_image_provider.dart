import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Web 按原地址复用压缩字节，再执行各尺寸的 decoder。
/// 不走第三方 HtmlImage（忽略尺寸）或 HttpGet（解码异常未收口）分支。
class CachedBytesImageProvider extends ImageProvider<CachedBytesImageProvider> {
  const CachedBytesImageProvider(this.url);
  final String url;

  @override
  Future<CachedBytesImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedBytesImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final cache = CachedNetworkImageProvider.defaultCacheManager;
    final file = await cache.getSingleFile(url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    // Future 的解码异常由 MultiFrameImageStreamCompleter 交给同一错误回退。
    try {
      return await decode(buffer);
    } catch (_) {
      // HTTP 200 的坏图也不能滞留字节缓存，重试需要重新取回资源。
      try {
        await cache.removeFile(url);
      } catch (_) {
        /* 保留原始解码错误。 */
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedBytesImageProvider && other.url == url;
  @override
  int get hashCode => Object.hash(CachedBytesImageProvider, url);
}
