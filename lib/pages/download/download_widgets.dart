import 'package:flutter/material.dart';

import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/presentation/modern/secondary/utility_page_art.dart';

const Duration _kExpandDuration = Duration(milliseconds: 250);
const Curve _kExpandCurve = Curves.easeInOutCubic;

class DownloadRecordCard extends StatelessWidget {
  const DownloadRecordCard({
    super.key,
    required this.record,
    required this.expanded,
    required this.onToggle,
    required this.onResumeAll,
    required this.onDeleteAll,
    required this.totalSpeed,
    required this.episodeTileBuilder,
  });

  final DownloadRecord record;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onResumeAll;
  final VoidCallback onDeleteAll;
  final double totalSpeed;

  final List<Widget> Function() episodeTileBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final episodes = record.episodes.values;
    final totalCount = episodes.length;
    final completedCount = episodes
        .where((e) => e.status == DownloadStatus.completed)
        .length;
    final activeCount = episodes
        .where(
          (e) =>
              e.status == DownloadStatus.downloading ||
              e.status == DownloadStatus.resolving ||
              e.status == DownloadStatus.pending,
        )
        .length;
    final aggregateProgress = totalCount == 0
        ? 0.0
        : episodes.fold<double>(
                0,
                (sum, e) =>
                    sum +
                    (e.status == DownloadStatus.completed
                        ? 1.0
                        : e.progressPercent),
              ) /
              totalCount;
    final allCompleted = completedCount >= totalCount;

    var meta = '$completedCount/$totalCount 已完成';
    if (activeCount > 0) {
      meta += ' · $activeCount 项进行中';
      if (totalSpeed > 0) {
        meta += ' · ${formatSpeed(totalSpeed)}';
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: .3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NetworkImgLayer(
                        src: record.bangumiCover,
                        width: 56,
                        height: 75,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.bangumiName,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '来源 · ${record.pluginName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      KazumiMenuButton(
                        animated: false,
                        builder: (context, toggle) => IconButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: '更多操作',
                          onPressed: toggle,
                        ),
                        menuChildren: [
                          KazumiMenuItem(label: '全部开始', onPressed: onResumeAll),
                          KazumiMenuItem(
                            label: '全部删除',
                            destructive: true,
                            onPressed: onDeleteAll,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        expanded ? '收起分集' : '查看分集',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : _kExpandDuration,
                        curve: _kExpandCurve,
                        child: Icon(
                          Icons.expand_more,
                          color: colorScheme.primary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 收起时显示作品总进度；展开后由分集进度承担主要反馈。
          if (!allCompleted && !expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, expanded ? 4 : 16),
              child: LinearProgressIndicator(value: aggregateProgress),
            ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : _kExpandDuration,
            curve: _kExpandCurve,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(children: episodeTileBuilder()),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class DownloadEpisodeTile extends StatelessWidget {
  const DownloadEpisodeTile({
    super.key,
    required this.episode,
    required this.statusText,
    this.actions = const [],
    this.onPlay,
  });

  final DownloadEpisode episode;
  final String statusText;
  final List<Widget> actions;

  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isError = episode.status == DownloadStatus.failed;
    final showProgress =
        episode.status == DownloadStatus.downloading ||
        (episode.status == DownloadStatus.paused &&
            episode.progressPercent > 0);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          episode.episodeName.isNotEmpty
              ? episode.episodeName
              : '第${episode.episodeNumber}集',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          statusText,
          style: textTheme.bodySmall?.copyWith(
            color: isError ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showProgress || episode.status == DownloadStatus.resolving) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: episode.status == DownloadStatus.resolving
                ? null
                : episode.progressPercent,
            minHeight: 3,
          ),
        ],
      ],
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final stacked =
                bounds.maxWidth < 480 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EpisodeStatusBadge(episode: episode),
                    const SizedBox(width: 12),
                    Expanded(child: body),
                    if (!stacked) ...[const SizedBox(width: 8), ...actions],
                  ],
                ),
                if (stacked && actions.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(children: actions),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EpisodeStatusBadge extends StatelessWidget {
  const _EpisodeStatusBadge({required this.episode});

  final DownloadEpisode episode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final kind = switch (episode.status) {
      DownloadStatus.completed => UtilityIconKind.completed,
      DownloadStatus.downloading => UtilityIconKind.downloading,
      DownloadStatus.resolving => UtilityIconKind.resolving,
      DownloadStatus.failed => UtilityIconKind.failed,
      DownloadStatus.paused => UtilityIconKind.paused,
      _ => UtilityIconKind.pending,
    };
    final isError = episode.status == DownloadStatus.failed;
    final foreground = isError ? colorScheme.error : colorScheme.primary;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(child: UtilitySvgIcon(kind, size: 20, color: foreground)),
    );
  }
}
