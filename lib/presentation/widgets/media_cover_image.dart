import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/network/cover_url_policy.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';

/// Cover loader shared by poster cards, banners, detail backdrops and the
/// player gate.
///
/// Handles CDN-specific headers (for example Douban Referer vs. no Referer on
/// iQIYI), retired/anti-bot host rewrites (`qnmob3` / `img9` -> `img2`),
/// primary -> fallback URL recovery, and short-lived negative caching so dead
/// links are not repeatedly retried across list scrolls.
class MediaCoverImage extends StatefulWidget {
  const MediaCoverImage({
    super.key,
    required this.url,
    this.fallbackUrl = '',
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.errorWidget,
  });

  final String url;
  final String fallbackUrl;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? errorWidget;

  static const String userAgent = CoverUrlPolicy.userAgent;
  static const String referer = CoverUrlPolicy.doubanReferer;

  static Map<String, String> headersFor(String url) =>
      CoverUrlPolicy.headersFor(url);

  @override
  State<MediaCoverImage> createState() => _MediaCoverImageState();
}

class _MediaCoverImageState extends State<MediaCoverImage> {
  bool _useFallback = false;

  @override
  void didUpdateWidget(covariant MediaCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.fallbackUrl != widget.fallbackUrl) {
      _useFallback = false;
    }
  }

  String _pickActiveUrl(String primary, String fallback) {
    if (primary.isEmpty) return fallback;
    if (_useFallback && fallback.isNotEmpty && fallback != primary) {
      return fallback;
    }
    if (CoverUrlPolicy.isRecentlyFailed(primary) &&
        fallback.isNotEmpty &&
        fallback != primary &&
        !CoverUrlPolicy.isRecentlyFailed(fallback)) {
      return fallback;
    }
    return primary;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 22,
          color: colors.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
    final primary = CoverUrlPolicy.normalize(widget.url);
    final fallback = CoverUrlPolicy.normalize(widget.fallbackUrl);
    final activeUrl = _pickActiveUrl(primary, fallback);

    if (activeUrl.isEmpty || CoverUrlPolicy.isRecentlyFailed(activeUrl)) {
      return widget.errorWidget ?? placeholder;
    }

    return CachedNetworkImage(
      key: ValueKey<String>(activeUrl),
      imageUrl: activeUrl,
      placeholder: (_, _) => ColoredBox(color: colors.surfaceContainerHighest),
      fit: widget.fit,
      // Headers are ignored by the web loader, so keep them native-only.
      httpHeaders: kIsWeb ? null : CoverUrlPolicy.headersFor(activeUrl),
      memCacheWidth: widget.cacheWidth,
      cacheManager: ProxyAwareImageCacheManager.instance,
      fadeInDuration: const Duration(milliseconds: 160),
      fadeOutDuration: const Duration(milliseconds: 80),
      errorWidget: (context, failedUrl, error) {
        CoverUrlPolicy.markFailed(activeUrl);
        assert(() {
          if (CoverUrlPolicy.shouldLogFailure(activeUrl)) {
            debugPrint('MediaCoverImage failed: $activeUrl -> $error');
          }
          return true;
        }());
        if (!_useFallback &&
            fallback.isNotEmpty &&
            fallback != activeUrl &&
            !CoverUrlPolicy.isRecentlyFailed(fallback)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_useFallback) {
              setState(() => _useFallback = true);
            }
          });
          return ColoredBox(color: colors.surfaceContainerHighest);
        }
        return widget.errorWidget ?? placeholder;
      },
    );
  }
}
