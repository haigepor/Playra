import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import '../home/modern_home_controller.dart';
import 'miomedia_browse.dart';
import 'miomedia_home_controller.dart';

String? mioRankCategory(
  MioHomeController controller,
  HomeFeed feed,
) => switch (feed) {
  HomeFeed.recommended || HomeFeed.popular => '0',
  HomeFeed.movies => controller.categoryIds[MioKind.movie],
  HomeFeed.television => controller.categoryIds[MioKind.series],
  HomeFeed.variety => controller.categoryIds[MioKind.variety],
  HomeFeed.comicDrama => controller.categoryIds[MioKind.comicDrama],
  HomeFeed.anime =>
    controller.namedCategoryIds['动漫大全'] ?? controller.namedCategoryIds['动漫'],
  HomeFeed.season => controller.namedCategoryIds['热门新番'],
  HomeFeed.japanese =>
    controller.namedCategoryIds['日本动漫'] ?? controller.namedCategoryIds['日韩动漫'],
  HomeFeed.chinese => controller.namedCategoryIds['国产动漫'],
  HomeFeed.animeMovies => controller.namedCategoryIds['动漫电影'],
};

class MioRankSection extends StatefulWidget {
  const MioRankSection({
    super.key,
    required this.controller,
    required this.categoryId,
    required this.onDetails,
  });
  final MioHomeController controller;
  final String? categoryId;
  final ValueChanged<MioVideo> onDetails;
  @override
  State<MioRankSection> createState() => _MioRankSectionState();
}

class _MioRankSectionState extends State<MioRankSection> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MioRankSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        oldWidget.controller != widget.controller) {
      _load();
    }
  }

  void _load() {
    // 首页构建阶段不发通知；同分类请求在控制器内去重。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.categoryId != null) {
        widget.controller.loadRanking(widget.categoryId!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final id = widget.categoryId;
    final rank = controller.rankings[id];
    final loading = id == null
        ? controller.discovering
        : controller.rankLoading.contains(id) ||
              (!controller.rankings.containsKey(id) &&
                  !controller.rankFailed.contains(id));
    final failed = controller.rankFailed.contains(id);
    final colors = Theme.of(context).colorScheme;
    if (rank == null && loading) return const SkeletonPosters();
    final retry = id == null
        ? null
        : () => controller.loadRanking(id, refresh: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rank != null) ...[
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rank.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (failed || rank == null || rank.entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  failed ? Icons.info_outline_rounded : Icons.bar_chart_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    failed
                        ? (rank == null ? '榜单加载失败' : '榜单更新失败，显示上次结果')
                        : '当前分类无榜单',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (retry != null)
                  TextButton(
                    onPressed: loading ? null : retry,
                    child: Text(
                      failed ? '重试' : '刷新',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        if (rank != null && rank.entries.isNotEmpty)
          LayoutBuilder(
            builder: (context, bounds) {
              final width = (bounds.maxWidth / 3.1 - 8).clamp(104.0, 144.0);
              final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
              return SizedBox(
                height: width * 1.42 + 66 * scale,
                child: ListView.separated(
                  key: PageStorageKey('mio-rank-$id'),
                  scrollDirection: Axis.horizontal,
                  itemCount: rank.entries.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final entry = rank.entries[index];
                    return SizedBox(
                      key: ValueKey('mio-rank-$id-${entry.position}'),
                      width: width,
                      child: MioPoster(
                        video: entry.video,
                        rank: entry.position,
                        onTap: () => widget.onDetails(entry.video),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
