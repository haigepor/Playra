import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';

/// Cover loader shared by poster cards, banners, detail backdrops and the
/// player gate.
///
/// Two reasons this is not a plain `Image.network`:
///
/// * The feed mixes CDNs. douban answers `418` without a browser UA and `403`
///   when the request carries Dart's default UA, and `Image.network` only
///   *appends* headers, so `user-agent` ends up duplicated and the request is
///   rejected. [CachedNetworkImage] goes through `package:http`, which replaces
///   the header, so one browser UA + referer works for douban, qpic and
///   360buyimg alike (verified on the emulator).
/// * Covers are scrolled past repeatedly; the disk cache and the app's
///   proxy-aware manager keep them off the network after the first load.
class MediaCoverImage extends StatelessWidget {
  const MediaCoverImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.errorWidget,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? errorWidget;

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const String referer = 'https://movie.douban.com/';

  static const Map<String, String> headers = <String, String>{
    'User-Agent': userAgent,
    'Referer': referer,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 22,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    if (url.isEmpty) return errorWidget ?? placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      placeholder: (_, _) => ColoredBox(color: colors.surfaceContainerHighest),
      fit: fit,
      // Headers are ignored by the web loader, so keep them native-only.
      httpHeaders: kIsWeb ? null : headers,
      memCacheWidth: cacheWidth,
      cacheManager: ProxyAwareImageCacheManager.instance,
      fadeInDuration: const Duration(milliseconds: 160),
      fadeOutDuration: const Duration(milliseconds: 80),
      errorWidget: (context, url, error) {
        // 只在 debug 输出，方便定位封面 CDN 的拒绝原因（正式包静默回退）。
        assert(() {
          debugPrint('MediaCoverImage failed: $url -> $error');
          return true;
        }());
        return errorWidget ?? placeholder;
      },
    );
  }
}
