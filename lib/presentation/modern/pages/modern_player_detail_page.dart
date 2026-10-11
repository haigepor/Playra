import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_episode_sheet.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/info/info_actions_menu.dart';
import 'package:kazumi/pages/info/info_comments_view.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/rating_review_dialog.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/playback_scaffold.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import '../player/player_theme.dart';
import '../player/player_discussion.dart';
import '../player/player_detail_tabs.dart';
import '../player/player_episodes.dart';
import '../player/player_work_info.dart';

class ModernPlayerDetailPage extends StatefulWidget {
  const ModernPlayerDetailPage({
    super.key,
    required this.item,
    required this.infoController,
    required this.videoController,
    required this.playerController,
    required this.historyController,
    required this.downloadController,
    this.args,
  });
  final BangumiItem item;
  final InfoController infoController;
  final VideoPageController videoController;
  final PlayerController playerController;
  final HistoryController historyController;
  final DownloadController downloadController;
  final VideoPlaybackArgs? args;
  @override
  State<ModernPlayerDetailPage> createState() => _ModernPlayerDetailPageState();
}

class _ModernPlayerDetailPageState extends State<ModernPlayerDetailPage>
    with SingleTickerProviderStateMixin, KazumiDialogOwner {
  final playbackKey = GlobalKey<PlaybackScaffoldState>();
  late final tabs = TabController(
    length: 3,
    vsync: this,
    animationDuration: const Duration(milliseconds: 200),
  )..addListener(tabChanged);
  bool choosingSource = false, infoError = false, infoLoading = false;
  bool commentsLoading = false,
      commentsLoaded = false,
      commentsError = false,
      commentsMore = true;
  bool relationsLoading = false, relationsError = false;
  InfoController get info => widget.infoController;
  VideoPageController get video => widget.videoController;
  BangumiItem get item => info.bangumiItem;
  String get title => item.nameCn.isEmpty ? item.name : item.nameCn;
  bool get showRating => GStorage.getSetting(SettingsKeys.showRating) == true;
  bool get hasPlayback =>
      playbackKey.currentState?.hasPlayback ??
      widget.args is OfflineVideoPlaybackArgs;

  History? get resumeCandidate {
    final candidates =
        widget.historyController.histories
            .where(
              (h) =>
                  h.bangumiItem.id == item.id &&
                  h.entryKind == HistoryEntryKind.online &&
                  h.lastSrc.isNotEmpty &&
                  h.episodePageUrl.isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    return candidates.firstOrNull;
  }

  Future<void> resume(BuildContext context) async {
    final history = resumeCandidate;
    if (history == null) return chooseSource(context);
    if (dialogs.isRunning) return;
    await dialogs.run((task) async {
      final cancel = RuleCancelToken();
      final result = await task.loading(
        message: '确认历史来源',
        onCancel: cancel.cancel,
        action: () =>
            inject<HistoryPlaybackService>().open(history, cancelToken: cancel),
      );
      if (!mounted || !context.mounted) return;
      if (result is! HistoryPlaybackReady ||
          result.args is! OnlineVideoPlaybackArgs) {
        KazumiDialog.showToast(message: '历史来源暂不可用，请重新选择来源');
        return;
      }
      final args = result.args as OnlineVideoPlaybackArgs;
      final verified = verifiedResume(args, [history]);
      final selection =
          verified?.selection ??
          await showModernPlayerSheet<VideoEpisodeSelection>(
            context,
            PlayerEpisodesSheet(
              roads: args.roads,
              selected: const VideoEpisodeSelection(episode: 1, road: 0),
              sourceName: args.plugin.name,
              confirmSource: true,
            ),
          );
      if (!mounted || selection == null) return;
      await playbackKey.currentState?.startSource(
        args,
        selection,
        offset:
            verified != null &&
                GStorage.getSetting(SettingsKeys.playResume) == true
            ? verified.offset
            : 0,
      );
    }, errorMessage: '暂时无法继续播放，请重新选源');
  }

  @override
  void initState() {
    super.initState();
    info.bangumiItem = widget.item;
    video.bangumiItem = widget.item;
    unawaited(loadInfo());
    unawaited(loadRelations());
    // 在线路由只提供来源上下文；身份不匹配时先确认目标，不能猜历史索引。
    if (widget.args case final OnlineVideoPlaybackArgs args) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final resume = verifiedResume(args, widget.historyController.histories);
        final selection =
            resume?.selection ??
            await showModernPlayerSheet<VideoEpisodeSelection>(
              playbackKey.currentContext!,
              PlayerEpisodesSheet(
                roads: args.roads,
                selected: const VideoEpisodeSelection(episode: 1, road: 0),
                sourceName: args.plugin.name,
                confirmSource: true,
              ),
            );
        if (!mounted || selection == null) return;
        await playbackKey.currentState?.startSource(
          args,
          selection,
          offset:
              resume != null &&
                  GStorage.getSetting(SettingsKeys.playResume) == true
              ? resume.offset
              : 0,
        );
      });
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void tabChanged() {
    if (tabs.index == 2 && !commentsLoaded && !commentsLoading) loadComments();
  }

  Future<void> loadInfo() async {
    if (infoLoading) return;
    setState(() {
      infoLoading = true;
      infoError = false;
    });
    try {
      final loaded = await BangumiApi.getBangumiInfoByID(item.id);
      if (!mounted) return;
      if (loaded == null) throw StateError('作品资料加载失败');
      // 海报继续使用进入页面时的 URL，避免补齐资料导致封面闪烁。
      if (item.images.values.any((url) => url.isNotEmpty)) {
        loaded.images = item.images;
      }
      info.bangumiItem = loaded;
      await info.collectController.updateLocalCollect(loaded);
    } catch (_) {
      if (mounted) setState(() => infoError = true);
    } finally {
      if (mounted) setState(() => infoLoading = false);
    }
  }

  Future<void> loadRelations() async {
    if (relationsLoading) return;
    setState(() {
      relationsLoading = true;
      relationsError = false;
    });
    try {
      await info.queryBangumiRelationsByID(item.id);
    } catch (_) {
      if (mounted) setState(() => relationsError = true);
    } finally {
      if (mounted) setState(() => relationsLoading = false);
    }
  }

  Future<void> loadComments({bool more = false}) async {
    if (commentsLoading || (more && (!commentsMore || commentsError))) return;
    final before = info.commentsList.length;
    setState(() {
      commentsLoading = true;
      commentsError = false;
    });
    try {
      await info.queryBangumiCommentsByID(item.id, refresh: !more);
      if (!mounted) return;
      setState(() {
        commentsLoaded = true;
        commentsMore = more
            ? info.commentsList.length > before
            : info.commentsList.isNotEmpty;
      });
      await info.fillInterestUserProfileIfNeeded();
    } catch (_) {
      if (mounted) setState(() => commentsError = true);
    } finally {
      if (mounted) setState(() => commentsLoading = false);
    }
  }

  Future<void> writeReview() async {
    if (GStorage.getSetting(
      SettingsKeys.bangumiAccessToken,
    ).toString().trim().isEmpty) {
      KazumiDialog.showToast(message: '请先在同步设置中绑定 Bangumi');
      return;
    }
    final type = info.collectController.getCollectType(item);
    if (type == 0) {
      KazumiDialog.showToast(message: '请先追番');
      return;
    }
    // 编辑会唤起键盘，仅恢复由此表单主动暂停的播放。
    final wasPlaying = widget.playerController.playback.playing;
    if (wasPlaying) await widget.playerController.pause();
    if (!mounted) return;
    try {
      final submitted = await KazumiDialog.show<bool>(
        context: context,
        builder: (_) => RatingReviewDialog(
          bangumiItem: item,
          onSubmit: (review) => info.rateBangumi(review, localType: type),
        ),
      );
      if (mounted && submitted == true) setState(() {});
    } finally {
      if (mounted && wasPlaying) await widget.playerController.play();
    }
  }

  Future<void> chooseSource(BuildContext themedContext) async {
    if (choosingSource) return;
    setState(() => choosingSource = true);
    try {
      final args = await showAdaptiveBottomSheet<OnlineVideoPlaybackArgs>(
        context: themedContext,
        maxHeightFactor: .9,
        builder: (sheetContext) => SourceSheet(
          infoController: info,
          emptyIllustration: SvgPicture.asset(
            'assets/images/modern-player-empty-source.svg',
            width: 136,
            height: 95,
            excludeFromSemantics: true,
          ),
          onSelected: (args) => Navigator.of(sheetContext).pop(args),
        ),
      );
      if (!mounted || args == null || !themedContext.mounted) return;
      final resume = !hasPlayback
          ? verifiedResume(args, widget.historyController.histories)
          : null;
      var target = resume?.selection;
      target ??= await showModernPlayerSheet<VideoEpisodeSelection>(
        themedContext,
        PlayerEpisodesSheet(
          roads: args.roads,
          selected: const VideoEpisodeSelection(episode: 1, road: 0),
          sourceName: args.plugin.name,
          confirmSource: true,
        ),
      );
      if (!mounted || target == null) return;
      final offset =
          resume != null && GStorage.getSetting(SettingsKeys.playResume) == true
          ? resume.offset
          : 0;
      await playbackKey.currentState?.startSource(args, target, offset: offset);
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => choosingSource = false);
    }
  }

  Set<String> get downloadedUrls {
    if (!hasPlayback || video.isOfflineMode) return {};
    final record = widget.downloadController.getRecord(
      item.id,
      video.currentPlugin.name,
    );
    return {
      for (final e in record?.episodes.values ?? <DownloadEpisode>[])
        if (e.status == DownloadStatus.completed && e.episodePageUrl.isNotEmpty)
          e.episodePageUrl,
    };
  }

  Future<void> allEpisodes(BuildContext context) async {
    if (!hasPlayback) return chooseSource(context);
    final result = await showModernPlayerSheet<VideoEpisodeSelection>(
      context,
      PlayerEpisodesSheet(
        roads: video.roadList.toList(),
        selected: video.selectedEpisode,
        playing: widget.playerController.playback.playing && !video.loading
            ? video.playingEpisode
            : null,
        sourceName: video.isOfflineMode
            ? '离线 · ${video.offlinePluginName}'
            : video.currentPlugin.name,
        downloadedUrls: downloadedUrls,
      ),
    );
    if (mounted && result != null && result != video.selectedEpisode) {
      await playbackKey.currentState?.changeEpisode(
        result.episode,
        currentRoad: result.road,
      );
    }
  }

  void download(BuildContext context) {
    if (kIsWeb) {
      KazumiDialog.showToast(message: '请在原生客户端中下载');
      return;
    }
    if (!hasPlayback) {
      chooseSource(context);
      return;
    }
    if (video.isOfflineMode) {
      KazumiDialog.showToast(message: '当前正在播放离线文件');
      return;
    }
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (_) => DownloadEpisodeSheet(
        road: video.selectedEpisode.road,
        videoPageController: video,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ModernPlayerScope(
    child: Builder(
      builder: (context) => PlaybackScaffold(
        key: playbackKey,
        args: widget.args is OfflineVideoPlaybackArgs ? widget.args : null,
        verifyHistoryIdentity: true,
        videoPageController: video,
        playerController: widget.playerController,
        historyController: widget.historyController,
        downloadController: widget.downloadController,
        idlePlayerBuilder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            PlayerCover(url: item.images['large'] ?? '', player: true),
            const ColoredBox(color: Color(0x66000000)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadButton(
                    onPressed: choosingSource ? null : () => resume(context),
                    width: 52,
                    height: 52,
                    padding: EdgeInsets.zero,
                    decoration: ShadDecoration(
                      border: ShadBorder(radius: BorderRadius.circular(26)),
                    ),
                    child: choosingSource
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.play, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    choosingSource
                        ? '正在选择来源'
                        : resumeCandidate != null
                        ? '继续观看 · ${resumeCandidate!.lastWatchEpisodeName}'
                        : '选择来源播放',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 4,
              child: IconButton(
                tooltip: '返回',
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(LucideIcons.chevronLeft, size: 22),
              ),
            ),
            Positioned(top: 0, right: 4, child: actionsMenu(context)),
          ],
        ),
        contentBuilder: (context, _) => Column(
          children: [
            PlayerDetailTabs(
              controller: tabs,
              disableAnimations:
                  GStorage.getSetting(SettingsKeys.playerDisableAnimations) ==
                  true,
            ),
            Expanded(
              child: TabBarView(
                controller: tabs,
                children: [
                  Observer(builder: (context) => detail(context)),
                  Observer(
                    builder: (_) => PlayerDiscussion(
                      subjectId: item.id,
                      episode: hasPlayback
                          ? video.resolveEpisode(video.selectedEpisode)
                          : null,
                    ),
                  ),
                  Observer(
                    builder: (context) => InfoCommentsView(
                      interest: item.interest,
                      comments: info.commentsList.toList(),
                      isLoading: commentsLoading,
                      hasLoaded: commentsLoaded,
                      hasError: commentsError,
                      onReviewTap: writeReview,
                      onRetry: () => loadComments(),
                      onLoadMore: () => loadComments(more: true),
                      useOverlap: false,
                      showRatings: showRating,
                      numericRatings: true,
                      header: Column(
                        children: [
                          scoreOverview(context),
                          if (commentsError && info.commentsList.isNotEmpty)
                            TextButton(
                              onPressed: () => loadComments(),
                              child: const Text('刷新失败，点击重试'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget detail(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final selection = video.selectedEpisode;
    final road = hasPlayback && selection.road < video.roadList.length
        ? video.roadList[selection.road]
        : null;
    final count = road == null
        ? 0
        : math.min(road.data.length, road.identifier.length);
    final start = math.max(0, selection.episode - 3);
    return ListView(
      key: const PageStorageKey('modern-player-detail'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            if (showRating && item.votes > 0)
              Text(
                '☆ ${item.ratingScore.toStringAsFixed(1)}',
                style: TextStyle(
                  color: c.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (item.airDate.isNotEmpty) item.airDate,
            ...item.metaTags,
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            foregroundColor: c.onSurfaceVariant,
          ),
          onPressed: () => showModernPlayerSheet<void>(
            context,
            PlayerWorkInfoSheet(
              controller: info,
              beforeNavigate: widget.playerController.pause,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.summary.isEmpty
                      ? '查看简介、角色与制作人员'
                      : item.summary.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Text('简介', style: TextStyle(color: c.primary, fontSize: 12)),
              const Icon(LucideIcons.chevronRight, size: 16),
            ],
          ),
        ),
        if (infoError)
          TextButton(onPressed: loadInfo, child: const Text('资料未能补齐，点击重试')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Theme(
              data: Theme.of(context).copyWith(
                filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(100, 48),
                    backgroundColor: c.secondaryContainer,
                    foregroundColor: c.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              child: CollectButton.extend(bangumiItem: item),
            ),
            TextButton.icon(
              onPressed: () => download(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: c.onSurfaceVariant,
              ),
              icon: const Icon(LucideIcons.download, size: 18),
              label: const Text('下载'),
            ),
            actionsMenu(context),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                '选集',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => allEpisodes(context),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                hasPlayback ? '共 $count 集 · 全部 ›' : '选择来源 ›',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (hasPlayback) ...[
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '来源',
                style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
              ),
              TextButton(
                onPressed: choosingSource ? null : () => chooseSource(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  video.isOfflineMode
                      ? '离线 · ${video.offlinePluginName}'
                      : '${video.currentPlugin.name}⌄',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => allEpisodes(context),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  road?.name ?? '',
                  style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(
            height: math.max(56, MediaQuery.textScalerOf(context).scale(42)),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(8, math.max(0, count - start)),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final index = start + i;
                final selected = VideoEpisodeSelection(
                  episode: index + 1,
                  road: selection.road,
                );
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: PlayerEpisodeButton(
                    title: road!.identifier[index],
                    selected: selected == selection,
                    playing:
                        video.playingEpisode == selected &&
                        widget.playerController.playback.playing &&
                        !video.loading,
                    downloaded: downloadedUrls.contains(road.data[index]),
                    onTap: () {
                      if (selected != selection) {
                        playbackKey.currentState?.changeEpisode(
                          index + 1,
                          currentRoad: selection.road,
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.errorMessage ??
                (video.loading
                    ? '正在解析选中的剧集'
                    : video.resolveEpisode(selection)?.displayTitle ?? ''),
            style: TextStyle(fontSize: 11, color: c.onSurfaceVariant),
          ),
          if (video.errorMessage != null)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => playbackKey.currentState?.changeEpisode(
                    selection.episode,
                    currentRoad: selection.road,
                  ),
                  child: const Text('重试'),
                ),
                TextButton(
                  onPressed: () => chooseSource(context),
                  child: const Text('换源'),
                ),
              ],
            ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选源后，在这里查看线路与全部剧集。',
                  style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                ),
                TextButton.icon(
                  onPressed: choosingSource
                      ? null
                      : () => chooseSource(context),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: const Text('选择来源播放'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        const Text(
          '关联作品',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (relationsLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (relationsError)
          TextButton(
            onPressed: loadRelations,
            child: const Text('关联作品加载失败，点击重试'),
          )
        else if (info.relationList.isEmpty)
          Text(
            '暂无关联作品',
            style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
          )
        else
          PlayerRelations(
            relations: info.relationList.toList(),
            beforeNavigate: widget.playerController.pause,
          ),
      ],
    );
  }

  Widget actionsMenu(BuildContext context) => IconButtonTheme(
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        minimumSize: const Size(48, 48),
      ),
    ),
    child: InfoActionsMenu(bangumiItem: item),
  );

  Widget scoreOverview(BuildContext context) {
    if (!showRating) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    if (item.votes <= 0) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('暂无评分', style: TextStyle(color: c.onSurfaceVariant)),
      );
    }
    final maxVotes = item.votesCount.fold<int>(1, math.max);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.ratingScore.toStringAsFixed(1),
                style: TextStyle(
                  color: c.primary,
                  fontSize: 36,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${item.votes} 人评分 · 十分制',
                style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
              ),
            ],
          ),
          SizedBox(
            width: 156,
            child: Column(
              children: [
                for (var i = 9; i >= 0; i--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: i < item.votesCount.length
                                ? item.votesCount[i] / maxVotes
                                : 0,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(3),
                            backgroundColor: c.surfaceContainerLow,
                          ),
                        ),
                      ],
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
