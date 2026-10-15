import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/source/source_candidates.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';
import 'package:kazumi/services/source/anime_source_session.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
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
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
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
import '../player/sdk_source_widgets.dart';

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
    this.sourceRules,
  });
  final BangumiItem item;
  final InfoController infoController;
  final VideoPageController videoController;
  final PlayerController playerController;
  final HistoryController historyController;
  final DownloadController downloadController;
  final VideoPlaybackArgs? args;
  final List<Plugin>? sourceRules;
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
  List<EpisodeInfo> catalogEpisodes = [];
  EpisodeInfo? selectedCatalogEpisode;
  bool episodesLoading = false, episodesError = false;
  String? automaticSourceError;
  final episodeCatalogCancel = RuleCancelToken();
  RuleCancelToken? automaticSourceCancel;
  late final sourceSession = AnimeSourceSession(widget.item)
    ..addListener(sourcesChanged);
  String? selectedSdkId;
  int manualLineGeneration = 0;
  VoidCallback? refreshSourceSheet;
  List<Plugin> get sourceRules =>
      widget.sourceRules ?? inject<PluginsController>().pluginList.toList();
  List<PlaybackSourceGroup> get sourceGroups => PlaybackSourceGroup.fromPlugins(
    SourceCandidates.shared.eligible(sourceRules, item),
  );
  PlaybackSourceGroup? get selectedGroup {
    final id =
        selectedSdkId ??
        (hasPlayback && !video.isOfflineMode
            ? playbackSdkId(video.currentPlugin)
            : 'anifive');
    return sourceGroups.where((g) => g.id == id).firstOrNull ??
        sourceGroups.firstOrNull;
  }

  void sourcesChanged() {
    if (mounted) {
      setState(() {});
      refreshSourceSheet?.call();
    }
  }

  InfoController get info => widget.infoController;
  VideoPageController get video => widget.videoController;
  BangumiItem get item => info.bangumiItem;
  String get title => item.nameCn.isEmpty ? item.name : item.nameCn;
  bool get showRating => GStorage.getSetting(SettingsKeys.showRating) == true;
  bool get hasPlayback =>
      playbackKey.currentState?.hasPlayback ??
      widget.args is OfflineVideoPlaybackArgs;

  void playbackReady() {
    // 外壳已进入播放会话，下方视图马上显示来源目录，不等待解析 Future 结束。
    if (mounted) setState(() {});
  }

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
    if (history == null) return playAutomatically();
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
        final number = regularEpisodeNumber(history.lastWatchEpisodeName);
        await playAutomatically(number: number);
        return;
      }
      final args = result.args as OnlineVideoPlaybackArgs;
      if (args.initialEpisode != null) {
        await playbackKey.currentState?.startSource(
          args,
          VideoEpisodeSelection(
            episode: args.initialEpisode!,
            road: args.initialRoad,
          ),
          onReady: playbackReady,
        );
        return;
      }
      final verified = verifiedResume(args, [history]);
      if (verified == null) {
        await playAutomatically(
          number: regularEpisodeNumber(history.lastWatchEpisodeName),
        );
        return;
      }
      final selection = verified.selection;
      if (!mounted) return;
      await playbackKey.currentState?.startSource(
        args,
        selection,
        onReady: playbackReady,
        offset: GStorage.getSetting(SettingsKeys.playResume) == true
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
    unawaited(loadEpisodeCatalog());
  }

  @override
  void dispose() {
    episodeCatalogCancel.cancel('page disposed');
    automaticSourceCancel?.cancel('page disposed');
    sourceSession.dispose();
    tabs.dispose();
    super.dispose();
  }

  void tabChanged() {
    if (tabs.index == 2 && !commentsLoaded && !commentsLoading) loadComments();
  }

  Future<void> loadEpisodeCatalog() async {
    if (episodesLoading || episodeCatalogCancel.isCancelled) return;
    setState(() {
      episodesLoading = true;
      episodesError = false;
    });
    try {
      final list = await BangumiApi.getBangumiEpisodesByID(
        item.id,
        throwOnError: true,
        cancelToken: episodeCatalogCancel,
        onPage: (page) {
          if (!mounted) return;
          setState(
            () => catalogEpisodes = page
                .where(
                  (e) =>
                      e.type == 0 &&
                      e.episode > 0 &&
                      e.episode == e.episode.toInt(),
                )
                .toList(),
          );
        },
      );
      if (!mounted) return;
      setState(
        () => catalogEpisodes = list
            .where(
              (e) =>
                  e.type == 0 &&
                  e.episode > 0 &&
                  e.episode == e.episode.toInt(),
            )
            .toList(),
      );
    } catch (_) {
      if (mounted) setState(() => episodesError = true);
    } finally {
      if (mounted) setState(() => episodesLoading = false);
    }
  }

  Future<void> playAutomatically({EpisodeInfo? episode, int? number}) async {
    if (choosingSource || video.isOfflineMode && hasPlayback) return;
    if (hasPlayback &&
        episode == null &&
        number == null &&
        regularEpisodeNumber(
              video.resolveEpisode(video.selectedEpisode)?.displayTitle ?? '',
            ) ==
            null) {
      setState(() => automaticSourceError = '当前特别篇无法自动对齐，请手动选择线路和剧集');
      return;
    }
    selectedCatalogEpisode =
        episode ?? selectedCatalogEpisode ?? catalogEpisodes.firstOrNull;
    final targetNumber =
        number ??
        episode?.episode.toInt() ??
        (hasPlayback
            ? regularEpisodeNumber(
                video.resolveEpisode(video.selectedEpisode)?.displayTitle ?? '',
              )
            : selectedCatalogEpisode?.episode.toInt()) ??
        1;
    final cancel = RuleCancelToken();
    automaticSourceCancel?.cancel('superseded');
    automaticSourceCancel = cancel;
    setState(() {
      choosingSource = true;
      automaticSourceError = null;
    });
    try {
      final choice = await SourceCandidates.shared
          .selectEpisode(
            item,
            selectedGroup?.plugins ?? [],
            targetNumber,
            cancel,
          )
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (!mounted || cancel.isCancelled) return;
      // 找到可用目录即停止余下探测；解析与首帧失败继续由现有播放会话自动换源。
      cancel.cancel('candidate selected');
      setState(() => choosingSource = false);
      if (choice == null) {
        setState(
          () => automaticSourceError = '暂未找到第 $targetNumber 集的可用来源，可重试或手动换源',
        );
        return;
      }
      sourceSession.seed(choice.candidate);
      await playbackKey.currentState?.startSource(
        choice.candidate.args(item, automatic: true),
        VideoEpisodeSelection(episode: choice.episode, road: choice.road),
        onReady: playbackReady,
        offset:
            hasPlayback &&
                regularEpisodeNumber(
                      video
                              .resolveEpisode(video.selectedEpisode)
                              ?.displayTitle ??
                          '',
                    ) ==
                    targetNumber
            ? widget.playerController.playback.playerPosition.inSeconds
            : 0,
        expectedDuration: hasPlayback
            ? widget.playerController.playback.playerDuration
            : null,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && identical(automaticSourceCancel, cancel)) {
        setState(() => automaticSourceError = '自动选源失败，请重试或手动换源');
      }
    } finally {
      cancel.cancel('selection finished');
      if (mounted && identical(automaticSourceCancel, cancel)) {
        setState(() => choosingSource = false);
      }
    }
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
      sourceSession.updateWork(loaded);
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
    manualLineGeneration++;
    automaticSourceCancel?.cancel('manual source selection');
    automaticSourceCancel = null;
    final oldNumber = hasPlayback
        ? regularEpisodeNumber(
            video.resolveEpisode(video.selectedEpisode)?.displayTitle ?? '',
          )
        : null;
    final oldPosition = hasPlayback
        ? widget.playerController.playback.playerPosition.inSeconds
        : 0;
    final oldDuration = hasPlayback
        ? widget.playerController.playback.playerDuration
        : null;
    setState(() => choosingSource = true);
    try {
      final args = await showAdaptiveBottomSheet<OnlineVideoPlaybackArgs>(
        context: themedContext,
        maxHeightFactor: .9,
        builder: (sheetContext) => SourceSheet(
          rules: selectedGroup?.plugins,
          infoController: info,
          episodeNumber: oldNumber,
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
      selectedSdkId = playbackSdkId(args.plugin);
      sourceSession.seed(
        PlaybackCandidate(
          plugin: args.plugin,
          item: SearchItem(name: args.title, src: args.src),
          roads: args.roads,
          matched: SourceCandidates.shared.matches(item, args.title),
        ),
      );
      final resume = !hasPlayback
          ? verifiedResume(args, widget.historyController.histories)
          : null;
      var target = resume?.selection;
      final sameWorkCandidate = SourceCandidates.shared.find(
        item,
        args.plugin,
        args.src,
      );
      if (target == null && oldNumber != null) {
        final matched = sameWorkCandidate?.matched == true
            ? sameWorkCandidate?.matchEpisode(oldNumber)
            : null;
        if (matched != null) {
          target = VideoEpisodeSelection(
            episode: matched.episode,
            road: matched.road,
          );
        }
      }
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
      // 选源弹层打开时播放仍可继续，提交时重新读取实际进度。
      final livePosition =
          widget.playerController.playback.playerPosition.inSeconds;
      final liveDuration = widget.playerController.playback.playerDuration;
      final offset =
          resume != null && GStorage.getSetting(SettingsKeys.playResume) == true
          ? resume.offset
          : sameWorkCandidate?.matched == true &&
                oldNumber != null &&
                regularEpisodeNumber(
                      args.roads[target.road].identifier[target.episode - 1],
                    ) ==
                    oldNumber
          ? (livePosition > 0 ? livePosition : oldPosition)
          : 0;
      await playbackKey.currentState?.startSource(
        args,
        target,
        onReady: playbackReady,
        offset: offset,
        expectedDuration: oldDuration == null
            ? null
            : (liveDuration > Duration.zero ? liveDuration : oldDuration),
      );
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => choosingSource = false);
    }
  }

  Widget sourceControls(BuildContext context) {
    if (hasPlayback && video.isOfflineMode)
      return Text('离线 · ${video.offlinePluginName}');
    final group = selectedGroup;
    final entries = [
      for (final p in group?.plugins ?? <Plugin>[])
        if (sourceSession.status[p.providerId] == 'ready')
          ...?sourceSession.entries[p.providerId],
    ];
    final count = entries.fold<int>(0, (n, c) => n + c.roads.length);
    final sameGroup =
        hasPlayback && playbackSdkId(video.currentPlugin) == group?.id;
    final road = sameGroup && video.selectedEpisode.road < video.roadList.length
        ? video.roadList[video.selectedEpisode.road]
        : null;
    final automatic = !hasPlayback || video.automaticSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlaybackSourcePanel(
          selectorKey: const ValueKey('anime-line-selector'),
          trailing: IconButton(
            tooltip: '高级选源',
            onPressed: choosingSource ? null : () => chooseSource(context),
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
          ),
          groups: [
            for (final g in sourceGroups)
              PlaybackSdkChip(
                name: g.name,
                selected: group?.id == g.id,
                onSelected: choosingSource
                    ? null
                    : () {
                        if (selectedGroup?.id == g.id) return;
                        setState(() => selectedSdkId = g.id);
                        unawaited(playAutomatically());
                      },
              ),
          ],
          automatic: automatic,
          summary: choosingSource
              ? '正在准备新线路…'
              : road == null
              ? '自动 · 优选线路'
              : '${automatic ? "自动 · " : "手动 · "}${video.currentPlugin.name} / ${road.name}',
          detail:
              automaticSourceError ??
              (video.activeRouteLabel != null && (video.loading || !sameGroup)
                  ? '当前播放：${video.activeRouteLabel}'
                  : null),
          lineCount: count == 0 && road != null ? video.roadList.length : count,
          onShowLines: () => showAnimeLines(context),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> showAnimeLines(BuildContext pageContext) async {
    sourceSession.updateWork(item);
    final group = selectedGroup;
    if (group == null) return;
    // 通过历史直接进入时先纳入现有目录，避免已播放的线路在弹层中消失。
    if (hasPlayback &&
        !video.isOfflineMode &&
        playbackSdkId(video.currentPlugin) == group.id) {
      sourceSession.seed(
        PlaybackCandidate(
          plugin: video.currentPlugin,
          item: SearchItem(name: video.title, src: video.src),
          roads: video.roadList.toList(),
          matched: true,
        ),
      );
    }
    for (final plugin in group.plugins) {
      unawaited(sourceSession.prepare(plugin));
    }
    try {
      await showModalBottomSheet<void>(
        context: pageContext,
        isScrollControlled: true,
        showDragHandle: false,
        useSafeArea: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(pageContext)
            ? AnimationStyle.noAnimation
            : null,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, update) {
            refreshSourceSheet = () {
              if (context.mounted) update(() {});
            };
            return PlaybackLineSheet(
              sdkName: group.name,
              onClose: () => Navigator.of(sheetContext).pop(),
              automaticOption: SdkLineOption(
                title: '自动选择',
                subtitle: '仅在 ${group.name} 内优选',
                automatic: true,
                selected: !hasPlayback || video.automaticSource,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(playAutomatically());
                },
              ),
              children: [
                for (final plugin in group.plugins)
                  animeProviderSection(plugin, pageContext, sheetContext),
              ],
            );
          },
        ),
      );
    } finally {
      refreshSourceSheet = null;
    }
  }

  Widget animeProviderSection(
    Plugin plugin,
    BuildContext pageContext,
    BuildContext sheetContext,
  ) {
    final candidates =
        sourceSession.entries[plugin.providerId] ?? <PlaybackCandidate>[];
    final ready = sourceSession.status[plugin.providerId] == 'ready';
    final loading = sourceSession.loading.contains(plugin.providerId);
    final roads = [for (final candidate in candidates) ...candidate.roads];
    final episodeCounts = roads.map((r) => r.identifier.length).toSet();
    final status = sourceSession.status[plugin.providerId] ?? '';
    final failed = status.startsWith('目录获取失败');
    final theme = Theme.of(pageContext);
    final colors = theme.colorScheme;
    final cardShape = theme.cardTheme.shape ?? const RoundedRectangleBorder();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        // 自定义 ShapeBorder 未必支持改描边，保留其形状实现。
        shape: cardShape is OutlinedBorder
            ? cardShape.copyWith(side: BorderSide(color: colors.outline))
            : cardShape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plugin.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (loading || !ready || roads.isEmpty)
                      Text(
                        loading
                            ? '获取线路…'
                            : failed
                            ? '线路获取失败'
                            : ready
                            ? '该来源暂无线路'
                            : status.contains('歧义')
                            ? '多个同名作品'
                            : '未匹配作品',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: failed && !loading
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LoadingIndicator(size: 16),
                )
              else if (!ready) ...[
                if (!failed)
                  TextButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(chooseSource(pageContext));
                    },
                    child: const Text('手动确认'),
                  ),
                IconButton(
                  tooltip: '重试 ${plugin.name}',
                  onPressed: () => sourceSession.prepare(plugin, retry: true),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ] else if (roads.isNotEmpty)
                Text(
                  '${roads.length} 条${episodeCounts.length == 1 ? " · ${episodeCounts.single} 集" : ""}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (ready && !loading && roads.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                for (final candidate in candidates)
                  for (var r = 0; r < candidate.roads.length; r++)
                    PlaybackRouteChip(
                      name: candidate.roads[r].name,
                      episodeCount: candidate.roads[r].identifier.length,
                      current:
                          video.activeProviderId == plugin.providerId &&
                          video.activeContentRef == candidate.item.src &&
                          video.activeRoadId ==
                              (candidate.roads[r].id.isEmpty
                                  ? '$r'
                                  : candidate.roads[r].id),
                      selected:
                          hasPlayback &&
                          !video.automaticSource &&
                          video.currentPlugin.providerId == plugin.providerId &&
                          video.src == candidate.item.src &&
                          video.selectedEpisode.road == r,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(selectAnimeLine(pageContext, candidate, r));
                      },
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> selectAnimeLine(
    BuildContext context,
    PlaybackCandidate candidate,
    int road,
  ) async {
    final generation = ++manualLineGeneration;
    automaticSourceCancel?.cancel('manual line selected');
    automaticSourceCancel = null;
    final args = candidate.args(item);
    final previousTitle = hasPlayback
        ? video.resolveEpisode(video.selectedEpisode)?.displayTitle
        : null;
    final number = previousTitle == null
        ? selectedCatalogEpisode?.episode.toInt()
        : regularEpisodeNumber(previousTitle);
    final names = candidate.roads[road].identifier;
    final matches = [
      for (var i = 0; i < names.length; i++)
        if (number != null
            ? regularEpisodeNumber(names[i]) == number
            : previousTitle != null &&
                  normalizeWorkTitle(names[i]) ==
                      normalizeWorkTitle(previousTitle))
          i + 1,
    ];
    VideoEpisodeSelection? target = matches.length == 1
        ? VideoEpisodeSelection(episode: matches.single, road: road)
        : null;
    if (!hasPlayback && number == null) {
      final resume = verifiedResume(args, widget.historyController.histories);
      if (resume?.selection.road == road) target = resume?.selection;
    }
    target ??= await showModernPlayerSheet<VideoEpisodeSelection>(
      context,
      PlayerEpisodesSheet(
        roads: args.roads,
        selected: VideoEpisodeSelection(episode: 1, road: road),
        sourceName: candidate.plugin.name,
        confirmSource: true,
      ),
    );
    if (!mounted || target == null || generation != manualLineGeneration)
      return;
    final sameEpisode =
        previousTitle != null &&
        (number != null
            ? regularEpisodeNumber(
                    args.roads[target.road].identifier[target.episode - 1],
                  ) ==
                  number
            : normalizeWorkTitle(
                    args.roads[target.road].identifier[target.episode - 1],
                  ) ==
                  normalizeWorkTitle(previousTitle));
    setState(() {
      choosingSource = true;
      automaticSourceError = null;
    });
    try {
      await playbackKey.currentState?.startSource(
        args,
        target,
        onReady: playbackReady,
        offset: sameEpisode
            ? widget.playerController.playback.playerPosition.inSeconds
            : 0,
        expectedDuration: sameEpisode
            ? widget.playerController.playback.playerDuration
            : null,
      );
    } finally {
      if (mounted && generation == manualLineGeneration) {
        setState(() => choosingSource = false);
      }
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
    if (!hasPlayback) {
      if (catalogEpisodes.isEmpty) {
        await loadEpisodeCatalog();
        if (!mounted || !context.mounted || catalogEpisodes.isEmpty) return;
      }
      final episode = await showModernPlayerSheet<EpisodeInfo>(
        context,
        PlayerCatalogEpisodesSheet(
          episodes: catalogEpisodes,
          selectedId: selectedCatalogEpisode?.id,
        ),
      );
      if (mounted && episode != null) await playAutomatically(episode: episode);
      return;
    }
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
        showRoadSelector: false,
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
        // 由播放器挂载后自行初始化，避免主题本地化延迟挂载时丢失父级回调。
        args: widget.args,
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
                  Semantics(
                    container: true,
                    label: choosingSource
                        ? '正在自动匹配来源'
                        : resumeCandidate != null
                        ? '继续观看'
                        : '开始观看，自动选择来源',
                    button: true,
                    enabled: !choosingSource,
                    excludeSemantics: true,
                    onTap: choosingSource ? null : () => resume(context),
                    child: ShadButton(
                      onPressed: choosingSource ? null : () => resume(context),
                      width: 52,
                      height: 52,
                      padding: EdgeInsets.zero,
                      decoration: ShadDecoration(
                        border: ShadBorder(radius: BorderRadius.circular(26)),
                      ),
                      child: choosingSource
                          ? const LoadingIndicator(
                              size: 26,
                              color: Color(0xff182142),
                            )
                          : const Icon(LucideIcons.play, size: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    choosingSource
                        ? '正在自动匹配来源'
                        : resumeCandidate != null
                        ? '继续观看 · ${resumeCandidate!.lastWatchEpisodeName}'
                        : '开始观看 · 自动选源',
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
            if (MediaQuery.sizeOf(context).width >
                MediaQuery.sizeOf(context).height)
              Positioned(
                right: 4,
                bottom: 4,
                child: IconButton(
                  key: const ValueKey('modern-player-open-details'),
                  tooltip: '详情与选集',
                  color: Colors.white,
                  onPressed: () => playbackKey.currentState?.toggleDetails(),
                  icon: const Icon(Icons.view_sidebar_outlined, size: 22),
                ),
              ),
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
                      canonicalEpisode: hasPlayback
                          ? null
                          : selectedCatalogEpisode,
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
        ? catalogEpisodes.length
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
        sourceControls(context),
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
                '共 $count 集 · 全部 ›',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        if (hasPlayback) ...[
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
                  onPressed: () => playbackKey.currentState?.retryPlayback(),
                  child: const Text('重试'),
                ),
                TextButton(
                  onPressed: () => chooseSource(context),
                  child: const Text('换源'),
                ),
              ],
            ),
        ] else ...[
          if (episodesLoading && catalogEpisodes.isEmpty)
            const SkeletonEpisodes(),
          if (catalogEpisodes.isNotEmpty)
            SizedBox(
              height: math.max(56, MediaQuery.textScalerOf(context).scale(42)),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: math.min(8, catalogEpisodes.length),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final episode = catalogEpisodes[i];
                  return PlayerEpisodeButton(
                    title: '第${episode.episode.toInt()}集',
                    selected: episode.id == selectedCatalogEpisode?.id,
                    onTap: () => playAutomatically(episode: episode),
                  );
                },
              ),
            ),
          if (choosingSource) const LinearProgressIndicator(),
          TextButton.icon(
            onPressed: choosingSource ? null : () => playAutomatically(),
            icon: const Icon(LucideIcons.play, size: 16),
            label: const Text('自动播放'),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        const Text(
          '关联作品',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (relationsLoading && info.relationList.isEmpty)
          const SkeletonPosters(count: 3)
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
