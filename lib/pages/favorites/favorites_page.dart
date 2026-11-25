import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 追番（收藏）页面 · 质感追更清单（方案 B）。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.onDiscover});
  final VoidCallback onDiscover;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _editing = false;

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titleTextStyle: Theme.of(
          dialog,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        title: const Text('清空全部追番？'),
        content: const Text('清空后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          PlayraButton.destructive(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FavoriteStorage.clearAll();
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final t = PlayraHomeTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: ValueListenableBuilder<Box<dynamic>>(
                valueListenable: FavoriteStorage.listenable(),
                builder: (context, box, child) {
                  final favorites = FavoriteStorage.getAll();
                  final editing = _editing && favorites.isNotEmpty;
                  return Column(
                    children: [
                      PlayraPageHeader(
                        title: '追番',
                        largeTitle: true,
                        subtitle: '${favorites.length} 部作品',
                        actions: [
                          if (editing)
                            TextButton(
                              onPressed: _confirmClear,
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              child: const Text('清空'),
                            ),
                          if (favorites.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _editing = !editing),
                              child: Text(editing ? '完成' : '编辑'),
                            ),
                        ],
                      ),
                      Divider(height: 1, thickness: 1, color: t.divider),
                      Expanded(
                        child: favorites.isEmpty
                            ? const _FavoritesEmptyState()
                            : _FavoritesWatchlist(
                                layout: layout,
                                favorites: favorites,
                                editing: editing,
                                onEmpty: () {
                                  if (mounted) setState(() => _editing = false);
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(28, 24, 28, bottomInset + 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FannedPosterStack(accent: t.accent, isDark: isDark, tokens: t),
            const SizedBox(height: 18),
            Text(
              '还没有追番',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FannedPosterStack extends StatelessWidget {
  const _FannedPosterStack({
    required this.accent,
    required this.isDark,
    required this.tokens,
  });

  final Color accent;
  final bool isDark;
  final PlayraHomeTokens tokens;

  Widget _buildSideCard({
    required double dx,
    required double angleDeg,
  }) {
    return Transform.translate(
      offset: Offset(dx, 6),
      child: Transform.rotate(
        angle: angleDeg * math.pi / 180,
        child: Transform.scale(
          scale: 0.9,
          child: Opacity(
            opacity: isDark ? 0.74 : 0.84,
            child: Container(
              width: 66,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  begin: const Alignment(-0.7, -1),
                  end: const Alignment(0.7, 1),
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.075),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : [
                          tokens.cardSurface,
                          tokens.cardPlaceholder.withValues(alpha: 0.7),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.11)
                      : tokens.divider.withValues(alpha: 0.8),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.08),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centerTop = isDark
        ? Color.lerp(const Color(0xFF181A26), accent, 0.22)!
        : Color.lerp(Colors.white, accent, 0.14)!;
    final centerBottom = isDark
        ? const Color(0xFF171925)
        : tokens.cardSurface;

    return SizedBox(
      width: 170,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 164,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.22 : 0.15),
                  accent.withValues(alpha: isDark ? 0.07 : 0.04),
                  accent.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),
          _buildSideCard(dx: -40, angleDeg: -13),
          _buildSideCard(dx: 40, angleDeg: 13),
          Container(
            width: 74,
            height: 102,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(
                begin: const Alignment(-0.6, -1),
                end: const Alignment(0.6, 1),
                colors: [centerTop, centerBottom],
              ),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.34 : 0.32),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.46 : 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.favorite_border_rounded,
                    size: 17,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 11),
                Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.45 : 0.42),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : tokens.textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesWatchlist extends StatelessWidget {
  const _FavoritesWatchlist({
    required this.layout,
    required this.favorites,
    required this.editing,
    required this.onEmpty,
  });

  final HomeLayoutMetrics layout;
  final List<FavoriteRecord> favorites;
  final bool editing;
  final VoidCallback onEmpty;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final hasAnyStatus = favorites.any((f) => f.statusText.isNotEmpty);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideColumns = constraints.maxWidth >= 700 ? 2 : 1;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                14,
                layout.gutter,
                hasAnyStatus ? 8 : 16,
              ),
              sliver: wideColumns == 1
                  ? SliverList.separated(
                      itemCount: favorites.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _WatchlistCard(
                        fav: favorites[index],
                        editing: editing,
                        onTap: () => context.pushNamed(
                          '/detail',
                          arguments: MediaKey(
                            sourceId: favorites[index].sourceId,
                            mediaId: favorites[index].mediaId,
                          ),
                        ),
                        onRemove: () => _removeItem(favorites[index]),
                      ),
                    )
                  : SliverGrid.builder(
                      itemCount: favorites.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent:
                            (MediaQuery.textScalerOf(context).scale(14) * 2.5 +
                                    64)
                                .clamp(96.0, double.infinity),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) => _WatchlistCard(
                        fav: favorites[index],
                        editing: editing,
                        onTap: () => context.pushNamed(
                          '/detail',
                          arguments: MediaKey(
                            sourceId: favorites[index].sourceId,
                            mediaId: favorites[index].mediaId,
                          ),
                        ),
                        onRemove: () => _removeItem(favorites[index]),
                      ),
                    ),
            ),
            if (hasAnyStatus)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.gutter,
                    6,
                    layout.gutter,
                    12,
                  ),
                  child: Text(
                    '更新状态为收藏时记录，可能不是最新',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.textSecondary.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + PlayraSpace.lg,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeItem(FavoriteRecord fav) async {
    await FavoriteStorage.remove(fav.sourceId, fav.mediaId);
    if (FavoriteStorage.getAll().isEmpty) onEmpty();
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({
    required this.fav,
    required this.editing,
    required this.onTap,
    required this.onRemove,
  });

  final FavoriteRecord fav;
  final bool editing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.038)
        : t.cardSurface;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : t.divider.withValues(alpha: 0.6);
    final hasCategory = fav.category.isNotEmpty;
    final hasStatus = fav.statusText.isNotEmpty;

    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        hoverColor: t.accent.withValues(alpha: 0.06),
        splashColor: t.accent.withValues(alpha: 0.12),
        onTap: editing ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: t.cardPlaceholder,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaCoverImage(
                  url: fav.cover,
                  cacheWidth:
                      (56 * MediaQuery.devicePixelRatioOf(context)).round(),
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fav.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    if (hasCategory || hasStatus) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (hasCategory)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.065)
                                    : t.searchFill,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                fav.category,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: t.textSecondary,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          if (hasStatus)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.accent.withValues(
                                  alpha: isDark ? 0.15 : 0.12,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                fav.statusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: t.accent,
                                  height: 1.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (editing)
                IconButton(
                  tooltip: '移除${fav.title}',
                  onPressed: onRemove,
                  constraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: t.textSecondary.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
