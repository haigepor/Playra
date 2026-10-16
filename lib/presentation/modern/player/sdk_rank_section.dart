import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/lumina/lumina_models.dart';
import '../miomedia/miomedia_browse.dart';
import '../widgets/modern_section_mark.dart';

/// 保留原榜单的标题和横向海报布局，只替换为两端真实内容。
class SdkRankSection extends StatelessWidget {
  const SdkRankSection({
    super.key,
    required this.controller,
    required this.onDetails,
  });
  final SdkRankController controller;
  final ValueChanged<SdkPlaybackEntry> onDetails;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final entries = controller.entries;
      final slots = controller.displaySlots;
      final loading =
          controller.loading.isNotEmpty || controller.discoveringSources;
      final failed = controller.failed.isNotEmpty;
      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ModernSectionMark(kind: ModernSectionKind.ranking),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '热播推荐',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              // 状态入口留在标题行，失败提示不能把已显示的海报向下挤动。
              if (failed || entries.isEmpty && !loading)
                Tooltip(
                  message: failed
                      ? entries.isEmpty
                            ? '推荐加载失败；点击重试'
                            : '部分来源暂不可用，显示已有推荐；点击重试'
                      : '当前暂无推荐；点击刷新',
                  child: SizedBox(
                    width: 48,
                    height: 24,
                    child: TextButton(
                      onPressed: loading ? null : controller.retry,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        foregroundColor: colors.primary,
                      ),
                      child: Text(
                        failed ? '重试' : '刷新',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (slots.isNotEmpty)
            LayoutBuilder(
              builder: (context, bounds) {
                final width = (bounds.maxWidth / 3.1 - 8).clamp(104.0, 144.0);
                final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                return SizedBox(
                  height: width * 1.42 + 66 * scale,
                  child: ListView.separated(
                    key: const PageStorageKey('sdk-rank'),
                    scrollDirection: Axis.horizontal,
                    itemCount: slots.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final entry = slots[index];
                      if (entry == null) {
                        return SizedBox(
                          key: ValueKey('sdk-rank-pending-$index'),
                          width: width,
                          child: loading
                              ? const ContentSkeleton(
                                  animate: false,
                                  child: SkeletonPosterCard(),
                                )
                              : Semantics(
                                  label: '此来源暂无推荐',
                                  child: const Center(
                                    child: Icon(Icons.movie_outlined),
                                  ),
                                ),
                        );
                      }
                      final video = entry.video;
                      return SizedBox(
                        key: ValueKey('sdk-rank-${entry.identity}'),
                        width: width,
                        child: MioPoster(
                          video: video,
                          identity: entry.identity,
                          providerName: entry.providerName,
                          statusLabel: video is LuminaVideo
                              ? video.updateLabel
                              : null,
                          rank: entry.position,
                          rankIsSequence: true,
                          onTap: () => onDetails(entry.playbackEntry),
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
    },
  );
}
