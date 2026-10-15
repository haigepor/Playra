import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/services/source/source_playback_service.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';
import 'package:kazumi/services/source/source_candidates.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';
import 'package:kazumi/services/source/source_policy.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/modules/comments/comment_response.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/episode_url.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

class VideoEpisodeSelection {
  const VideoEpisodeSelection({required this.episode, required this.road});

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

/// 播放控制界面需要的来源资料，不赋予 Bangumi 收藏/历史身份。
class SourcePlayerContext {
  const SourcePlayerContext({
    required this.identity,
    required this.title,
    required this.sourceName,
    this.artworkUrl,
    this.referer = '',
  });
  final String identity, title, sourceName, referer;
  final String? artworkUrl;
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;
  SourcePlayerContext? sourceContext;
  bool get hasBangumiContext => sourceContext == null;
  String get playbackWorkTitle =>
      sourceContext?.title ??
      (bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name);
  String? get playbackArtwork =>
      sourceContext?.artworkUrl ??
      (hasBangumiContext ? bangumiItem.images['large'] : null);
  String get playbackSourceName =>
      sourceContext?.sourceName ??
      (isOfflineMode ? offlinePluginName : currentPlugin.name);
  String get playbackReferer =>
      sourceContext?.referer ?? (isOfflineMode ? '' : currentPlugin.referer);
  String get playbackMediaId => sourceContext?.identity ?? '${bangumiItem.id}';

  void bindSourcePlayer(
    SourcePlayerContext source,
    List<Road> roads,
    VideoEpisodeSelection selection,
  ) {
    runInAction(() {
      sourceContext = source;
      title = source.title;
      src = source.identity;
      isOfflineMode = false;
      _playbackHistoryIdentity = null;
      roadList = ObservableList.of(roads);
      selectedEpisode = selection;
      playingEpisode = selection;
      _loading = false;
      _errorMessage = null;
    });
  }

  EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();

  @observable
  var episodeCommentsList = ObservableList<EpisodeCommentItem>();

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode = const VideoEpisodeSelection(
    episode: 1,
    road: 0,
  );

  @observable
  VideoEpisodeSelection? playingEpisode;

  @observable
  int commentsEpisode = 1;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selection);
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  final fullscreen = VideoFullscreenController(
    applyFullscreen: DisplayModeService.applyVideoFullscreen,
  );

  bool get isFullscreen => fullscreen.isFullscreen;

  @observable
  bool isCommentsAscending = false;

  // Playback, automatic danmaku loading, and comment loading have separate
  // owners. Manual danmaku selection can cancel auto danmaku without touching
  // playback; comment refreshes never cancel playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();
  final AsyncSessionOwner _commentSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  String _offlinePluginName = '';

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  SourcePlaybackService? _videoSourceService;
  bool automaticSource = false;
  String? activeProviderId, activeContentRef, activeRoadId, activeRouteLabel;
  RuleCancelToken? _pendingSourceCancel;
  int _sourceSwitchVersion = 0;
  RuleCancelToken? _recoveryCancel;
  int _mediaRecoveries = 0;
  String? _mediaFailure;
  String _lastFailureCode = '';
  Timer? _firstFrameTimer;
  int _attemptVersion = 0;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    sourceContext = null;
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        currentPlugin = args.plugin;
        automaticSource = args.automatic;
        title = args.title;
        src = args.src;
        roadList.clear();
        roadList.addAll(args.roads);
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
        );
    }
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    title = bangumiItem.nameCn.isNotEmpty
        ? bangumiItem.nameCn
        : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selected);
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    KazumiLogger().i(
      'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})',
    );
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad.addAll(
      snapshot.displayRoadToOriginalRoad,
    );
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad.addAll(
      snapshot.originalRoadToDisplayRoad,
    );
  }

  String get offlinePluginName => _offlinePluginName;

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      hasBangumiContext ? _playbackHistoryIdentity : null;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex:
          downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    return isOfflineMode
        ? _resolveOfflineEpisode(selection.episode, road: selection.road)
        : _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  int commentEpisodeForSelection(VideoEpisodeSelection selection) {
    final resolvedEpisode = resolveEpisode(selection);
    return resolvedEpisode?.danmakuEpisodeNumber ?? selection.episode;
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    final targetCommentsEpisode = commentEpisodeForSelection(selection);
    selectedEpisode = selection;
    playingEpisode = null;
    // The comments sheet only re-queries when [commentsEpisode] changes, so
    // resetting comment state here without changing it would blank the sheet
    // permanently.
    if (targetCommentsEpisode != commentsEpisode) {
      commentsEpisode = targetCommentsEpisode;
      _resetEpisodeComments();
    }
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
    commentsEpisode = commentEpisodeForSelection(selectedEpisode);
  }

  @action
  void _finishLoading() {
    _loading = false;
    _errorMessage = null;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
    bool fromRecovery = false,
    Duration? expectedDuration,
    VideoSource? preparedSource,
  }) async {
    _sourceSwitchVersion++;
    _pendingSourceCancel?.cancel('episode changed');
    _pendingSourceCancel = null;
    // 明确换线视为手动锁定；同线路的下一集保留现有自动/手动模式。
    if (!fromRecovery && currentRoad != selectedEpisode.road)
      automaticSource = false;
    final originalDuration =
        expectedDuration ?? playerController.playback.playerDuration;
    var durationGuard = expectedDuration;
    if (!fromRecovery) _mediaRecoveries = 0;
    _recoveryCancel?.cancel('replaced');
    _firstFrameTimer?.cancel();
    final cancel = RuleCancelToken();
    _recoveryCancel = cancel;
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();
    playerController.playback.onMediaError = null;

    await playerController.stop();
    if (session.isStale) {
      return;
    }
    activeProviderId = null;
    activeContentRef = null;
    activeRoadId = null;
    activeRouteLabel = null;

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    final resolvedEpisode = _resolveOnlineEpisode(episode, road: currentRoad);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
        'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode',
      );
      _failLoading('集数解析失败');
      return;
    }

    _applyResolvedSelection(resolvedEpisode);
    _setOnlineHistoryIdentity(resolvedEpisode);

    KazumiLogger().i(
      'VideoPageController: changed to ${resolvedEpisode.displayTitle}',
    );
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolvedEpisode.pageUrl,
    );

    final budget = Stopwatch()..start();
    final maxTime = Duration(seconds: kIsWeb ? 180 : 120);
    var ref = resolvedEpisode;
    var url = urlItem;
    var attempts = 0;
    final tried = <String>{};
    List<PlaybackCandidate>? alternatives;
    var discovered = false;
    while (session.isActive &&
        !cancel.isCancelled &&
        budget.elapsed < maxTime &&
        attempts < 3) {
      attempts++;
      final key = '${currentPlugin.providerId}|${ref.pageUrl}';
      tried.add(key);
      for (var retry = 0; retry < (automaticSource ? 2 : 1); retry++) {
        _loading = true;
        _errorMessage = null;
        final success = await _resolveWithVideoSourceService(
          url,
          offset,
          resolvedEpisode: ref,
          session: session,
          playerController: playerController,
          budgetRemaining: maxTime - budget.elapsed,
          expectedDuration: durationGuard,
          preparedSource: preparedSource,
        );
        preparedSource = null;
        if (success || session.isStale || cancel.isCancelled) return;
        if (!const [
              'TIMEOUT',
              'MEDIA_ERROR',
              'SOURCE_ERROR',
              'EXPIRED',
            ].contains(_lastFailureCode) ||
            budget.elapsed >= maxTime) {
          break;
        }
      }
      if (!automaticSource || session.isStale || budget.elapsed >= maxTime) {
        break;
      }
      final number = regularEpisodeNumber(resolvedEpisode.displayTitle);
      if (number == null) break;
      final plugins = samePlaybackSdk(
        currentPlugin,
        inject<PluginsController>().pluginList,
      );
      alternatives ??= SourceCandidates.shared.cached(bangumiItem, plugins);
      final hasAlternative = alternatives.any(
        (candidate) =>
            candidate.matched &&
            !SourcePolicy.shared.coolingDown(
              candidate.plugin.providerId,
              candidate.plugin.version,
            ) &&
            alternatives!
                    .where(
                      (c) => c.plugin.providerId == candidate.plugin.providerId,
                    )
                    .length ==
                1 &&
            candidate
                .episodeMatches(number)
                .any(
                  (match) => !tried.contains(
                    '${candidate.plugin.providerId}|${candidate.roads[match.road].data[match.episode - 1]}',
                  ),
                ),
      );
      // 已缓存的来源可能只有当前来源；预算内允许补检索一次。
      if (!hasAlternative && !discovered) {
        discovered = true;
        try {
          alternatives = await SourceCandidates.shared
              .discover(bangumiItem, plugins, cancel)
              .timeout(
                maxTime - budget.elapsed,
                onTimeout: () {
                  cancel.cancel('deadline');
                  return [];
                },
              );
        } catch (_) {
          alternatives = [];
        }
      }
      if (session.isStale) return;
      if (cancel.isCancelled) {
        _failLoading('自动检索预算已用尽，请手动重试或换源');
        return;
      }
      PlaybackCandidate? next;
      ({int road, int episode})? target;
      for (final candidate in alternatives) {
        if (!candidate.matched ||
            SourcePolicy.shared.coolingDown(
              candidate.plugin.providerId,
              candidate.plugin.version,
            ) ||
            alternatives
                    .where(
                      (c) => c.plugin.providerId == candidate.plugin.providerId,
                    )
                    .length !=
                1) {
          continue;
        }
        for (final match in candidate.episodeMatches(number)) {
          if (tried.contains(
            '${candidate.plugin.providerId}|${candidate.roads[match.road].data[match.episode - 1]}',
          )) {
            continue;
          }
          next = candidate;
          target = match;
          break;
        }
        if (next != null) break;
      }
      if (next == null || target == null) break;
      await playerController.stop();
      if (session.isStale) return;
      applyPlaybackArgs(next.args(bangumiItem, automatic: true));
      durationGuard = originalDuration;
      ref = _resolveOnlineEpisode(target.episode, road: target.road)!;
      _applyResolvedSelection(ref);
      _setOnlineHistoryIdentity(ref);
      url = normalizeEpisodeUrl(currentPlugin.baseUrl, ref.pageUrl);
    }
    if (session.isActive) {
      _failLoading(
        '${_errorMessage ?? '未找到可播放的同集来源'}${automaticSource ? '，自动尝试已结束，可手动重试或换源' : ''}',
      );
    }
  }

  /// 新地址准备期间保留旧媒体与历史身份，确认可用后才停止并提交新上下文。
  Future<void> switchOnlineSource(
    OnlineVideoPlaybackArgs args, {
    required VideoEpisodeSelection selection,
    required PlayerController playerController,
    int offset = 0,
    Duration? expectedDuration,
    void Function()? onReady,
  }) async {
    final switchVersion = ++_sourceSwitchVersion;
    _pendingSourceCancel?.cancel('replaced');
    final pending = _pendingSourceCancel = RuleCancelToken();
    final road = selection.road >= 0 && selection.road < args.roads.length
        ? args.roads[selection.road]
        : null;
    if (road == null ||
        selection.episode < 1 ||
        selection.episode > road.data.length) {
      pending.cancel('invalid selection');
      _pendingSourceCancel = null;
      return;
    }
    final preparer = SourcePlaybackService();
    VideoSource? prepared;
    try {
      if (playerController.playback.mediaPlayer != null) {
        prepared = await preparer.resolve(
          normalizeEpisodeUrl(
            args.plugin.baseUrl,
            road.data[selection.episode - 1],
          ),
          useLegacyParser: args.plugin.useLegacyParser,
          offset: offset,
          definition: SourceDefinition.fromJson(args.plugin.toJson()),
          context: SourceContext(
            providerId: args.plugin.providerId,
            cancelToken: pending,
            timeout: const Duration(seconds: 55),
          ),
        );
      }
      if (pending.isCancelled) return;
    } catch (_) {
      if (pending.isCancelled) return;
      if (!args.automatic) {
        _errorMessage = '新线路解析失败，请重试或选择其他线路';
        if (identical(_pendingSourceCancel, pending))
          _pendingSourceCancel = null;
        return;
      }
      // 自动模式交给统一恢复循环，在同一 SDK 内继续尝试同集。
    } finally {
      preparer.cancel();
    }
    if (pending.isCancelled || switchVersion != _sourceSwitchVersion) return;
    _pendingSourceCancel = null;
    final session = _playbackSessions.begin();
    _recoveryCancel?.cancel('replaced');
    _firstFrameTimer?.cancel();
    playerController.playback.onMediaError = null;
    _danmakuSessions.cancel();
    _resetEpisodeComments();
    _videoSourceService?.cancel();
    _loading = true;
    _errorMessage = null;
    await playerController.stop();
    if (session.isStale || switchVersion != _sourceSwitchVersion) return;
    isOfflineMode = false;
    _playbackHistoryIdentity = null;
    applyPlaybackArgs(args);
    resetEpisodeState(episode: selection.episode, road: selection.road);
    onReady?.call();
    await changeEpisode(
      selection.episode,
      currentRoad: selection.road,
      offset: offset,
      expectedDuration: expectedDuration,
      playerController: playerController,
      preparedSource: prepared,
    );
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode = _resolveOfflineEpisode(
      selection.episode,
      road: selection.road,
    );
    if (resolvedEpisode == null) {
      KazumiLogger().e(
        'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}',
      );
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset = offset > 0
        ? offset
        : getHistoryOffsetFor(_playbackHistoryIdentity!);

    KazumiLogger().i(
      'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath',
    );

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName: bangumiItem.nameCn.isNotEmpty
          ? bangumiItem.nameCn
          : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session,
  ) async {
    final danmakuSession = _danmakuSessions.begin();
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await playerController.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          final bool enableDanmaku = GStorage.getSetting(
            SettingsKeys.danmakuEnabledByDefault,
          );
          playerController.danmaku.applyDanmakuLoad(
            result,
            enableDanmaku: enableDanmaku,
          );
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          if (result.isFailed) {
            KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      KazumiLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  /// 外壳切换版本时路由作用域仍在；取消请求但保持控制器可再次使用。
  void cancelPendingPlayback() {
    _sourceSwitchVersion++;
    _pendingSourceCancel?.cancel('playback disposed');
    _pendingSourceCancel = null;
    _firstFrameTimer?.cancel();
    _recoveryCancel?.cancel();
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _videoSourceService?.cancel();
  }

  String? _getLocalVideoPath(
    int bangumiId,
    String pluginName,
    int episodeNumber,
  ) {
    final episode = downloadRepository.getEpisode(
      bangumiId,
      pluginName,
      episodeNumber,
    );
    return downloadManager.getLocalVideoPath(episode);
  }

  Future<bool> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
    Duration budgetRemaining = const Duration(seconds: 120),
    Duration? expectedDuration,
    VideoSource? preparedSource,
  }) async {
    _videoSourceService ??= SourcePlaybackService();

    await _logSubscription?.cancel();
    if (session.isStale) return false;
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    final measured = Stopwatch()..start();
    final attemptVersion = ++_attemptVersion;
    _firstFrameTimer?.cancel();
    final attemptedPlugin = currentPlugin;
    var firstFrameTimedOut = false;
    bool currentAttempt() =>
        session.isActive && attemptVersion == _attemptVersion;
    void markActiveRoute() {
      if (session.isStale || attemptVersion != _attemptVersion) return;
      activeProviderId = currentPlugin.providerId;
      activeContentRef = src;
      final road = roadList[resolvedEpisode.roadIndex];
      activeRoadId = road.id.isEmpty ? '${resolvedEpisode.roadIndex}' : road.id;
      activeRouteLabel = '${currentPlugin.name} / ${road.name}';
      playingEpisode = VideoEpisodeSelection(
        episode: resolvedEpisode.listIndex,
        road: resolvedEpisode.roadIndex,
      );
    }

    try {
      final source =
          preparedSource ??
          await _videoSourceService!.resolve(
            url,
            useLegacyParser: currentPlugin.useLegacyParser,
            offset: offset,
            definition: SourceDefinition.fromJson(currentPlugin.toJson()),
            context: SourceContext(
              providerId: currentPlugin.providerId,
              cancelToken: _recoveryCancel,
              sessionId: 'playback',
              timeout: budgetRemaining < const Duration(seconds: 55)
                  ? budgetRemaining
                  : const Duration(seconds: 55),
            ),
          );

      if (session.isStale) {
        return false;
      }
      if (source.expiresAt != null &&
          !source.expiresAt!.isAfter(DateTime.now())) {
        throw const SourceException('EXPIRED', '视频地址已过期，请重新解析');
      }
      KazumiLogger().i(
        'VideoPageController: resolved video for ${currentPlugin.name}',
      );

      final bool forceAdBlocker = GStorage.getSetting(
        SettingsKeys.forceAdBlocker,
      );

      final params = PlaybackInitParams(
        videoUrl: source.url,
        // 跨源先从头打开，再根据真实时长核对能否恢复进度。
        offset: expectedDuration == null ? source.offset : 0,
        isLocalPlayback: false,
        videoSourceFormat: source.format,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          if (source.inheritHeaders)
            'user-agent': currentPlugin.userAgent.isEmpty
                ? getRandomUA()
                : currentPlugin.userAgent,
          if (source.inheritHeaders && currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
          ...source.headers,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: source.inheritHeaders ? currentPlugin.referer : '',
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      var progressRestored = false;
      Future<void> restoreMatchingProgress() async {
        if (progressRestored || !currentAttempt()) return;
        progressRestored = true;
        if (expectedDuration == null || source.offset <= 0) return;
        final duration = playerController.playback.playerDuration;
        final difference = (duration - expectedDuration).inSeconds.abs();
        final tolerance = (expectedDuration.inSeconds * .1).clamp(5, 30);
        if (expectedDuration > Duration.zero &&
            duration > Duration.zero &&
            difference <= tolerance &&
            source.offset < duration.inSeconds) {
          await playerController.seek(Duration(seconds: source.offset));
        }
      }

      _mediaFailure = null;
      playerController.playback.onMediaError = (message) {
        if (session.isStale || attemptVersion != _attemptVersion) return;
        // 真正的媒体错误不能被后续首帧回调当成“超时恢复”清除。
        firstFrameTimedOut = false;
        _mediaFailure = message;
        if (!_loading) {
          SourcePolicy.shared.record(
            attemptedPlugin.providerId,
            attemptedPlugin.version,
            success: false,
            elapsedMs: measured.elapsedMilliseconds,
          );
          unawaited(retryPlayback(playerController, mediaError: true));
        }
      };
      final remaining = budgetRemaining - measured.elapsed;
      if (remaining <= Duration.zero) {
        throw const SourceException('TIMEOUT', '播放启动预算已用尽');
      }
      final initialized = await playerController
          .init(params)
          .timeout(
            remaining,
            onTimeout: () {
              // 旧初始化的超时回调不能停止用户随后创建的播放器。
              if (session.isActive && attemptVersion == _attemptVersion) {
                unawaited(playerController.stop());
              }
              throw const SourceException('TIMEOUT', '播放器打开超时');
            },
          );
      if (initialized && session.isActive) {
        final firstFrame = playerController
            .playback
            .videoController
            ?.waitUntilFirstFrameRendered;
        var rendered = firstFrame == null;
        if (rendered) markActiveRoute();
        var waited = Duration.zero;
        var hasPlayed = false;
        final resolveMs = measured.elapsedMilliseconds;
        // 与 SDK 影视页一致；尾置索引 MP4 需要额外 Range 请求，不能在 15 秒误判。
        const frameLimit = Duration(seconds: 25);
        if (firstFrame != null) {
          final timer = Timer.periodic(const Duration(milliseconds: 200), (
            timer,
          ) {
            if (session.isStale ||
                attemptVersion != _attemptVersion ||
                rendered) {
              timer.cancel();
              return;
            }
            final playing =
                playerController.playback.mediaPlayer?.state.playing == true;
            hasPlayed = hasPlayed || playing;
            final active =
                WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed;
            if (active &&
                !playerController.playback.startupSuspended &&
                (playing ||
                    (!kIsWeb &&
                        !hasPlayed &&
                        playerController.playback.autoPlay))) {
              waited += const Duration(milliseconds: 200);
            }
            if (waited >= frameLimit) {
              timer.cancel();
              firstFrameTimedOut = true;
              _mediaFailure = '首帧等待超时';
              if (!_loading) {
                SourcePolicy.shared.record(
                  attemptedPlugin.providerId,
                  attemptedPlugin.version,
                  success: false,
                  elapsedMs: resolveMs + waited.inMilliseconds,
                );
                unawaited(retryPlayback(playerController, mediaError: true));
              }
            }
          });
          _firstFrameTimer = timer;
          unawaited(
            firstFrame
                .then<void>((_) async {
                  rendered = true;
                  timer.cancel();
                  if (currentAttempt() &&
                      (_mediaFailure == null || firstFrameTimedOut)) {
                    // 超时不是播放器终止：仅当前媒体迟到出画时撤掉过期错误。
                    // 新选集/新线路已更换 attempt 或 session，旧帧没有恢复权限。
                    // 主等待仍在运行时交给下方统一完成，避免同时恢复进度/加载弹幕。
                    final recovered = firstFrameTimedOut && !_loading;
                    firstFrameTimedOut = false;
                    _mediaFailure = null;
                    if (recovered) {
                      await restoreMatchingProgress();
                      if (!currentAttempt() || _mediaFailure != null) return;
                      _lastFailureCode = '';
                      markActiveRoute();
                      _finishLoading();
                      unawaited(
                        _loadPlaybackDanmaku(playerController, params, session),
                      );
                    } else {
                      markActiveRoute();
                    }
                    SourcePolicy.shared.record(
                      attemptedPlugin.providerId,
                      attemptedPlugin.version,
                      success: true,
                      elapsedMs: resolveMs + waited.inMilliseconds,
                    );
                  }
                })
                .catchError((Object _) {}),
          );
        }
        while (!rendered &&
            _mediaFailure == null &&
            session.isActive &&
            measured.elapsed < budgetRemaining) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          // 暂停和后台先退出前台等待；独立监视器在恢复播放后继续计算有效等待时间。
          if (!playerController.playback.autoPlay ||
              playerController.playback.startupSuspended ||
              (kIsWeb &&
                  playerController.playback.mediaPlayer?.state.playing !=
                      true) ||
              (hasPlayed &&
                  playerController.playback.mediaPlayer?.state.playing ==
                      false) ||
              (WidgetsBinding.instance.lifecycleState != null &&
                  WidgetsBinding.instance.lifecycleState !=
                      AppLifecycleState.resumed)) {
            break;
          }
        }
        if (session.isStale) return false;
        if (_mediaFailure != null ||
            (!rendered && measured.elapsed >= budgetRemaining)) {
          _firstFrameTimer?.cancel();
          throw const SourceException('MEDIA_ERROR', '视频加载失败或首帧等待超时');
        }
      }
      if (session.isActive && initialized) {
        await restoreMatchingProgress();
        if (!currentAttempt()) return false;
        if (_mediaFailure != null) {
          throw const SourceException('MEDIA_ERROR', '恢复播放进度时媒体加载失败');
        }
        _finishLoading();
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
        return true;
      } else if (session.isActive) {
        throw const SourceException('MEDIA_ERROR', '播放器初始化失败，请重试或换源');
      }
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return false;
      }
      _failLoading('视频解析超时，请重试');
      _lastFailureCode = 'TIMEOUT';
    } on VideoSourceCancelledException {
      KazumiLogger().i('VideoPageController: video URL resolution cancelled');
      return false;
    } catch (e) {
      if (session.isStale) {
        return false;
      }
      if (e is SourceException && e.code == 'MEDIA_ERROR') {
        _failLoading(
          firstFrameTimedOut ? '视频首帧等待超时，请重试或换源' : '已取得视频地址，但媒体加载失败，请重试或换源',
        );
      } else if (e is SourceException && e.code == 'TIMEOUT') {
        _failLoading('视频加载超时，请重试或换源');
      } else {
        _failLoading('视频解析失败：${e.toString()}');
      }
      _lastFailureCode = e is SourceException ? e.code : 'SOURCE_ERROR';
    }
    _firstFrameTimer?.cancel();
    if (session.isActive &&
        !const ['CANCELLED', 'CHALLENGE_REQUIRED'].contains(_lastFailureCode)) {
      SourcePolicy.shared.record(
        attemptedPlugin.providerId,
        attemptedPlugin.version,
        success: false,
        elapsedMs: measured.elapsedMilliseconds,
      );
    }
    return false;
  }

  Future<void> retryPlayback(
    PlayerController playerController, {
    bool mediaError = false,
  }) async {
    // 新选线正在准备时，旧媒体错误不能发起恢复并取消用户的新选择。
    if (_pendingSourceCancel != null && !_pendingSourceCancel!.isCancelled)
      return;
    if (isOfflineMode || _loading || (mediaError && ++_mediaRecoveries > 2)) {
      if (mediaError && _mediaRecoveries > 2) _failLoading('播放持续失败，请手动重试或换源');
      return;
    }
    if (mediaError && !automaticSource) {
      _failLoading('视频播放失败，请重试或换源');
      return;
    }
    final target = selectedEpisode;
    final position = playerController.playback.playerPosition.inSeconds;
    await changeEpisode(
      target.episode,
      currentRoad: target.road,
      offset: position,
      playerController: playerController,
      fromRecovery: mediaError,
    );
  }

  void _resetEpisodeComments() {
    _commentSessions.cancel();
    episodeInfo.reset();
    episodeCommentsList.clear();
  }

  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async {
    final session = _commentSessions.begin();
    final EpisodeInfo latestEpisodeInfo;
    try {
      latestEpisodeInfo = await BangumiApi.getBangumiEpisodeByID(id, episode);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final EpisodeCommentResponse value;
    try {
      value = await BangumiApi.getBangumiCommentsByEpisodeID(
        latestEpisodeInfo.id,
      );
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final commentsList = value.commentList;
    if (!isCommentsAscending) {
      commentsList.sort(
        (a, b) => b.comment.createdAt.compareTo(a.comment.createdAt),
      );
    } else {
      commentsList.sort(
        (a, b) => a.comment.createdAt.compareTo(b.comment.createdAt),
      );
    }
    _applyEpisodeComments(episode, latestEpisodeInfo, commentsList);
    KazumiLogger().i(
      'VideoPageController: loaded comments list length ${episodeCommentsList.length}',
    );
    return true;
  }

  @action
  void _applyEpisodeComments(
    int episode,
    EpisodeInfo info,
    List<EpisodeCommentItem> comments,
  ) {
    commentsEpisode = episode;
    episodeInfo = info;
    episodeCommentsList = ObservableList.of(comments);
  }

  @action
  void toggleSortOrder() {
    isCommentsAscending = !isCommentsAscending;
    episodeCommentsList.sort(
      (a, b) => isCommentsAscending
          ? a.comment.createdAt.compareTo(b.comment.createdAt)
          : b.comment.createdAt.compareTo(a.comment.createdAt),
    );
  }

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    _firstFrameTimer?.cancel();
    _recoveryCancel?.cancel();
    unawaited(fullscreen.close());
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(
      Road(
        name: originalRoad >= 0
            ? '播放列表${originalRoad + 1}'
            : '播放列表${displayRoad + 1}',
        data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
        identifier: roadEpisodes
            .map(
              (e) => e.episodeName.isNotEmpty
                  ? e.episodeName
                  : '第${e.episodeNumber}集',
            )
            .toList(),
      ),
    );
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber: parsedEpisodeNumber > 0
          ? parsedEpisodeNumber
          : listIndex,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
         sortNumber: episodeNumber,
         historyEpisodeNumber: episodeNumber,
         danmakuEpisodeNumber: episodeNumber,
       );
}
