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

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return SizedBox(
      width: width,
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
            ),
            const SizedBox(height: PlayraSpace.compact),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.foreground,
                fontSize: PlayraType.item,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (item.subtitle.isNotEmpty || item.metaText.isNotEmpty)
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
  });

  final MediaItem item;
  final int? rank;
  final bool showScore;
  final int? decodeWidth;
  final Color mutedColor;
  final Color subtleColor;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
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
                    cacheWidth: decodeWidth,
                    errorWidget: Icon(
                      item.cover.isEmpty
                          ? Icons.movie_outlined
                          : Icons.broken_image_outlined,
                      color: subtleColor,
                      size: 26,
                    ),
                  ),
                ),
                if (showScore && (item.score ?? 0) > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _Badge(
                      text: MediaPosterCard._scoreText(item.score!),
                      highlight: true,
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight
            ? t.primary.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(PlayraTokens.radiusXs),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: highlight ? t.primaryForeground : Colors.white,
          fontSize: PlayraType.micro,
          fontWeight: FontWeight.w600,
          height: 1.1,
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
class MediaSearchField extends StatelessWidget {
  const MediaSearchField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.focusNode,
    this.hint = '输入作品名',
    this.onSubmitted,
    this.onClear,
  });

  final TextEditingController controller;
  final bool autofocus;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = PlayraTokens.of(context);
    return Container(
      constraints: BoxConstraints(
        minHeight: 40,
        maxHeight: (MediaQuery.textScalerOf(context).scale(16) + 20).clamp(
          40,
          70,
        ),
      ),
      padding: const EdgeInsets.only(
        left: PlayraSpace.md,
        right: PlayraSpace.xs,
      ),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: TextStyle(color: t.foreground, fontSize: PlayraType.body),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TextStyle(
                  color: t.foregroundSubtle,
                  fontSize: PlayraType.body,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: '清空',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.cancel_rounded, size: 17),
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
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final EdgeInsets insets;
  final bool ranked;
  final int phoneColumns;
  final bool showScore;

  static const double _maxExtent = 140;
  static const double _tabletMaxExtent = 180;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gap = phoneColumns == 2 ? 9.0 : 6.0;
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
          var columns =
              MediaQuery.sizeOf(context).shortestSide <
                  PlayraLayout.compactWidth
              ? ((available + gap) /
                        (scaler.scale(PlayraType.item) * 5.5 + gap))
                    .floor()
                    .clamp(1, phoneColumns)
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
                      decodeWidth: (tileWidth * dpr).round(),
                      onTap: () => onTap(items[first + offset]),
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
  });

  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

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
