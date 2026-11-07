import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:octo_image/octo_image.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/image_extension.dart';
import 'package:kazumi/services/platform/resource_url.dart';
import 'package:kazumi/services/network/cached_bytes_image_provider.dart';

class NetworkImgLayer extends StatefulWidget {
  const NetworkImgLayer({
    super.key,
    this.src,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.type,
    this.fadeOutDuration,
    this.fadeInDuration,
    this.origAspectRatio,
    this.filterQuality = FilterQuality.high,
    this.color,
    this.colorBlendMode,
    this.borderRadius,
    this.fallbackTitle,
  });

  final String? src;
  final double width;
  final double height;
  final BoxFit fit;
  final String? type;
  final Duration? fadeOutDuration;
  final Duration? fadeInDuration;
  final double? origAspectRatio;
  final FilterQuality filterQuality;
  final Color? color;
  final BlendMode? colorBlendMode;
  final BorderRadius? borderRadius;
  final String? fallbackTitle;

  static Widget heroFlightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final heroContext = flightDirection == HeroFlightDirection.push
        ? fromHeroContext
        : toHeroContext;
    final hero = flightDirection == HeroFlightDirection.push
        ? fromHero
        : toHero;

    return InheritedTheme.captureAll(
      heroContext,
      Material(type: MaterialType.transparency, child: hero.child),
    );
  }

  @override
  State<NetworkImgLayer> createState() => _NetworkImgLayerState();
}

class _NetworkImgLayerState extends State<NetworkImgLayer> {
  String? _resolvedFallbackUrl;
  bool _resolvingFallback = false;
  bool _primaryFailed = false;

  @override
  void initState() {
    super.initState();
    _syncFallbackState();
  }

  @override
  void didUpdateWidget(covariant NetworkImgLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.fallbackTitle != widget.fallbackTitle) {
      _primaryFailed = false;
      _resolvingFallback = false;
      _syncFallbackState();
    }
  }

  void _syncFallbackState() {
    final normalized = normalizeImageUrl(widget.src ?? '');
    final cached = cachedFallbackCoverForTitle(widget.fallbackTitle);
    _resolvedFallbackUrl = cached;
    if ((normalized.isEmpty || isDeadImageHost(normalized)) &&
        (widget.fallbackTitle?.trim().isNotEmpty ?? false) &&
        !hasTriedFallbackCoverForTitle(widget.fallbackTitle)) {
      _requestFallbackCover();
    }
  }

  void _requestFallbackCover() {
    final title = widget.fallbackTitle?.trim() ?? '';
    if (title.isEmpty || _resolvingFallback || isFlutterTestBinding) return;
    if (hasTriedFallbackCoverForTitle(title)) {
      _resolvedFallbackUrl = cachedFallbackCoverForTitle(title);
      return;
    }
    _resolvingFallback = true;
    resolveFallbackCoverByTitle(title).then((url) {
      if (!mounted) return;
      setState(() {
        _resolvingFallback = false;
        _resolvedFallbackUrl = url;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryUrl = normalizeImageUrl(widget.src ?? '');
    final useFallback =
        _primaryFailed || primaryUrl.isEmpty || isDeadImageHost(primaryUrl);
    final effectiveUrl = useFallback
        ? (_resolvedFallbackUrl ?? '')
        : primaryUrl;

    if (effectiveUrl.isEmpty) {
      if (_resolvingFallback) {
        return ClipRRect(
          clipBehavior: Clip.antiAlias,
          borderRadius: _borderRadius,
          child: _skeletonPlaceholder(),
        );
      }
      return _placeholder(context);
    }

    final (memCacheWidth, memCacheHeight) = _cacheSize(context);
    final url = platformResourceUrl(effectiveUrl);
    final headers = httpHeadersForImageUrl(url);
    return ClipRRect(
      clipBehavior: Clip.antiAlias,
      borderRadius: _borderRadius,
      // 复用 CachedNetworkImage 内部的同一淡入组件与原生缓存 provider。
      // Web 用框架的字节解码分支，确保缩略尺寸生效，坏图片也能结束等待。
      child: OctoImage(
        key: ValueKey(url),
        image: kIsWeb
            ? CachedBytesImageProvider(url, headers: headers)
            : CachedNetworkImageProvider(url, headers: headers),
        width: widget.width,
        height: widget.height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fit: widget.fit,
        fadeOutDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : widget.fadeOutDuration ?? const Duration(milliseconds: 140),
        fadeInDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : widget.fadeInDuration ?? const Duration(milliseconds: 240),
        fadeInCurve: Curves.easeOutCubic,
        filterQuality: widget.filterQuality,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        errorBuilder: (context, error, stackTrace) {
          _logFailure(url, error);
          if (!useFallback &&
              (widget.fallbackTitle?.trim().isNotEmpty ?? false) &&
              !hasTriedFallbackCoverForTitle(widget.fallbackTitle) &&
              !isFlutterTestBinding) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _primaryFailed = true);
              _requestFallbackCover();
            });
            return _skeletonPlaceholder();
          }
          if (!useFallback && (_resolvedFallbackUrl?.isNotEmpty ?? false)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_primaryFailed) {
                setState(() => _primaryFailed = true);
              }
            });
            return _skeletonPlaceholder();
          }
          return _placeholder(context);
        },
        placeholderBuilder: (context) => _skeletonPlaceholder(),
      ),
    );
  }

  Widget _skeletonPlaceholder() => ContentSkeleton(
    key: const ValueKey('content-skeleton-image'),
    animate: !isFlutterTestBinding,
    child: Bone(
      width: widget.width.isFinite ? widget.width : null,
      height: widget.height.isFinite ? widget.height : null,
      borderRadius: _borderRadius,
    ),
  );

  (int?, int?) _cacheSize(BuildContext context) {
    if (!widget.width.isFinite || !widget.height.isFinite || widget.height <= 0) {
      return (null, null);
    }
    final cacheWidth = widget.width.cacheSize(context);
    final cacheHeight = widget.height.cacheSize(context);
    final aspectRatio = widget.width / widget.height;
    final sourceAspectRatio = widget.origAspectRatio;

    switch (widget.fit) {
      case BoxFit.none:
      case BoxFit.scaleDown:
        // These modes depend on the original image dimensions.
        return (null, null);
      case BoxFit.fill:
        return (cacheWidth, cacheHeight);
      case BoxFit.fitWidth:
        return (cacheWidth, null);
      case BoxFit.fitHeight:
        return (null, cacheHeight);
      case BoxFit.contain:
        // A single decode axis preserves unknown source proportions.
        return sourceAspectRatio != null && sourceAspectRatio > aspectRatio
            ? (cacheWidth, null)
            : (null, cacheHeight);
      case BoxFit.cover:
        // Decode enough pixels along the axis that fills the box.
        if (sourceAspectRatio != null) {
          if (sourceAspectRatio < aspectRatio) return (cacheWidth, null);
          if (sourceAspectRatio > aspectRatio) return (null, cacheHeight);
        } else {
          if (aspectRatio > 1) return (null, cacheHeight);
          if (aspectRatio < 1) return (cacheWidth, null);
        }
        return (cacheWidth, cacheHeight);
    }
  }

  BorderRadius get _borderRadius =>
      widget.borderRadius ??
      BorderRadius.circular(switch (widget.type) {
        'avatar' => 50,
        'emote' => 0,
        _ => StyleString.imgRadius.x,
      });

  // 同一 URL 的失败只记录一次，避免滚动或重建时重复刷日志。
  static final _loggedFailures = <String>{};

  static void _logFailure(String url, Object error) {
    if (_loggedFailures.length >= 200) _loggedFailures.clear();
    if (!_loggedFailures.add(url)) return;
    KazumiLogger().w(
      'NetworkImage: network image load error',
      error: '$error | url=$url',
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onInverseSurface.withValues(alpha: 0.4),
        borderRadius: _borderRadius,
      ),
      child: widget.type == 'bg'
          ? Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 22,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Center(
              child: Image.asset(
                widget.type == 'avatar'
                    ? 'assets/images/noface.jpeg'
                    : 'assets/images/loading.png',
                width: widget.width.isFinite ? widget.width : null,
                height: widget.height.isFinite ? widget.height : null,
                cacheWidth: widget.width.isFinite ? widget.width.cacheSize(context) : null,
                cacheHeight: widget.height.isFinite ? widget.height.cacheSize(context) : null,
              ),
            ),
    );
  }
}
