import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/pages/player/episode_comments_view.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'player_episodes.dart';

class PlayerDiscussion extends StatefulWidget {
  const PlayerDiscussion({
    super.key,
    required this.subjectId,
    required this.episode,
    this.canonicalEpisode,
  });
  final int subjectId;
  final EpisodeRef? episode;
  final EpisodeInfo? canonicalEpisode;
  @override
  State<PlayerDiscussion> createState() => _PlayerDiscussionState();
}

class _PlayerDiscussionState extends State<PlayerDiscussion>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  int version = 0;
  bool loading = false, error = false, ascending = true;
  List<EpisodeInfo>? episodes;
  EpisodeInfo? matched;
  List<EpisodeCommentItem> comments = [];
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(covariant PlayerDiscussion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId) episodes = null;
    if (oldWidget.subjectId != widget.subjectId ||
        oldWidget.episode?.pageUrl != widget.episode?.pageUrl ||
        oldWidget.canonicalEpisode?.id != widget.canonicalEpisode?.id ||
        oldWidget.episode?.displayTitle != widget.episode?.displayTitle) {
      matched = null;
      comments = [];
      refresh();
    }
  }

  Future<void> refresh({EpisodeInfo? manual}) async {
    final request = ++version;
    if (widget.episode == null &&
        widget.canonicalEpisode == null &&
        manual == null) {
      setState(() {
        loading = false;
        error = false;
        matched = null;
        comments = [];
      });
      return;
    }
    setState(() {
      loading = true;
      error = false;
    });
    try {
      final list =
          episodes ??
          (manual != null || widget.canonicalEpisode != null
              ? null
              : await BangumiApi.getBangumiEpisodesByID(
                  widget.subjectId,
                  throwOnError: true,
                ));
      if (!mounted || request != version) return;
      if (list != null) episodes = list;
      final target =
          manual ??
          widget.canonicalEpisode ??
          matchDiscussionEpisode(widget.episode!.displayTitle, list ?? []);
      if (target == null) {
        setState(() {
          matched = null;
          loading = false;
          comments = [];
        });
        return;
      }
      final response = await BangumiApi.getBangumiCommentsByEpisodeID(
        target.id,
      );
      if (!mounted || request != version) return;
      setState(() {
        matched = target;
        comments = response.commentList;
        sort();
        loading = false;
      });
    } catch (_) {
      if (mounted && request == version) {
        setState(() {
          error = true;
          loading = false;
        });
      }
    }
  }

  void sort() => comments.sort(
    (a, b) => ascending
        ? a.comment.createdAt.compareTo(b.comment.createdAt)
        : b.comment.createdAt.compareTo(a.comment.createdAt),
  );
  Future<void> pick() async {
    if (episodes == null) {
      try {
        episodes = await BangumiApi.getBangumiEpisodesByID(
          widget.subjectId,
          throwOnError: true,
        );
      } catch (_) {
        if (mounted) setState(() => error = true);
        return;
      }
      if (!mounted || episodes == null) return;
    }
    final chosen = await showModernPlayerSheet<EpisodeInfo>(
      context,
      Column(
        children: [
          const PlayerSheetHeader(title: '选择讨论对应的分集'),
          Expanded(
            child: ListView.builder(
              itemCount: episodes!.length,
              itemBuilder: (context, i) {
                final item = episodes![i];
                return ListTile(
                  minVerticalPadding: 12,
                  title: Text(
                    '${item.readType()} ${item.episode} · ${item.nameCn.isEmpty ? item.name : item.nameCn}',
                  ),
                  selected: matched?.id == item.id,
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ],
      ),
    );
    if (mounted && chosen != null) await refresh(manual: chosen);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (matched == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          if (loading)
            const SkeletonComments()
          else ...[
            Text(
              error
                  ? '讨论加载失败'
                  : widget.episode == null
                  ? '先选择播放剧集'
                  : '尚未匹配到资料库分集',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              error ? '请检查网络后重试。' : '讨论对应真实分集；特别篇和来源集数不一致时，可手动选择。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (error)
              TextButton(onPressed: refresh, child: const Text('重新加载')),
            TextButton(onPressed: pick, child: const Text('匹配讨论分集')),
          ],
        ],
      );
    }
    return EpisodeCommentsView(
      episode: matched!.episode.toInt(),
      episodeInfo: matched,
      comments: comments,
      isLoading: loading,
      hasError: error,
      isAscending: ascending,
      onToggleSort: () => setState(() {
        ascending = !ascending;
        sort();
      }),
      onSelectEpisode: pick,
      onRefresh: () => refresh(manual: matched),
      emptyState: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            SvgPicture.asset(
              'assets/images/modern-player-empty-discussion.svg',
              width: 136,
              height: 95,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 12),
            const Text('这集还没有讨论'),
          ],
        ),
      ),
    );
  }
}
