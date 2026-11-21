import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

/// Large, edge-peeking promotional carousel for the discovery page.
///
/// This intentionally uses a [PageView] instead of a fixed strip: the target
/// layout keeps the previous/next poster visible on both sides so the page
/// reads as a browsable editorial shelf rather than a full-width banner.
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({
    super.key,
    required this.layout,
    required this.banners,
    required this.onTap,
  });

  final HomeLayoutMetrics layout;
  final List<MediaBanner> banners;
  final ValueChanged<MediaBanner> onTap;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  static const Duration _interval = Duration(seconds: 6);

  PageController? _controller;
  double _fraction = .78;
  Timer? _timer;
  int _index = 0;
  int? _autoTarget;

  int get _initialPage => widget.banners.length > 1 ? 1 : 0;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureController();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layoutChanged = oldWidget.layout.kind != widget.layout.kind;
    final bannersChanged =
        oldWidget.banners.length != widget.banners.length ||
        oldWidget.banners.map((banner) => banner.id).join('|') !=
            widget.banners.map((banner) => banner.id).join('|');
    if (layoutChanged) {
      _ensureController(force: true);
    }
    if (bannersChanged) {
      _index = _initialPage;
      _autoTarget = null;
      _restartTimer();
      if (_controller?.hasClients ?? false) {
        _controller!.jumpToPage(_initialPage);
      }
    }
  }

  void _ensureController({bool force = false}) {
    final nextFraction = widget.layout.isPhone
        ? 1.0
        : widget.layout.heroFraction;
    if (!force && _controller != null && nextFraction == _fraction) {
      return;
    }
    final old = _controller;
    _fraction = nextFraction;
    _index = _initialPage;
    _controller = PageController(
      viewportFraction: _fraction,
      initialPage: _initialPage,
    );
    old?.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _autoTarget = null;
    if (_reduceMotion || widget.banners.length < 2) return;
    _timer = Timer.periodic(_interval, (_) {
      final controller = _controller;
      if (!mounted ||
          controller == null ||
          !controller.hasClients ||
          _reduceMotion) {
        return;
      }
      final next = (_index + 1) % widget.banners.length;
      _autoTarget = next;
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: PlayraMotion.curve,
      );
    });
  }

  void _onPageChanged(int index) {
    final fromTimer = _autoTarget == index;
    _autoTarget = null;
    setState(() => _index = index);
    if (!fromTimer) _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final phone = widget.layout.isPhone;
        final cardHeight = (width * _fraction * (phone ? 0.60 : 9 / 16)).clamp(
          widget.layout.heroMinHeight,
          widget.layout.heroMaxHeight,
        );
        final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(480, 1920);
        return Padding(
          padding: EdgeInsets.only(
            top: phone ? 0 : widget.layout.heroTopPadding,
          ),
          child: Column(
            children: [
              SizedBox(
                height: cardHeight,
                child: PageView.builder(
                  controller: controller,
                  itemCount: widget.banners.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) => AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final page =
                          controller.hasClients &&
                              controller.position.haveDimensions
                          ? controller.page ?? _index.toDouble()
                          : _index.toDouble();
                      final delta = (index - page).abs().clamp(0.0, 1.0);
                      return Opacity(
                        opacity: 1 - delta * 0.28,
                        child: Transform.scale(
                          scale: 1 - delta * 0.075,
                          child: child,
                        ),
                      );
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: phone ? 0 : PlayraSpace.md,
                      ),
                      child: _BannerCard(
                        edgeToEdge: phone,
                        banner: widget.banners[index],
                        decodeWidth: decodeWidth,
                        onTap: () => widget.onTap(widget.banners[index]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.edgeToEdge,
    required this.banner,
    required this.decodeWidth,
    required this.onTap,
  });

  final bool edgeToEdge;
  final MediaBanner banner;
  final int decodeWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final radius = edgeToEdge
        ? BorderRadius.zero
        : BorderRadius.circular(PlayraRadius.control);
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label: banner.title.isEmpty ? '精选推荐' : banner.title,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: edgeToEdge
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: t.cardPlaceholder,
                child: MediaCoverImage(
                  url: banner.imageUrl,
                  cacheWidth: decodeWidth,
                  errorWidget: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: t.textSecondary,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      Color(0xC9000000),
                      Color(0x66000000),
                      Color(0x00000000),
                    ],
                    stops: <double>[0, 0.35, 0.72],
                  ),
                ),
              ),
              Positioned(
                left: PlayraSpace.lg,
                right: PlayraSpace.lg,
                bottom: 18,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        banner.title.isEmpty ? '精选推荐' : banner.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'serif',
                          fontSize: edgeToEdge ? 23 : 29,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                          height: 1.12,
                        ),
                      ),
                    ),
                    if (banner.target != null) ...[
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 15,
                            color: t.accentForeground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, borderRadius: radius),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
