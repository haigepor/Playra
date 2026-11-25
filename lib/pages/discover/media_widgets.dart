import 'dart:ui' show ImageFilter;

import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

/// Poster card shared by discover / browse / search.
class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    super.key,
    required this.item,
    this.width = 118,
    this.rank,
    this.showScore = false,
    this.onTap,
    this.decodeWidth,
    this.overlayStatus = false,
    this.onRemove,
    this.coverAspectRatio = 2 / 3,
  });

  final MediaItem item;
  final double width;

  /// 1-based position inside a ranked section; null hides the badge.
  final int? rank;
  final bool showScore;
  final VoidCallback? onTap;

  /// Decoding width in physical pixels; keeps long grids from holding
  /// full-resolution bitmaps in memory.
  final int? decodeWidth;

  /// Compact grid presentation with status over the artwork and one title line.
  final bool overlayStatus;
  final VoidCallback? onRemove;
  final double coverAspectRatio;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final status = item.subtitle.isNotEmpty
        ? item.subtitle
        : item.episodeCount > 0
        ? '${item.episodeCount} 集'
        : '';
    return SizedBox(
      width: width,
      child: Semantics(
        container: true,
        button: onTap != null,
        label:
            '${onTap == null ? '作品' : '查看'} ${item.title}'
            '${status.isEmpty ? '' : '，$status'}'
            '${onRemove == null && showScore && (item.score ?? 0) > 0 ? '，评分 ${_scoreText(item.score!)}' : ''}',
        onTap: onTap,
        excludeSemantics: onRemove == null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PlayraRadius.poster),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PosterCover(
                item: item,
                rank: rank,
                showScore: showScore,
                decodeWidth: decodeWidth,
                mutedColor: t.muted,
                subtleColor: t.foregroundSubtle,
                overlayStatus: overlayStatus,
                onRemove: onRemove,
                coverAspectRatio: coverAspectRatio,
              ),
              const SizedBox(height: PlayraSpace.compact),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.textScalerOf(context).scale(PlayraType.item) *
                      (overlayStatus ? 1.2 : 2.4),
                ),
                child: Text(
                  item.title,
                  maxLines: overlayStatus ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.foreground,
                    fontSize: PlayraType.item,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (!overlayStatus &&
                  (item.subtitle.isNotEmpty || item.metaText.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: PlayraSpace.tiny),
                  child: Text(
                    item.subtitle.isNotEmpty ? item.subtitle : item.metaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.foregroundSubtle,
                      fontSize: PlayraType.caption,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _scoreText(double score) {
    return score == score.roundToDouble()
        ? score.toStringAsFixed(0)
        : score.toStringAsFixed(1);
  }
}

/// Poster artwork, with an optional ranking or sort score.
class _PosterCover extends StatelessWidget {
  const _PosterCover({
    required this.item,
    required this.rank,
    required this.showScore,
    required this.decodeWidth,
    required this.mutedColor,
    required this.subtleColor,
    required this.overlayStatus,
    required this.onRemove,
    required this.coverAspectRatio,
  });

  final MediaItem item;
  final int? rank;
  final bool showScore;
  final int? decodeWidth;
  final Color mutedColor;
  final Color subtleColor;
  final bool overlayStatus;
  final VoidCallback? onRemove;
  final double coverAspectRatio;

  @override
  Widget build(BuildContext context) {
    final status = item.subtitle.isNotEmpty
        ? item.subtitle
        : item.episodeCount > 0
        ? '${item.episodeCount} 集'
        : '';
    return AspectRatio(
      aspectRatio: coverAspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(PlayraRadius.poster),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: mutedColor,
                  child: MediaCoverImage(
                    url: item.cover,
                    fallbackUrl: item.fallbackCover,
                    cacheWidth: decodeWidth,
                    errorWidget: ColoredBox(
                      color: mutedColor,
                      child: Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: subtleColor.withValues(alpha: 0.72),
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
                if (onRemove == null && showScore && (item.score ?? 0) > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: PosterScoreCornerBadge(
                      scoreText: MediaPosterCard._scoreText(item.score!),
                      topRightRadius: PlayraRadius.poster,
                    ),
                  ),
                if (overlayStatus && status.isNotEmpty)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: _Badge(text: status),
                    ),
                  ),
                if (onRemove != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: '移除${item.title}',
                      onPressed: onRemove,
                      icon: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .68),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                if (rank != null && rank! > 0)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _Badge(text: 'TOP $rank', highlight: rank! <= 3),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Flush top-right frosted glass score badge whose outer corner matches the
/// poster's exact [topRightRadius] so no background peeks around the curve.
class PosterScoreCornerBadge extends StatelessWidget {
  const PosterScoreCornerBadge({
    super.key,
    required this.scoreText,
    this.topRightRadius = PlayraRadius.poster,
  });

  final String scoreText;
  final double topRightRadius;

  @override
  Widget build(BuildContext context) {
    final cornerRadius = BorderRadius.only(
      topRight: Radius.circular(topRightRadius),
      bottomLeft: const Radius.circular(10),
    );
    return ClipRRect(
      borderRadius: cornerRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 3, 7, 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xC21A1524), Color(0x9E0E111A)],
            ),
            borderRadius: cornerRadius,
            border: const Border(
              left: BorderSide(color: Color(0x4DFDE68A), width: 0.75),
              bottom: BorderSide(color: Color(0x4DFDE68A), width: 0.75),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 11.5,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 2),
              Text(
                scoreText,
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Color(0xFFFEF08A),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final radius = BorderRadius.circular(
      highlight ? PlayraTokens.radiusXs : 6,
    );
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: highlight ? t.primaryForeground : Colors.white,
        fontSize: PlayraType.micro,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    );
    if (highlight) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.92),
          borderRadius: radius,
        ),
        child: label,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x6612151E),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.75,
            ),
          ),
          child: label,
        ),
      ),
    );
  }
}

/// Chip used by every selection row: discover categories, browse sort,
/// detail roads and episodes. One implementation keeps selected/unselected
/// colors identical across pages.
class MediaSelectChip extends StatelessWidget {
  const MediaSelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
    this.minWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Episodes use a denser chip than categories / roads.
  final bool dense;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final radius = BorderRadius.circular(
      dense ? PlayraTokens.radiusSm : PlayraRadius.control,
    );
    return Material(
      color: selected
          ? (dense ? t.primary : t.primaryContainer)
          : t.surfaceRaised,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: BoxConstraints(
            minWidth: minWidth ?? 0,
            minHeight: mediaChipHeight(context),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? PlayraSpace.sm : PlayraSpace.md,
            vertical: dense ? PlayraSpace.sm : PlayraSpace.xs,
          ),
          // 不设 alignment：在 Wrap 里 Container 带 alignment 会撑满整行，
          // 分集列表就变成一行一个全宽按钮了。
          decoration: BoxDecoration(
            borderRadius: radius,
            // 分集 chip 的填充色和页面背景太接近，加一条发丝边框才看得出格子；
            // 选中态用透明边框保持尺寸一致。
            border: Border.all(
              color: selected
                  ? (dense
                        ? Colors.transparent
                        : t.primary.withValues(alpha: 0.4))
                  : t.borderSubtle,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? (dense ? t.primaryForeground : t.primary)
                  : t.mutedForeground,
              fontSize: dense ? PlayraType.caption : PlayraType.label,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of one chip, scaled with the system font size so large text does
/// not clip inside fixed-height selection strips.
double mediaChipHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler.scale(PlayraType.label) * 1.2 + PlayraSpace.md * 2;
}

/// Height of a fixed-height chip strip (chip + vertical padding).
double mediaChipStripHeight(BuildContext context, {double vertical = 1}) {
  return mediaChipHeight(context) + PlayraSpace.sm * 2 * vertical;
}

/// Height of a horizontal poster strip: cover (3:4) + title + meta line.
double mediaPosterStripHeight(BuildContext context, {double cardWidth = 118}) {
  final scaler = MediaQuery.textScalerOf(context);
  return cardWidth * 4 / 3 +
      PlayraSpace.compact +
      scaler.scale(PlayraType.item) * 1.2 +
      PlayraSpace.tiny +
      scaler.scale(PlayraType.caption) * 1.2 +
      // 2px 余量吸收字体度量取整，避免 1px 溢出。
      PlayraSpace.tiny +
      PlayraSpace.xs;
}

/// Tap target that opens the search page from discover.
class MediaSearchEntry extends StatelessWidget {
  const MediaSearchEntry({super.key, required this.onTap, this.hint = '输入作品名'});

  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(PlayraRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayraRadius.control),
        child: Container(
          height: PlayraLayout.inputHeight,
          padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayraRadius.control),
            border: Border.all(color: t.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: t.foregroundSubtle),
              const SizedBox(width: PlayraSpace.sm),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.foregroundSubtle,
                    fontSize: PlayraType.body,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editable search box used by the search page; same surface, radius and
/// height as [MediaSearchEntry] so the transition between them is seamless.
class MediaSearchField extends StatefulWidget {
  const MediaSearchField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.focusNode,
    this.hint = '输入作品名',
    this.onSubmitted,
    this.onClear,
    this.showIcon = true,
  });

  final TextEditingController controller;
  final bool autofocus;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool showIcon;

  @override
  State<MediaSearchField> createState() => _MediaSearchFieldState();
}

class _MediaSearchFieldState extends State<MediaSearchField> {
  FocusNode? _internalFocusNode;
  bool _focused = false;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focused = _effectiveFocusNode.hasFocus;
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant MediaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)?.removeListener(
        _handleFocusChange,
      );
      _focused = _effectiveFocusNode.hasFocus;
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final next = _effectiveFocusNode.hasFocus;
    if (next != _focused && mounted) {
      setState(() => _focused = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? t.surface : Colors.white;
    final borderColor = _focused
        ? t.primary.withValues(alpha: isDark ? 0.62 : 0.7)
        : (isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.09));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: _focused ? 1.2 : 1),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: t.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          if (widget.showIcon) ...[
            Icon(
              Icons.search_rounded,
              size: 18,
              color: _focused
                  ? t.primary
                  : t.foregroundSubtle.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              autofocus: widget.autofocus,
              focusNode: _effectiveFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                color: t.foreground,
                fontSize: PlayraType.body,
                height: 1.3,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: t.foregroundSubtle.withValues(alpha: 0.72),
                  fontSize: PlayraType.body,
                ),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            Semantics(
              button: true,
              label: '清空',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: t.foreground.withValues(alpha: 0.08),
                  splashColor: t.foreground.withValues(alpha: 0.12),
                  onTap: widget.onClear,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.foregroundSubtle.withValues(
                            alpha: isDark ? 0.24 : 0.18,
                          ),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: isDark ? t.foreground : t.foregroundSubtle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Poster grid used by browse / search / section grids.
///
/// The delegate is computed from the real cross-axis extent, so tiles keep a
/// 3:4 cover and one meta line at any font scale instead of relying on a fixed
/// childAspectRatio that clips large text.
class MediaPosterGrid extends StatelessWidget {
  const MediaPosterGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.insets = const EdgeInsets.symmetric(horizontal: PlayraSpace.xl),
    this.ranked = false,
    this.phoneColumns = 3,
    this.showScore = false,
    this.overlayStatus = false,
    this.fixedColumns,
    this.onRemove,
    this.coverAspectRatio = 2 / 3,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem>? onTap;
  final EdgeInsets insets;
  final bool ranked;
  final int phoneColumns;
  final bool showScore;
  final bool overlayStatus;
  final int? fixedColumns;
  final ValueChanged<MediaItem>? onRemove;
  final double coverAspectRatio;

  static const double _maxExtent = 140;
  static const double _tabletMaxExtent = 180;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gap = phoneColumns == 2 ? 12.0 : 8.0;
    return SliverPadding(
      padding: insets,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.crossAxisExtent;
          final maxExtent =
              MediaQuery.sizeOf(context).shortestSide >=
                  PlayraLayout.compactWidth
              ? _tabletMaxExtent
              : _maxExtent;
          final isPhone =
              MediaQuery.sizeOf(context).shortestSide <
              PlayraLayout.compactWidth;
          var columns = isPhone
              ? ((available + gap) /
                        (scaler.scale(PlayraType.item) *
                                (phoneColumns == 2 ? 5.5 : 4.5) +
                            gap))
                    .floor()
                    .clamp(1, fixedColumns ?? phoneColumns)
              : ((available + gap) / (maxExtent + gap)).ceil();
          if (columns < 1) columns = 1;
          final tileWidth = (available - gap * (columns - 1)) / columns;
          return SliverList.separated(
            itemCount: (items.length / columns).ceil(),
            separatorBuilder: (_, _) => const SizedBox(height: PlayraSpace.sm),
            itemBuilder: (context, row) {
              final first = row * columns;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var offset = 0;
                    offset < columns && first + offset < items.length;
                    offset++
                  ) ...[
                    if (offset > 0) SizedBox(width: gap),
                    MediaPosterCard(
                      item: items[first + offset],
                      width: tileWidth,
                      rank: ranked ? first + offset + 1 : null,
                      showScore: showScore,
                      overlayStatus: overlayStatus,
                      coverAspectRatio: coverAspectRatio,
                      onRemove: onRemove == null
                          ? null
                          : () => onRemove!(items[first + offset]),
                      decodeWidth: (tileWidth * dpr).round(),
                      onTap: onTap == null
                          ? null
                          : () => onTap!(items[first + offset]),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Pagination feedback for search and category results.
class MediaGridFooter extends StatelessWidget {
  const MediaGridFooter({
    super.key,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onLoadMore,
  });

  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (error != null && onRetry != null) {
      return MediaRetryNotice(
        message: '下一页加载失败',
        retrying: loading,
        onRetry: onRetry!,
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: PlayraSpace.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (onLoadMore != null) {
      return Center(
        child: TextButton(onPressed: onLoadMore, child: const Text('加载更多')),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Scrollable wrapper so empty / error states still accept pull-to-refresh.
class MediaStateScrollView extends StatelessWidget {
  const MediaStateScrollView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    );
  }
}

class MediaSectionHeader extends StatelessWidget {
  const MediaSectionHeader({
    super.key,
    required this.title,
    this.tabs = const <String>[],
    this.trailing,
  });

  final String title;

  /// Server-side board labels shown next to the title, e.g. `热播榜`.
  final List<String> tabs;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayraSpace.xl,
        PlayraSpace.xxl,
        PlayraSpace.xl,
        PlayraSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.foreground,
                      fontSize: PlayraType.section,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                if (tabs.isNotEmpty) ...[
                  const SizedBox(width: PlayraSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: t.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        PlayraTokens.radiusXs,
                      ),
                    ),
                    child: Text(
                      tabs.first,
                      style: TextStyle(
                        color: t.primary,
                        fontSize: PlayraType.micro,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// In-place feedback for a failed feed or page request.
class MediaRetryNotice extends StatelessWidget {
  const MediaRetryNotice({
    super.key,
    required this.message,
    this.error,
    required this.retrying,
    required this.onRetry,
  });
  final String message;
  final Object? error;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = retrying
        ? '正在重试'
        : switch (error) {
            MediaSourceException(kind: MediaSourceErrorKind.network) =>
              '网络连接失败',
            MediaSourceException(kind: MediaSourceErrorKind.protocol) =>
              '内容源响应异常',
            MediaSourceException(:final message) => message,
            String reason => reason,
            _ => message,
          };
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                onPressed: retrying ? null : onRetry,
                child: retrying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaErrorState extends StatelessWidget {
  const MediaErrorState({
    super.key,
    required this.message,
    required this.error,
    required this.onRetry,
  });

  final String message;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PlayraPageState(
    icon: Icons.cloud_off_outlined,
    title: message,
    description: switch (error) {
      MediaSourceException(kind: MediaSourceErrorKind.network) => '请检查网络连接后再试。',
      MediaSourceException(:final message) => message,
      String reason => reason,
      _ => null,
    },
    action: FilledButton(onPressed: onRetry, child: const Text('重试')),
  );
}

class MediaLoadingState extends StatelessWidget {
  const MediaLoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          if (label != null) ...[
            const SizedBox(height: PlayraSpace.md),
            Text(
              label!,
              style: TextStyle(
                color: t.foregroundSubtle,
                fontSize: PlayraType.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
