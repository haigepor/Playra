import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

/// Flagship centered symmetric depth-stack carousel with zero-overlay artwork,
/// full-bleed blurred ambient backdrop, and an external caption + liquid
/// indicator row. Displays at most [maxItems] banners (defaults to 5).
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({
    super.key,
    required this.layout,
    required this.banners,
    required this.onTap,
    this.canOpen,
    this.maxItems = 5,
  });

  final HomeLayoutMetrics layout;
  final List<MediaBanner> banners;
  final ValueChanged<MediaBanner> onTap;
  final bool Function(MediaBanner)? canOpen;
  final int maxItems;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  static const Duration _interval = Duration(seconds: 6);

  PageController? _controller;
  double _fraction = .84;
  Timer? _timer;
  int _pageIndex = 0;
  bool _correcting = false;

  List<MediaBanner> get _visibleBanners => widget.banners.length > widget.maxItems
      ? widget.banners.sublist(0, widget.maxItems)
      : widget.banners;

  bool get _loops => _visibleBanners.length > 1;
  int get _initialPage => _loops ? 1 : 0;
  int get _pageCount =>
      _loops ? _visibleBanners.length + 2 : _visibleBanners.length;

  int _bannerIndex(int page) => _loops
      ? (page - 1 + _visibleBanners.length) % _visibleBanners.length
      : page.clamp(0, _visibleBanners.length - 1);

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = PlayraMotion.reduceOf(context);
    _ensureController();
    _restartTimer();
  }

  @override
  void reassemble() {
    super.reassemble();
    _ensureController(force: true);
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldVisible = oldWidget.banners.length > oldWidget.maxItems
        ? oldWidget.banners.sublist(0, oldWidget.maxItems)
        : oldWidget.banners;
    final nextVisible = _visibleBanners;
    final layoutChanged = oldWidget.layout.kind != widget.layout.kind;
    final bannersChanged =
        oldVisible.length != nextVisible.length ||
        oldVisible.map((banner) => banner.id).join('|') !=
            nextVisible.map((banner) => banner.id).join('|');
    if (layoutChanged || bannersChanged) {
      _ensureController(force: true);
      _restartTimer();
    }
  }

  void _ensureController({bool force = false}) {
    final nextFraction = widget.layout.isPhone
        ? (_visibleBanners.length > 1 ? .84 : 1.0)
        : widget.layout.heroFraction;
    if (!force && _controller != null && nextFraction == _fraction) {
      return;
    }
    final old = _controller;
    _fraction = nextFraction;
    _pageIndex = _initialPage;
    _correcting = false;
    _controller = PageController(
      viewportFraction: _fraction,
      initialPage: _initialPage,
      keepPage: false,
    );
    old?.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_reduceMotion || !_loops) return;
    _timer = Timer(_interval, () {
      final controller = _controller;
      if (!mounted ||
          controller == null ||
          !controller.hasClients ||
          _reduceMotion) {
        return;
      }
      controller.animateToPage(
        _pageIndex + 1,
        duration: const Duration(milliseconds: 480),
        curve: PlayraMotion.curve,
      );
    });
  }

  void _onPageChanged(int page) {
    if (_pageIndex != page) setState(() => _pageIndex = page);
  }

  void _jumpToBannerIndex(int bannerIdx) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final targetPage = _loops ? bannerIdx + 1 : bannerIdx;
    if (targetPage == _pageIndex) return;
    _timer?.cancel();
    controller.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 440),
      curve: PlayraMotion.curve,
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_loops) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _timer?.cancel();
    } else if (notification is ScrollEndNotification && !_correcting) {
      final controller = _controller;
      if (controller == null || controller.positions.length != 1) return false;
      final page = controller.page?.round() ?? _pageIndex;
      final destination = page == 0
          ? _visibleBanners.length
          : page == _visibleBanners.length + 1
          ? 1
          : page;
      if (destination != page) {
        _correcting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !identical(controller, _controller) ||
              !controller.hasClients) {
            return;
          }
          controller.jumpToPage(destination);
          _pageIndex = destination;
          _correcting = false;
          _restartTimer();
        });
      } else {
        _restartTimer();
      }
    }
    return false;
  }

  bool _isBannerActionable(MediaBanner banner) =>
      widget.canOpen?.call(banner) ?? true;

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = _visibleBanners;
    if (banners.isEmpty) return const SizedBox.shrink();
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final phone = widget.layout.isPhone;
        final activeIdx = _bannerIndex(_pageIndex);
        final activeBanner = banners[activeIdx];
        final activeActionable = _isBannerActionable(activeBanner);

        final cardWidth = _loops
            ? width * _fraction
            : (width - widget.layout.gutter * 2).clamp(0.0, width);
        final cardHeight = (cardWidth * 9 / 16).clamp(
          120.0,
          phone ? 232.0 : widget.layout.heroMaxHeight,
        );
        final decodeWidth = (cardWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(480, 1920);
        final topGap = phone ? 12.0 : widget.layout.heroTopPadding;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Full-bleed blurred ambient backdrop melting into the dark canvas.
            Positioned.fill(
              child: IgnorePointer(
                child: _AmbientBackdrop(
                  banner: activeBanner,
                  pageBackground: t.pageBackground,
                  accent: t.accent,
                  isDark: isDark,
                  reduceMotion: _reduceMotion,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: topGap, bottom: phone ? 6 : 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Visual z-sorted centered symmetric depth stack.
                        IgnorePointer(
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              final page =
                                  controller.positions.length == 1 &&
                                      controller.position.haveDimensions
                                  ? controller.page ?? _pageIndex.toDouble()
                                  : _pageIndex.toDouble();
                              return _buildDepthStack(
                                banners: banners,
                                width: width,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                page: page,
                                decodeWidth: decodeWidth,
                                phone: phone,
                              );
                            },
                          ),
                        ),
                        // Transparent native PageView driving swipe physics & hit-testing.
                        NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: PageView.builder(
                            key: ObjectKey(controller),
                            controller: controller,
                            itemCount: _pageCount,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, index) {
                              final banner = banners[_bannerIndex(index)];
                              final actionable = _isBannerActionable(banner);
                              final isCurrent = index == _pageIndex;
                              final label = banner.title.isEmpty
                                  ? '精选推荐'
                                  : banner.title;
                              return Semantics(
                                button: isCurrent && actionable,
                                excludeSemantics: true,
                                label: isCurrent ? label : null,
                                onTap: isCurrent && actionable
                                    ? () => widget.onTap(banner)
                                    : null,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (!isCurrent) {
                                      controller.animateToPage(
                                        index,
                                        duration: const Duration(
                                          milliseconds: 420,
                                        ),
                                        curve: PlayraMotion.curve,
                                      );
                                      return;
                                    }
                                    if (actionable) {
                                      widget.onTap(banner);
                                    }
                                  },
                                  child: const SizedBox.expand(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  _ExternalCaptionRow(
                    gutter: widget.layout.gutter,
                    controller: controller,
                    loops: _loops,
                    fallbackPage: _pageIndex.toDouble(),
                    bannerIndex: activeIdx,
                    bannerCount: banners.length,
                    title: activeBanner.title.isEmpty
                        ? '精选推荐'
                        : activeBanner.title,
                    onTapTitle: activeActionable
                        ? () => widget.onTap(activeBanner)
                        : null,
                    onSelectDot: _jumpToBannerIndex,
                    reduceMotion: _reduceMotion,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDepthStack({
    required List<MediaBanner> banners,
    required double width,
    required double cardWidth,
    required double cardHeight,
    required double page,
    required int decodeWidth,
    required bool phone,
  }) {
    if (!_loops) {
      return Center(
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: _PureArtCard(
            key: const ValueKey('banner-depth-card-0'),
            banner: banners.first,
            decodeWidth: decodeWidth,
            isFocused: true,
            dimAlpha: 0,
            phone: phone,
          ),
        ),
      );
    }

    final base = page.floor();
    final visible = <int>[
      for (var i = base - 1; i <= base + 2; i++)
        if (i >= 0 && i < _pageCount) i,
    ];

    visible.sort(
      (a, b) => (b - page).abs().compareTo((a - page).abs()),
    );

    final shiftUnit = phone ? cardWidth * 0.155 : cardWidth * 0.22;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        for (final index in visible)
          Builder(
            builder: (context) {
              final offset = (index - page).clamp(-1.6, 1.6);
              final depth = offset.abs().clamp(0.0, 1.5);
              final scale = _reduceMotion
                  ? (depth < 0.5 ? 1.0 : 0.88)
                  : (1.0 - depth * 0.12).clamp(0.76, 1.0);
              final opacity = (1.0 - depth * 0.34).clamp(0.0, 1.0);
              final dimAlpha = (depth * 0.36).clamp(0.0, 0.45);
              final translateX = offset * shiftUnit;
              final bIdx = _bannerIndex(index);

              return Transform.translate(
                offset: Offset(translateX, 0),
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: _PureArtCard(
                        key: ValueKey('banner-depth-card-$index'),
                        banner: banners[bIdx],
                        decodeWidth: decodeWidth,
                        isFocused: depth < 0.35,
                        dimAlpha: dimAlpha,
                        phone: phone,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({
    required this.banner,
    required this.pageBackground,
    required this.accent,
    required this.isDark,
    required this.reduceMotion,
  });

  final MediaBanner banner;
  final Color pageBackground;
  final Color accent;
  final bool isDark;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final bgLayer = banner.imageUrl.isNotEmpty
        ? Opacity(
            opacity: isDark ? 0.38 : 0.16,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 30,
                sigmaY: 30,
                tileMode: TileMode.clamp,
              ),
              child: Transform.scale(
                scale: 1.24,
                child: MediaCoverImage(
                  url: banner.imageUrl,
                  fallbackUrl: banner.fallbackImageUrl,
                  cacheWidth: 160,
                  errorWidget: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.2),
                        radius: 1.1,
                        colors: [
                          accent.withValues(alpha: isDark ? 0.28 : 0.16),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 1.05,
                colors: [
                  accent.withValues(alpha: isDark ? 0.20 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 500),
            child: SizedBox.expand(
              key: ValueKey('${banner.id}-${banner.imageUrl}'),
              child: bgLayer,
            ),
          ),
          // Feather top and bottom seamlessly into the page background.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  pageBackground.withValues(alpha: 0.42),
                  pageBackground.withValues(alpha: 0.14),
                  pageBackground.withValues(alpha: 0.72),
                  pageBackground,
                ],
                stops: const [0.0, 0.28, 0.78, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PureArtCard extends StatelessWidget {
  const _PureArtCard({
    super.key,
    required this.banner,
    required this.decodeWidth,
    required this.isFocused,
    required this.dimAlpha,
    required this.phone,
  });

  final MediaBanner banner;
  final int decodeWidth;
  final bool isFocused;
  final double dimAlpha;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(16);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isFocused ? (isDark ? 0.52 : 0.18) : (isDark ? 0.34 : 0.1),
            ),
            blurRadius: isFocused ? 28 : 16,
            offset: Offset(0, isFocused ? 12 : 6),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(
            alpha: isFocused ? (isDark ? 0.16 : 0.08) : (isDark ? 0.08 : 0.04),
          ),
          width: 1,
        ),
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
                fallbackUrl: banner.fallbackImageUrl,
                cacheWidth: decodeWidth,
                errorWidget: Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: t.textSecondary,
                    size: 28,
                  ),
                ),
              ),
            ),
            if (dimAlpha > 0.01)
              ColoredBox(color: Colors.black.withValues(alpha: dimAlpha)),
          ],
        ),
      ),
    );
  }
}

class _ExternalCaptionRow extends StatelessWidget {
  const _ExternalCaptionRow({
    required this.gutter,
    required this.controller,
    required this.loops,
    required this.fallbackPage,
    required this.bannerIndex,
    required this.bannerCount,
    required this.title,
    required this.onTapTitle,
    required this.onSelectDot,
    required this.reduceMotion,
  });

  final double gutter;
  final PageController controller;
  final bool loops;
  final double fallbackPage;
  final int bannerIndex;
  final int bannerCount;
  final String title;
  final VoidCallback? onTapTitle;
  final ValueChanged<int> onSelectDot;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final indexLabel = (bannerIndex + 1).toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter + 2),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapTitle,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: isDark ? 0.15 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      child: Text(
                        indexLabel,
                        key: ValueKey(indexLabel),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          color: t.accent,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) {
                        if (reduceMotion) return child;
                        final offset = Tween<Offset>(
                          begin: const Offset(0, 0.22),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        );
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Text(
                        title,
                        key: ValueKey('$bannerIndex-$title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                          letterSpacing: -0.1,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (bannerCount > 1) ...[
            const SizedBox(width: 12),
            _FluidBannerIndicator(
              controller: controller,
              loops: loops,
              fallbackPage: fallbackPage,
              count: bannerCount,
              accent: t.accent,
              accentEnd: isDark
                  ? const Color(0xFF9B7BFF)
                  : const Color(0xFF8B5CF6),
              inactiveColor: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.20,
              ),
              onTapDot: onSelectDot,
            ),
          ],
        ],
      ),
    );
  }
}

/// 1:1 finger-tracked liquid-worm dot indicator synchronized with [PageController].
///
/// Between adjacent slides the glowing lavender pill elastically stretches like a
/// liquid drop toward the destination dot and snaps smoothly into place; across
/// the circular wrap boundary (`last <-> first`) the outgoing pill gracefully
/// contracts while the incoming edge pill blooms open.
class _FluidBannerIndicator extends StatelessWidget {
  const _FluidBannerIndicator({
    required this.controller,
    required this.loops,
    required this.fallbackPage,
    required this.count,
    required this.accent,
    required this.accentEnd,
    required this.inactiveColor,
    required this.onTapDot,
  });

  static const double _dotWidth = 5.0;
  static const double _activeWidth = 20.0;
  static const double _gap = 5.0;
  static const double _dotHeight = 4.5;

  final PageController controller;
  final bool loops;
  final double fallbackPage;
  final int count;
  final Color accent;
  final Color accentEnd;
  final Color inactiveColor;
  final ValueChanged<int> onTapDot;

  double get _totalWidth =>
      _activeWidth + (count - 1) * _dotWidth + (count - 1) * _gap;

  @override
  Widget build(BuildContext context) {
    final totalW = _totalWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final fraction = (details.localPosition.dx / totalW).clamp(0.0, 0.999);
        onTapDot((fraction * count).floor());
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final page =
                controller.positions.length == 1 &&
                    controller.position.haveDimensions
                ? controller.page ?? fallbackPage
                : fallbackPage;
            final rawPos = loops ? page - 1.0 : page;
            return CustomPaint(
              size: Size(totalW, _dotHeight),
              painter: _LiquidDotsPainter(
                count: count,
                rawPosition: rawPos,
                dotWidth: _dotWidth,
                activeWidth: _activeWidth,
                gap: _gap,
                accent: accent,
                accentEnd: accentEnd,
                inactiveColor: inactiveColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiquidDotsPainter extends CustomPainter {
  const _LiquidDotsPainter({
    required this.count,
    required this.rawPosition,
    required this.dotWidth,
    required this.activeWidth,
    required this.gap,
    required this.accent,
    required this.accentEnd,
    required this.inactiveColor,
  });

  final int count;
  final double rawPosition;
  final double dotWidth;
  final double activeWidth;
  final double gap;
  final Color accent;
  final Color accentEnd;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final h = size.height;
    final radius = Radius.circular(h / 2);
    final inactivePaint = Paint()..color = inactiveColor;
    final extra = activeWidth - dotWidth;

    void paintGlowPill(double left, double width, double alpha) {
      if (alpha <= 0.01 || width <= 0.5) return;
      final rect = Rect.fromLTWH(left, 0, width, h);
      final rrect = RRect.fromRectAndRadius(rect, radius);

      final glowPaint = Paint()
        ..color = accent.withValues(alpha: 0.48 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
      canvas.drawRRect(rrect, glowPaint);

      final pillPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: alpha),
            accentEnd.withValues(alpha: alpha),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect, pillPaint);
    }

    // Circular wrap boundary: rawPosition < 0 (wrapping 0 -> last) or
    // rawPosition > count - 1 (wrapping last -> 0).
    if (rawPosition < 0 || rawPosition > count - 1) {
      final wrappingForward = rawPosition > count - 1;
      final w = wrappingForward
          ? (rawPosition - (count - 1)).clamp(0.0, 1.0)
          : (-rawPosition).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(w);
      final firstWeight = wrappingForward ? eased : 1.0 - eased;
      final lastWeight = 1.0 - firstWeight;

      double x = 0;
      for (var i = 0; i < count; i++) {
        final weight = i == 0
            ? firstWeight
            : i == count - 1
            ? lastWeight
            : 0.0;
        final slotW = dotWidth + extra * weight;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, slotW, h), radius),
          inactivePaint,
        );
        if (weight > 0.01) {
          paintGlowPill(x, slotW, weight);
        }
        x += slotW + gap;
      }
      return;
    }

    // Normal adjacent transition: continuous elastic liquid worm glide.
    final clamped = rawPosition.clamp(0.0, (count - 1).toDouble());
    final lower = clamped.floor();
    final upper = clamped.ceil();
    final t = clamped - lower;

    // 1. Compute dynamic slot positions & draw muted base dots.
    final slotLefts = List<double>.filled(count, 0);
    final slotWidths = List<double>.filled(count, dotWidth);
    double x = 0;
    for (var i = 0; i < count; i++) {
      final weight = i == lower && i == upper
          ? 1.0
          : i == lower
          ? (1.0 - t)
          : i == upper
          ? t
          : 0.0;
      final slotW = dotWidth + extra * weight;
      slotLefts[i] = x;
      slotWidths[i] = slotW;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, slotW, h), radius),
        inactivePaint,
      );
      x += slotW + gap;
    }

    // 2. Paint elastic liquid capsule stretching from lower -> upper.
    if (lower == upper) {
      paintGlowPill(slotLefts[lower], slotWidths[lower], 1.0);
      return;
    }
    final startLeft = slotLefts[lower];
    final startRight = startLeft + activeWidth;
    final endRight = slotLefts[upper] + slotWidths[upper];
    final endLeft = endRight - activeWidth;

    final headT = Curves.easeOutCubic.transform(t);
    final tailT = Curves.easeInCubic.transform(t);
    final pillLeft = lerpDouble(startLeft, endLeft, tailT)!;
    final pillRight = lerpDouble(startRight, endRight, headT)!;
    paintGlowPill(pillLeft, (pillRight - pillLeft).clamp(dotWidth, size.width), 1.0);
  }

  @override
  bool shouldRepaint(covariant _LiquidDotsPainter oldDelegate) =>
      oldDelegate.rawPosition != rawPosition ||
      oldDelegate.count != count ||
      oldDelegate.accent != accent ||
      oldDelegate.inactiveColor != inactiveColor;
}
