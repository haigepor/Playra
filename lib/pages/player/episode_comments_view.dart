import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/bean/card/user_comments_card.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart';

class EpisodeCommentsView extends StatelessWidget {
  const EpisodeCommentsView({
    super.key,
    required this.episode,
    required this.episodeInfo,
    required this.comments,
    required this.isLoading,
    required this.hasError,
    required this.isAscending,
    required this.onToggleSort,
    required this.onSelectEpisode,
    required this.onRefresh,
    this.emptyState,
  });

  final int episode;
  final EpisodeInfo? episodeInfo;
  final List<EpisodeCommentItem> comments;
  final bool isLoading;
  final bool hasError;
  final bool isAscending;
  final VoidCallback onToggleSort;
  final VoidCallback onSelectEpisode;
  final VoidCallback onRefresh;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: LayoutBuilder(builder: (context, constraints) {
        final gutter = constraints.maxWidth > 760
            ? (constraints.maxWidth - 728) / 2
            : 16.0;
        return CustomScrollView(
          key: ValueKey(episode),
          scrollBehavior: const ScrollBehavior().copyWith(
            scrollbars: false,
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.trackpad,
            },
          ),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, PlayraSpace.lg, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: _EpisodeHeader(
                  episode: episode,
                  info: episodeInfo,
                  onSelectEpisode: onSelectEpisode,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter + PlayraSpace.xs, PlayraSpace.lg, gutter, PlayraSpace.md),
              sliver: SliverToBoxAdapter(child: _buildToolbar(context)),
            ),
            if (isLoading && comments.isEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: const SliverToBoxAdapter(child: SkeletonComments()),
              )
            else if (!isLoading && hasError && comments.isEmpty)
              SliverToBoxAdapter(
                child: GeneralErrorWidget(
                  icon: Icons.cloud_off_rounded,
                  title: '评论暂时未能加载',
                  errMsg: '请检查网络后重试，或切换分集查看讨论。',
                  onRetry: onRefresh,
                  retryText: '重新加载',
                ),
              )
            else if (!isLoading && comments.isEmpty)
              SliverToBoxAdapter(
                child: emptyState ?? const GeneralEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '本集还没有讨论',
                ),
              )
            else if (comments.isNotEmpty) ...[
              if (hasError)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, PlayraSpace.md),
                  sliver: SliverToBoxAdapter(
                    child: Material(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(PlayraRadius.card),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(PlayraSpace.lg, PlayraSpace.xs, PlayraSpace.sm, PlayraSpace.xs),
                        child: Row(children: [
                          Expanded(
                            child: Text('刷新失败，已保留现有讨论',
                                style:
                                    TextStyle(color: colors.onErrorContainer)),
                          ),
                          PlayraButton.ghost(
                            onPressed: onRefresh,
                            child: const Text('重试'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => KeepAlive(
                      // Retain BBCode image geometry and expanded discussions.
                      key: ObjectKey(comments[index]),
                      keepAlive: true,
                      child: IndexedSemantics(
                        index: index,
                        child: UserCommentsCard.episode(comments[index]),
                      ),
                    ),
                    childCount: comments.length,
                    findChildIndexCallback: (key) {
                      final index = comments.indexOf(
                          (key as ObjectKey).value as EpisodeCommentItem);
                      return index < 0 ? null : index;
                    },
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    addSemanticIndexes: false,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(PlayraSpace.lg, PlayraSpace.sm, PlayraSpace.lg, PlayraSpace.xxl),
                  child: Text('已显示全部 ${comments.length} 条讨论 · 来自 Bangumi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, constraints) {
      final title = Row(mainAxisSize: MainAxisSize.min, children: [
        Text('讨论',
            style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if ((!isLoading && !hasError) || comments.isNotEmpty) ...[
          const SizedBox(width: PlayraSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md, vertical: PlayraSpace.xs),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(PlayraRadius.overlay),
            ),
            child: Text('${comments.length}',
                style: type.labelLarge
                    ?.copyWith(color: colors.onSecondaryContainer)),
          ),
        ],
      ]);
      final actions = Row(mainAxisSize: MainAxisSize.min, children: [
        PlayraButton.ghostIcon(
          onPressed: comments.length > 1 ? onToggleSort : null,
          icon: Icon(
              isAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18),
          label: Text(isAscending ? '最早优先' : '最新优先'),
        ),
        const SizedBox(width: PlayraSpace.xs),
        PlayraIconButton(
          tooltip: isLoading ? '正在加载评论' : '刷新评论',
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
              ? LoadingIndicator(
                  size: 20,
                  color: colors.onSecondaryContainer,
                  semanticsLabel: '正在加载评论',
                )
              : const Icon(Icons.refresh_rounded, size: 20),
        ),
      ]);
      if (constraints.maxWidth < 310 ||
          MediaQuery.textScalerOf(context).scale(14) > 19) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title,
          const SizedBox(height: PlayraSpace.xs),
          Align(alignment: Alignment.centerRight, child: actions),
        ]);
      }
      return Row(children: [title, const Spacer(), actions]);
    });
  }
}

class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({
    required this.episode,
    required this.info,
    required this.onSelectEpisode,
  });

  final int episode;
  final EpisodeInfo? info;
  final VoidCallback onSelectEpisode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final type = Theme.of(context).textTheme;
    final number = info?.episode ?? episode;
    final translatedTitle = info?.nameCn ?? '';
    final originalTitle = info?.name ?? '';
    final title = translatedTitle.isNotEmpty
        ? translatedTitle
        : originalTitle.isNotEmpty
            ? originalTitle
            : '第 $number 集';
    final subtitle = originalTitle.isNotEmpty && originalTitle != title
        ? originalTitle
        : '';
    final episodeType = info?.readType().toUpperCase() ?? 'EP';

    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(PlayraRadius.card),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(PlayraSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: PlayraSpace.md, vertical: PlayraSpace.sm),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(PlayraRadius.control),
                    ),
                    child: Text('$episodeType $number'.trim(),
                        style: type.titleSmall?.copyWith(
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w700)),
                  ),
                  PlayraButton.outlineIcon(
                    onPressed: onSelectEpisode,
                    icon: const Icon(Icons.video_library_outlined, size: 18),
                    label: const Text('切换分集'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PlayraSpace.lg),
            Semantics(
              header: true,
              child: Text(title,
                  style: type.titleLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  )),
            ),
            const SizedBox(height: PlayraSpace.compact),
            // Reserve one line to prevent jumps when metadata arrives.
            Tooltip(
              message: subtitle,
              child: Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
