import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/player_buffering_overlay.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/player/player_option_sheet.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/presentation/widgets/playra_segmented_tab_bar.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/player/cast_eligibility.dart';
import 'package:kazumi/services/player/remote.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

/// Map source failures to safe, actionable messages without exposing signed URLs
/// or raw server responses in the player UI.
@visibleForTesting
String playbackSourceErrorMessage(Object error) {
  if (error is! MediaSourceException) return '视频加载失败';
  return switch (error.kind) {
    MediaSourceErrorKind.network => '视频连接失败',
    MediaSourceErrorKind.protocol => '视频源响应异常',
    MediaSourceErrorKind.authentication => '请先登录后播放',
    MediaSourceErrorKind.vipRequired => '该剧集需要会员',
    MediaSourceErrorKind.adRequired => '需要完成观看条件后播放',
    MediaSourceErrorKind.expired => '播放地址已失效，请重试',
    MediaSourceErrorKind.notFound => '未找到可播放的视频',
    MediaSourceErrorKind.unsupported => '当前视频暂不支持播放',
    MediaSourceErrorKind.cancelled => '播放已取消',
    MediaSourceErrorKind.unknown => '视频加载失败',
  };
}

/// Player page bound to a [MediaSource].
///
/// The play URL is resolved on every episode switch: CliCli URLs expire in
/// ~20 seconds, so they can never be kept in the session.
class SourcePlayerPage extends StatefulWidget {
  const SourcePlayerPage({super.key, required this.request, this.demoUrl});
  final String? demoUrl;

  final PlaybackRequest request;

  @override
  State<SourcePlayerPage> createState() => _SourcePlayerPageState();
}

class _SourcePlayerPageState extends State<SourcePlayerPage>
    with TickerProviderStateMixin {
  late final ShaderAssetService _shaders;
  late final AudioController _audio;
  late final PlayerController _player;
  late final PlaybackSession _session;
  late final Future<void> _shadersReady;
  late final TabController _contentTabController;
  TabController? _roadTabController;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'source-player');

  late int _roadIndex;
  static const _episodesPerGroup = 20;
  int _episodeGroup = 0;
  bool _episodeDescending = false;
  bool _allEpisodesSheetOpen = false;
  bool _drawerOpen = false;
  bool? _immersive;
  int _resumeOffset = 0;
  bool _started = false;
  String? _resolvingLabel;
  bool _loading = true;
  ({int position, int road})? _failedSwitch;
  String? _error;
  int _requestToken = 0;

  MediaDetail get _detail => widget.request.detail;

  List<MediaRoad> get _roads => _detail.roads;

  @override
  void initState() {
    super.initState();
    _shaders = ShaderAssetService();
    _audio = AudioController();
    _player = PlayerController(_shaders, _audio);
    _contentTabController = TabController(length: 2, vsync: this);
    _roadIndex = _roads.indexWhere(
      (road) => road.code == widget.request.roadCode,
    );
    if (_roadIndex < 0) _roadIndex = 0;
    if (_roads.length >= 2) {
      _roadTabController = TabController(
        length: _roads.length,
        initialIndex: _roadIndex,
        vsync: this,
      );
    }
    final episodes = _roads.isEmpty
        ? const <MediaEpisode>[]
        : _roads[_roadIndex].episodes;
    final initial = episodes.indexWhere(
      (ep) => ep.number == widget.request.episode,
    );
    if (initial >= 0) _episodeGroup = initial ~/ _episodesPerGroup;
    final sourceName =
        mediaSources.maybeById(widget.request.sourceId)?.displayName ?? '';
    _session = PlaybackSession(
      title: _detail.title,
      sourceName: sourceName,
      mediaId: _detail.key.mediaId,
      artworkUrl: _detail.cover,
      episode: initial + 1,
      road: _roadIndex,
      roads: <PlaybackRoad>[
        for (final road in _roads)
          PlaybackRoad(
            name: road.name,
            episodes: <PlaybackEpisode>[
              for (final episode in road.episodes)
                PlaybackEpisode(title: episode.title, url: ''),
            ],
          ),
      ],
    );
    // 着色器只服务超分辨率，和网络解析互不依赖：并行准备，别挡首播。
    _shadersReady = _prepareShaders();
    int startOffset = 0;
    if (widget.demoUrl == null &&
        GStorage.getSetting(SettingsKeys.playResume)) {
      final history = HistoryStorage.get(
        widget.request.sourceId,
        _detail.key.mediaId,
      );
      if (history != null &&
          history.roadCode == widget.request.roadCode &&
          history.episode == widget.request.episode &&
          history.positionMs > 3000) {
        if (history.durationMs <= 0 ||
            (history.durationMs - history.positionMs > 15000)) {
          startOffset = history.positionMs ~/ 1000;
        }
      }
    }
    _resumeOffset = startOffset;
    if (initial >= 0) {
      unawaited(_play(initial + 1, roadIndex: _roadIndex, offset: startOffset));
    } else {
      _loading = false;
      _error = '暂无可播放剧集';
    }
    _startProgressTimer();
  }

  Timer? _progressTimer;

  void _startProgressTimer() {
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  void _saveProgress() {
    if (!_started || _loading || widget.demoUrl != null) return;
    final pos = _player.playback.playerPosition.inMilliseconds;
    if (pos <= 1000) return;
    final playing = _session.playbackEpisode;
    final road = _roads[playing.road];
    final ep = road.episodes[playing.episode - 1];
    unawaited(
      HistoryStorage.save(
        HistoryRecord(
          sourceId: widget.request.sourceId,
          mediaId: _detail.key.mediaId,
          title: _detail.title,
          cover: _detail.cover,
          roadCode: road.code,
          roadName: road.name,
          episode: ep.number,
          episodeTitle: ep.title,
          positionMs: pos,
          durationMs: _player.playback.playerDuration.inMilliseconds,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _prepareShaders() async {
    try {
      await _shaders.copyShadersToExternalDirectory();
    } catch (error) {
      // 拷贝失败只影响超分辨率，不应阻断播放。
      KazumiLogger().w('SourcePlayer: 着色器准备失败', error: error);
    }
  }

  Future<void> _play(
    int position, {
    required int roadIndex,
    int offset = 0,
    bool switchingRoad = false,
    String? resolvingLabel,
    ({int position, int road})? restoringAfter,
    bool? playWhenReady,
    double? speed,
  }) async {
    final token = ++_requestToken;
    final road = _roads[roadIndex];
    final item = road.episodes[position - 1];
    if (road.vipOnly || item.vipOnly) {
      setState(() {
        _loading = false;
        _error = '该剧集需要会员';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _failedSwitch = null;
      _resolvingLabel = resolvingLabel;
    });
    _session.loading = true;
    final previous = _session.playbackEpisode;
    var opening = false;
    var failed = false;
    Future<void> fail(String message) async {
      if (!mounted || token != _requestToken || failed) return;
      failed = true;
      if (opening) _resumeOffset = offset;
      setState(() {
        _error = message;
        if (opening) _started = false;
      });
      if (switchingRoad && opening) {
        _roadIndex = previous.road;
        _syncRoadTabController();
        _session.selectEpisode(previous.episode, road: previous.road);
        await _play(
          previous.episode,
          roadIndex: previous.road,
          offset: offset,
          restoringAfter: (road: roadIndex, position: position),
          playWhenReady: playWhenReady,
          speed: speed,
        );
        return;
      }
      if (_started) {
        final current = _session.playbackEpisode;
        _session.selectEpisode(current.episode, road: current.road);
        if (switchingRoad) {
          setState(() => _failedSwitch = (road: roadIndex, position: position));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }

    try {
      final demo = widget.demoUrl;
      final playback = demo == null
          ? await mediaSources
                .byId(widget.request.sourceId)
                .resolvePlayback(
                  mediaId: _detail.key.mediaId,
                  roadCode: road.code,
                  episode: item.number,
                  quality: widget.request.quality,
                )
          : MediaPlaybackSource(url: demo);
      await _shadersReady;
      if (!mounted || token != _requestToken) return;
      // Keep the old stream running during resolution. Capture its clock right
      // before the native player is replaced, including a pause during the wait.
      if (switchingRoad) {
        offset = _player.playback.playerPosition.inSeconds;
        playWhenReady = _player.playback.playerPlaying;
        speed = _player.playback.playerSpeed;
      }
      _resumeOffset = offset;
      opening = true;
      _player.playback.onOpenFailure = (message) => unawaited(fail(message));
      final ok = await _player.init(
        PlaybackInitParams(
          videoUrl: playback.url,
          offset: offset,
          playWhenReady: playWhenReady,
          speed: speed,
          episode: item.number,
          httpHeaders: playback.headers,
          referer: playback.referer,
          episodeTitle: item.title,
          workTitle: _detail.title,
          sourceName: _session.playbackSourceName,
          coverUrl: _detail.cover,
          currentRoad: roadIndex,
        ),
      );
      if (!mounted || token != _requestToken) return;
      if (failed) return;
      if (!ok) {
        await fail('播放器未能打开视频');
        return;
      }
      _session.markPlaying(position, road: roadIndex);
      _resumeOffset = 0;
      setState(() {
        _roadIndex = roadIndex;
        _episodeGroup = (position - 1) ~/ _episodesPerGroup;
        _started = true;
        _failedSwitch = restoringAfter;
      });
      _syncRoadTabController();
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      await fail(playbackSourceErrorMessage(error));
    } finally {
      if (mounted && token == _requestToken) {
        _session.loading = false;
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeEpisode(
    int position, {
    int currentRoad = 0,
    int offset = 0,
    String? resolvingLabel,
  }) async {
    if (_loading) return;
    _saveProgress();
    _session.selectEpisode(position, road: currentRoad);
    await _play(
      position,
      roadIndex: currentRoad,
      offset: offset,
      resolvingLabel: resolvingLabel,
    );
  }

  void _onEpisodeEnded() {
    if (_failedSwitch != null) setState(() => _failedSwitch = null);
    if (!GStorage.getSetting(SettingsKeys.autoPlayNext)) return;
    final playing = _session.playbackEpisode;
    final episodes = _roads[playing.road].episodes;
    // Positions are one-based. The same index selects the next item in this road.
    if (playing.episode >= episodes.length ||
        episodes[playing.episode].vipOnly) {
      return;
    }
    final next = episodes[playing.episode];
    unawaited(
      _changeEpisode(
        playing.episode + 1,
        currentRoad: playing.road,
        resolvingLabel: '正在连播第 ${next.number} 集',
      ),
    );
  }

  void _syncRoadTabController() {
    final controller = _roadTabController;
    if (controller == null) return;
    if (_roadIndex >= 0 &&
        _roadIndex < controller.length &&
        controller.index != _roadIndex) {
      controller.index = _roadIndex;
    }
  }

  @override
  void dispose() {
    _requestToken++;
    _progressTimer?.cancel();
    _saveProgress();
    unawaited(DisplayModeService.releaseSystemBars(this));
    _contentTabController.dispose();
    _roadTabController?.dispose();
    _player.dispose();
    _session.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session.fullscreen.attach(ModalRoute.of(context)!);
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      final showEndActions =
          _started &&
          !_loading &&
          _failedSwitch == null &&
          !_session.isPip &&
          !_player.panel.lockPanel &&
          _player.playback.completed &&
          !_player.playback.resumedNearEnd;
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final panelWidth = (MediaQuery.sizeOf(context).width * .38)
          .clamp(240.0, 420.0)
          .clamp(0.0, MediaQuery.sizeOf(context).width);
      final screenSize = MediaQuery.sizeOf(context);
      final tabletDetail =
          landscape && screenSize.width >= 900 && screenSize.height >= 600;
      final immersive =
          _session.isFullscreen ||
          _session.isPip ||
          (landscape && !tabletDetail);
      if (_immersive != immersive) {
        _immersive = immersive;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _immersive == immersive) {
            if (!immersive) setState(() => _drawerOpen = false);
            DisplayModeService.setSystemBarsHidden(
              owner: this,
              hidden: immersive,
            );
          }
        });
      }
      return PopScope(
        canPop: !_drawerOpen && !_allEpisodesSheetOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_allEpisodesSheetOpen) {
            setState(() => _allEpisodesSheetOpen = false);
          } else if (_drawerOpen) {
            setState(() => _drawerOpen = false);
          }
        },
        child: Scaffold(
          body: Stack(
            children: [
              SafeArea(
                top: !immersive,
                bottom: !immersive,
                left: !immersive,
                right: !immersive,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final video = ColoredBox(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_started)
                            PlayerItem(
                              playerController: _player,
                              videoPageController: _session,
                              fillsWindow: immersive,
                              episodePanelOpen: _drawerOpen,
                              episodePanelInset: _drawerOpen && landscape
                                  ? panelWidth
                                  : 0,
                              changeEpisode: _changeEpisode,
                              onEpisodeEnded: _onEpisodeEnded,
                              resolvingLabel: _resolvingLabel,
                              onToggleSidePanel: immersive && !showEndActions
                                  ? () => setState(() => _drawerOpen = true)
                                  : null,
                              onBackPressed: () {
                                if (_drawerOpen) {
                                  setState(() => _drawerOpen = false);
                                } else {
                                  Navigator.of(context).maybePop();
                                }
                              },
                              keyboardFocus: _keyboardFocus,
                              pauseForTimedShutdown: () => _player.pause(),
                              disableAnimations: MediaQuery.disableAnimationsOf(
                                context,
                              ),
                            )
                          else
                            _buildGate(context),
                          if (showEndActions)
                            LayoutBuilder(
                              builder: (context, constraints) => Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    // Leave the player’s edge controls reachable.
                                    maxWidth: constraints.maxWidth > 160
                                        ? (constraints.maxWidth - 96).clamp(
                                            0.0,
                                            420.0,
                                          )
                                        : constraints.maxWidth,
                                    maxHeight: constraints.maxHeight > 180
                                        ? constraints.maxHeight - 80
                                        : constraints.maxHeight * .80,
                                  ),
                                  child: _buildEndActions(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                    final failed = _failedSwitch;
                    if (tabletDetail && !immersive) {
                      Widget accessibleInfo({required bool episodesOnly}) =>
                          Observer(
                            builder: (_) {
                              final locked = _player.panel.lockPanel;
                              return ExcludeSemantics(
                                excluding: locked,
                                child: AbsorbPointer(
                                  absorbing: locked,
                                  child: _episodeInfo(
                                    context,
                                    drawer: false,
                                    informationOnly: !episodesOnly,
                                    episodesOnly: episodesOnly,
                                  ),
                                ),
                              );
                            },
                          );
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 2,
                              child: LayoutBuilder(
                                builder: (context, leftConstraints) => Column(
                                  children: [
                                    SizedBox(
                                      width: leftConstraints.maxWidth,
                                      height:
                                          (leftConstraints.maxWidth * 9 / 16)
                                              .clamp(
                                                0.0,
                                                leftConstraints.maxHeight * .64,
                                              ),
                                      child: video,
                                    ),
                                    if (failed != null && _started && !_loading)
                                      Observer(
                                        builder: (_) => _player.panel.lockPanel
                                            ? const SizedBox.shrink()
                                            : _switchFailureBar(
                                                context,
                                                failed,
                                              ),
                                      ),
                                    Expanded(
                                      child: accessibleInfo(
                                        episodesOnly: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: accessibleInfo(episodesOnly: true),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        if (immersive)
                          Expanded(child: video)
                        else
                          SizedBox(
                            width: constraints.maxWidth,
                            height: (constraints.maxWidth * 9 / 16).clamp(
                              0.0,
                              constraints.maxHeight,
                            ),
                            child: video,
                          ),
                        if (failed != null &&
                            _started &&
                            !_loading &&
                            !_session.isPip)
                          Observer(
                            builder: (_) => _player.panel.lockPanel
                                ? const SizedBox.shrink()
                                : SafeArea(
                                    top: false,
                                    child: _switchFailureBar(context, failed),
                                  ),
                          ),
                        if (!immersive)
                          Expanded(
                            child: Observer(
                              builder: (_) {
                                final locked = _player.panel.lockPanel;
                                return ExcludeSemantics(
                                  excluding: locked,
                                  child: AbsorbPointer(
                                    absorbing: locked,
                                    child: Stack(
                                      children: [
                                        _buildPortraitOptionC(context),
                                        if (_allEpisodesSheetOpen)
                                          Positioned.fill(
                                            child: _buildAllEpisodesOverlay(
                                              context,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_drawerOpen && !_player.panel.lockPanel)
                Positioned(
                  top: landscape ? 0 : null,
                  bottom: 0,
                  right: 0,
                  left: landscape ? null : 0,
                  width: landscape ? panelWidth : null,
                  height: landscape
                      ? null
                      : MediaQuery.sizeOf(context).height * .65,
                  child: Theme(
                    data: buildShellTheme(Brightness.dark),
                    child: Builder(
                      builder: (context) => Material(
                        elevation: 12,
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          child: _episodeInfo(context, drawer: true),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  static final RegExp _genericEpisodeTitlePattern = RegExp(
    r'^(?:第\s*0*\d+\s*[集话話期回]|(?:ep|e)\.?\s*0*\d+|0*\d+)$',
    caseSensitive: false,
  );

  bool _allNumericEpisodeTitles(List<MediaEpisode> episodes) =>
      episodes.isNotEmpty &&
      episodes.every((ep) {
        final t = ep.title.trim();
        return t.isEmpty || _genericEpisodeTitlePattern.hasMatch(t);
      });

  String get _formattedSchedule => _detail.updateSchedule
      .replaceAll('|', ' · ')
      .replaceFirstMapped(
        RegExp(r'^(\d+)全$'),
        (match) => '全 ${match[1]} 集',
      );

  List<String> get _compactMetaParts {
    final schedule = _formattedSchedule;
    return <String>{
      if (_detail.year != null) _detail.year.toString(),
      _detail.area,
      _detail.category,
      ..._detail.tags.take(2),
      if (_detail.episodeStatus.isNotEmpty)
        _detail.episodeStatus
      else
        schedule,
    }.where((part) => part.isNotEmpty).toList(growable: false);
  }

  Future<void> _selectRoadFromTab(int index) async {
    if (_loading || index < 0 || index >= _roads.length) return;
    if (index == _roadIndex) return;
    final road = _roads[index];
    final playable = !road.vipOnly && road.episodes.any((ep) => !ep.vipOnly);
    if (!playable) {
      _syncRoadTabController();
      KazumiDialog.showToast(
        context: context,
        message: road.vipOnly ? '该线路需要会员' : '该线路暂无可播放剧集',
      );
      return;
    }
    final target = road.episodes.indexWhere(
      (ep) => ep.number == _currentEpisodeNumber && !ep.vipOnly,
    );
    if (target < 0) {
      setState(() {
        _roadIndex = index;
        _episodeGroup = 0;
      });
      _syncRoadTabController();
      KazumiDialog.showToast(
        context: context,
        message: '该线路暂缺第 $_currentEpisodeNumber 集，请点选下方剧集',
      );
      return;
    }
    _saveProgress();
    _session.selectEpisode(target + 1, road: index);
    await _play(
      target + 1,
      roadIndex: index,
      switchingRoad: _started,
      offset: _resumeOffset,
    );
  }

  Future<void> _castVideo() async {
    if (kIsWeb) {
      KazumiDialog.showToast(
        context: context,
        message: 'DLNA 投屏需要原生局域网权限，请使用 Windows 或 Android 客户端',
      );
      return;
    }
    final videoUrl = _player.videoUrl;
    final title = _player.mediaTitle;
    final reason = castUnavailableReason(
      isLocalPlayback: _player.isLocalPlayback,
      url: videoUrl,
      referer: _player.referer,
      hasPlaybackHeaders: _player.hasPlaybackHeaders,
    );
    if (reason != null) {
      KazumiDialog.showToast(context: context, message: reason);
      return;
    }
    final lease = _player.playback.playing ? _player.pauseTemporarily() : null;
    try {
      if (lease != null) await lease.completed;
      if (!mounted ||
          _player.videoUrl != videoUrl ||
          _player.mediaTitle != title ||
          castUnavailableReason(
                isLocalPlayback: _player.isLocalPlayback,
                url: _player.videoUrl,
                referer: _player.referer,
                hasPlaybackHeaders: _player.hasPlaybackHeaders,
              ) !=
              null) {
        return;
      }
      await RemotePlay().castVideo(videoUrl, title: title);
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(context: context, message: '投屏启动失败，请稍后重试');
      }
    } finally {
      if (mounted && lease != null) {
        await _player.resumeTemporaryPause(lease);
      }
    }
  }

  Future<void> _openTimerSheet() async {
    final timer = TimedShutdownService();
    final value = await showPlayerOptions<int>(
      context,
      title: '定时关闭',
      selected: timer.isActive ? timer.setMinutes : 0,
      options: const [
        PlayerOption(0, '不开启'),
        PlayerOption(15, '15 分钟'),
        PlayerOption(30, '30 分钟'),
        PlayerOption(60, '60 分钟'),
        PlayerOption(-1, '自定义'),
      ],
    );
    if (!mounted || value == null) return;
    if (value == 0) {
      timer.cancel();
    } else if (value < 0) {
      TimedShutdownService.showCustomTimerDialog(
        onExpired: () => _player.pause(),
      );
    } else {
      timer.start(value, onExpired: () => _player.pause());
      KazumiDialog.showToast(
        context: context,
        message: '已设置 ${timer.formatMinutesToDisplay(value)} 后定时关闭',
      );
    }
  }

  Future<void> _openSuperResolutionSheet() async {
    if (kIsWeb) {
      KazumiDialog.showToast(context: context, message: '浏览器不支持 MPV 超分辨率');
      return;
    }
    final value = await showPlayerOptions<SuperResolutionMode>(
      context,
      title: '超分画质',
      selected: _player.playback.superResolutionMode,
      options: [
        for (final mode in SuperResolutionMode.values)
          PlayerOption(mode, mode.label, detail: mode.description),
      ],
    );
    if (!mounted || value == null) return;
    await _player.setShader(value);
  }

  Widget _buildPortraitOptionC(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.divider, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PlayraUnderlineTabBar(
                      controller: _contentTabController,
                      labels: const ['播放', '简介与资料'],
                      horizontalPadding: 6,
                      minHeight: 44,
                      indicatorBottom: 0,
                    ),
                  ),
                  if (widget.demoUrl == null)
                    _buildFavoriteButton(
                      context,
                      compactIconOnly:
                          constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(14) > 20,
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _contentTabController,
                children: [
                  _buildPlayTab(context),
                  _buildDetailTab(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoriteButton(
    BuildContext context, {
    required bool compactIconOnly,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder(
      valueListenable: FavoriteStorage.listenable(),
      builder: (context, box, child) {
        final favorite = FavoriteStorage.isFavorite(
          _detail.key.sourceId,
          _detail.key.mediaId,
        );
        void toggleFavorite() => FavoriteStorage.toggle(
          FavoriteRecord(
            sourceId: _detail.key.sourceId,
            mediaId: _detail.key.mediaId,
            title: _detail.title,
            cover: _detail.cover,
            category: _detail.category,
            subtitle: _detail.episodeStatus,
            updatedAt: DateTime.now(),
          ),
        );
        final icon = Icon(
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: compactIconOnly ? 20 : 15,
          color: favorite
              ? (isDark ? const Color(0xFF161224) : Colors.white)
              : t.accent,
        );
        if (compactIconOnly) {
          return IconButton(
            tooltip: favorite ? '取消追番' : '加入追番',
            icon: Icon(
              favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 20,
              color: favorite ? t.accent : t.textSecondary,
            ),
            onPressed: toggleFavorite,
          );
        }
        return Tooltip(
          message: favorite ? '取消追番' : '加入追番',
          child: Material(
            color: favorite ? t.accent : t.accent.withValues(alpha: 0.14),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: toggleFavorite,
              splashColor: t.accent.withValues(alpha: 0.18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 4),
                    Text(
                      favorite ? '已追番' : '追番',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: favorite
                            ? (isDark ? const Color(0xFF161224) : Colors.white)
                            : t.accent,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayTab(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = PlayraHomeTokens.of(context);
        final theme = Theme.of(context);
        final road = _roads.isEmpty ? null : _roads[_roadIndex];
        final episodes = road?.episodes ?? const <MediaEpisode>[];
        final numericMode = _allNumericEpisodeTitles(episodes);
        final playing = _session.playbackEpisode;
        final active = _started
            ? _roads[playing.road].episodes[playing.episode - 1]
            : null;
        final columns = _computeEpisodeColumns(
          maxWidth: constraints.maxWidth,
          numericMode: numericMode,
          episodesOnly: false,
          scaler: MediaQuery.textScalerOf(context),
        );
        final previewLimit = numericMode ? columns * 2 : columns * 2;
        final previewIndices = _computePreviewEpisodeIndices(
          total: episodes.length,
          limit: previewLimit,
          columns: columns,
          anchor: playing.road == _roadIndex
              ? (playing.episode - 1).clamp(0, math.max(0, episodes.length - 1))
              : 0,
        );
        final metaParts = _compactMetaParts;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            _detail.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 19,
                              height: 1.24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (_detail.score != null) ...[
                          const SizedBox(width: 10),
                          _ScoreInlineBadge(score: _detail.score!),
                        ],
                      ],
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        metaParts.join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                    if (_roads.length >= 2) ...[
                      const SizedBox(height: 12),
                      PlayraSegmentedTabBar(
                        controller: _roadTabController,
                        labels: [for (final r in _roads) r.name],
                        verticalPadding: 0,
                        expand: _roads.length <= 4,
                        onTap: _selectRoadFromTab,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildEpisodeSectionHeader(
                      context,
                      road: road,
                      episodes: episodes,
                      active: active,
                      showAllTrigger: episodes.length > previewLimit,
                      onOpenAll: () =>
                          setState(() => _allEpisodesSheetOpen = true),
                    ),
                  ],
                ),
              ),
            ),
            if (episodes.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                sliver: _buildEpisodeSliverGrid(
                  context,
                  road: road!,
                  episodes: episodes,
                  indices: previewIndices,
                  columns: columns,
                  numericMode: numericMode,
                  episodesOnly: false,
                  drawer: false,
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
                child: _buildQuickToolStrip(context),
              ),
            ),
            if (_detail.related.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    '相关推荐',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              MediaPosterGrid(
                items: _detail.related,
                insets: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                onTap: (item) =>
                    context.pushNamed('/detail', arguments: item.key),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDetailTab(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final tagItems = <String>{
      ..._detail.tags,
      if (_detail.category.isNotEmpty) _detail.category,
    }.where((item) => item.isNotEmpty).toList(growable: false);
    final schedule = _formattedSchedule;
    final updateLabel = _detail.episodeStatus.isNotEmpty
        ? _detail.episodeStatus
        : schedule;
    final infoRows = <({String label, String value, bool gold})>[
      if (_detail.score != null)
        (label: '评分', value: '★ ${_detail.score}', gold: true),
      if (_detail.subtitle.isNotEmpty)
        (label: '别名', value: _detail.subtitle, gold: false),
      if (_detail.year != null)
        (label: '年份', value: '${_detail.year}', gold: false),
      if (_detail.area.isNotEmpty)
        (label: '地区', value: _detail.area, gold: false),
      if (_detail.category.isNotEmpty)
        (label: '分类', value: _detail.category, gold: false),
      if (updateLabel.isNotEmpty)
        (label: '更新', value: updateLabel, gold: false),
      if (_roads.isNotEmpty)
        (
          label: '线路',
          value: _roads.map((r) => r.name).join(' · '),
          gold: false,
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _detail.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (tagItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tagItems)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.055)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '剧情简介',
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _detail.description.trim().isNotEmpty
                ? _detail.description.trim()
                : '暂无剧情简介',
            style: TextStyle(
              fontSize: 13,
              height: 1.72,
              color: _detail.description.trim().isNotEmpty
                  ? t.textSecondary
                  : t.textSecondary.withValues(alpha: 0.68),
            ),
          ),
          if (infoRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.038)
                    : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < infoRows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 9),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            infoRows[i].label,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: t.textSecondary.withValues(alpha: 0.68),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            infoRows[i].value,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: infoRows[i].gold
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: infoRows[i].gold
                                  ? const Color(0xFFFFC857)
                                  : t.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickToolStrip(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget buildPill({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      bool active = false,
    }) {
      final fg = active
          ? t.accent
          : onTap == null
          ? t.textSecondary.withValues(alpha: 0.68)
          : t.textPrimary.withValues(alpha: 0.9);
      return Material(
        color: active ? t.accent.withValues(alpha: 0.14) : pillBg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: t.accent.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          buildPill(
            icon: Icons.cast_rounded,
            label: '投屏',
            onTap: _started ? _castVideo : null,
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<int>(
            valueListenable: TimedShutdownService().remainingSecondsNotifier,
            builder: (context, remainingSeconds, _) {
              final active = remainingSeconds > 0;
              return buildPill(
                icon: Icons.timer_outlined,
                label: active
                    ? '定时 ${TimedShutdownService().formatRemainingTime()}'
                    : '定时关闭',
                active: active,
                onTap: _openTimerSheet,
              );
            },
          ),
          const SizedBox(width: 8),
          Observer(
            builder: (_) {
              final mode = _player.playback.superResolutionMode;
              final active = mode != SuperResolutionMode.off;
              return buildPill(
                icon: Icons.auto_awesome_outlined,
                label: active ? '超分 · ${mode.label}' : '超分画质',
                active: active,
                onTap: _openSuperResolutionSheet,
              );
            },
          ),
          const SizedBox(width: 8),
          buildPill(
            icon: Icons.open_in_new_rounded,
            label: '外部播放',
            onTap: _started ? _player.launchExternalPlayer : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAllEpisodesOverlay(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final road = _roads.isEmpty ? null : _roads[_roadIndex];
    final episodes = road?.episodes ?? const <MediaEpisode>[];
    final numericMode = _allNumericEpisodeTitles(episodes);
    final groupCount =
        (episodes.length + _episodesPerGroup - 1) ~/ _episodesPerGroup;
    final safeGroup = groupCount == 0
        ? 0
        : _episodeGroup.clamp(0, groupCount - 1);

    return Material(
      color: isDark
          ? const Color(0xFF12141D)
          : Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _computeEpisodeColumns(
            maxWidth: constraints.maxWidth,
            numericMode: numericMode,
            episodesOnly: false,
            scaler: MediaQuery.textScalerOf(context),
          );
          final indices = _computeGroupEpisodeIndices(
            total: episodes.length,
            group: safeGroup,
          );
          return Column(
            children: [
              Container(
                height: 46,
                padding: const EdgeInsets.only(left: 16, right: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: t.divider, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '全部选集 · ${episodes.length} 集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    if (episodes.length > 1) _buildSortButton(context),
                    IconButton(
                      tooltip: '关闭全部选集',
                      onPressed: () =>
                          setState(() => _allEpisodesSheetOpen = false),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (groupCount > 1)
                _buildRangePillBar(
                  context,
                  episodes: episodes,
                  groupCount: groupCount,
                  selectedGroup: safeGroup,
                ),
              Expanded(
                child: road == null || episodes.isEmpty
                    ? Center(
                        child: Text(
                          '暂无剧集',
                          style: TextStyle(color: t.textSecondary),
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            sliver: _buildEpisodeSliverGrid(
                              context,
                              road: road,
                              episodes: episodes,
                              indices: indices,
                              columns: columns,
                              numericMode: numericMode,
                              episodesOnly: false,
                              drawer: false,
                              closeAllSheetOnSelect: true,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEpisodeSectionHeader(
    BuildContext context, {
    required MediaRoad? road,
    required List<MediaEpisode> episodes,
    required MediaEpisode? active,
    required bool showAllTrigger,
    VoidCallback? onOpenAll,
    bool showCloseDrawer = false,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subLabel = active != null
        ? '当前 ${active.title}'
        : episodes.isNotEmpty
        ? '共 ${episodes.length} 集'
        : '';
    final leftGroup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '选集',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        if (_roads.length == 1 && road != null && !showCloseDrawer) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              road.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
        if (subLabel.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              subLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: t.textSecondary.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ],
    );

    final rightGroup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (episodes.length > 1) _buildSortButton(context),
        if (showAllTrigger && onOpenAll != null) ...[
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '全部 ${episodes.length} 集',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: t.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (showCloseDrawer)
          IconButton(
            tooltip: '关闭选集',
            onPressed: () => setState(() => _drawerOpen = false),
            icon: Icon(Icons.close_rounded, color: t.textSecondary),
          ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [leftGroup, rightGroup],
      ),
    );
  }

  Widget _buildSortButton(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _episodeDescending = !_episodeDescending;
        _episodeGroup = 0;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 15, color: t.textSecondary),
            const SizedBox(width: 2),
            Text(
              _episodeDescending ? '倒序' : '正序',
              style: TextStyle(
                fontSize: 12,
                color: t.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangePillBar(
    BuildContext context, {
    required List<MediaEpisode> episodes,
    required int groupCount,
    required int selectedGroup,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = episodes.length;
    String rangeLabel(int group) {
      if (_episodeDescending) {
        final startIdx = total - 1 - group * _episodesPerGroup;
        final endIdx = math.max(0, startIdx - _episodesPerGroup + 1);
        return '${episodes[startIdx].number}–${episodes[endIdx].number}';
      }
      final start = group * _episodesPerGroup;
      final end = (start + _episodesPerGroup).clamp(0, total);
      return '${episodes[start].number}–${episodes[end - 1].number}';
    }

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: groupCount,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, group) {
          final active = group == selectedGroup;
          return Material(
            color: active
                ? t.accent.withValues(alpha: 0.16)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Theme.of(context).colorScheme.surfaceContainerHighest),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _episodeGroup = group),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Center(
                  child: Text(
                    rangeLabel(group),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? t.accent : t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _computeEpisodeColumns({
    required double maxWidth,
    required bool numericMode,
    required bool episodesOnly,
    required TextScaler scaler,
  }) {
    if (episodesOnly) {
      if (!numericMode) return 1;
      return ((maxWidth - 32 + 8) / math.max(58.0, scaler.scale(14) * 3.8))
          .floor()
          .clamp(3, 5);
    }
    if (numericMode) {
      return ((maxWidth - 32 + 8) / math.max(58.0, scaler.scale(14) * 3.8))
          .floor()
          .clamp(3, 5);
    }
    return ((maxWidth - 32 + 8) / math.max(150.0, scaler.scale(14) * 11))
        .floor()
        .clamp(1, 2);
  }

  List<int> _computePreviewEpisodeIndices({
    required int total,
    required int limit,
    required int columns,
    required int anchor,
  }) {
    if (total <= 0) return const <int>[];
    final count = math.min(total, limit);
    if (_episodeDescending) {
      return List<int>.generate(count, (i) => total - 1 - i);
    }
    final maxStart = math.max(0, total - count);
    final start = ((anchor ~/ columns) * columns).clamp(0, maxStart);
    return List<int>.generate(count, (i) => start + i);
  }

  List<int> _computeGroupEpisodeIndices({
    required int total,
    required int group,
  }) {
    if (total <= 0) return const <int>[];
    final first = group * _episodesPerGroup;
    final count = (total - first).clamp(0, _episodesPerGroup);
    if (_episodeDescending) {
      return List<int>.generate(count, (i) => total - 1 - (first + i));
    }
    return List<int>.generate(count, (i) => first + i);
  }

  SliverGrid _buildEpisodeSliverGrid(
    BuildContext context, {
    required MediaRoad road,
    required List<MediaEpisode> episodes,
    required List<int> indices,
    required int columns,
    required bool numericMode,
    required bool episodesOnly,
    required bool drawer,
    bool closeAllSheetOnSelect = false,
  }) {
    final t = PlayraHomeTokens.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    final playing = _session.playbackEpisode;
    final active = _started
        ? _roads[playing.road].episodes[playing.episode - 1]
        : null;
    final tileExtent = numericMode
        ? math.max(42.0, scaler.scale(14) * 2.4)
        : (scaler.scale(14) * 4.8).clamp(62.0, double.infinity);

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: tileExtent,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: indices.length,
      itemBuilder: (context, offset) {
        final i = indices[offset];
        final item = episodes[i];
        final current =
            active != null &&
            playing.road == _roadIndex &&
            playing.episode == i + 1;
        final vip = item.vipOnly || road.vipOnly;
        final disabled = _loading || vip;
        final numText = item.number.toString().padLeft(2, '0');

        final bgColor = current
            ? t.accent.withValues(alpha: isDark ? 0.18 : 0.14)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.055)
                  : theme.colorScheme.surfaceContainerHighest);
        final borderColor = current
            ? t.accent.withValues(alpha: isDark ? 0.42 : 0.45)
            : Colors.transparent;
        final fgColor = current
            ? t.accent
            : disabled
            ? t.textSecondary.withValues(alpha: 0.68)
            : t.textPrimary.withValues(alpha: 0.9);

        void handleTap() {
          if (drawer) {
            setState(() => _drawerOpen = false);
          }
          if (closeAllSheetOnSelect) {
            setState(() => _allEpisodesSheetOpen = false);
          }
          if (!current) {
            _changeEpisode(i + 1, currentRoad: _roadIndex);
          }
        }

        return Tooltip(
          message: vip ? '${item.title} · 需要会员' : item.title,
          child: Semantics(
            button: true,
            selected: current,
            enabled: !disabled,
            child: Material(
              color: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: borderColor, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: disabled ? null : handleTap,
                splashColor: t.accent.withValues(alpha: 0.15),
                child: numericMode
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (current) ...[
                                Observer(
                                  builder: (context) => _EqualizerIcon(
                                    color: t.accent,
                                    playing:
                                        _started &&
                                        _player.playback.playing &&
                                        !_player.playback.completed &&
                                        !PlayraMotion.reduceOf(context),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                numText,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: current
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: fgColor,
                                ),
                              ),
                            ],
                          ),
                          if (vip)
                            Positioned(
                              top: 2,
                              right: 4,
                              child: Text(
                                'VIP',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFFC857),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (current) ...[
                                  Observer(
                                    builder: (context) => _EqualizerIcon(
                                      color: t.accent,
                                      playing:
                                          _started &&
                                          _player.playback.playing &&
                                          !_player.playback.completed &&
                                          !PlayraMotion.reduceOf(context),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  numText,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    color: current
                                        ? t.accent
                                        : t.textSecondary,
                                  ),
                                ),
                                if (vip) ...[
                                  const Spacer(),
                                  const Text(
                                    '需要会员',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFFFC857),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: current
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: fgColor,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _episodeInfo(
    BuildContext context, {
    required bool drawer,
    bool informationOnly = false,
    bool episodesOnly = false,
  }) {
    assert(!(informationOnly && episodesOnly));
    if (informationOnly) {
      return _buildTabletInfoPane(context);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = PlayraHomeTokens.of(context);
        final road = _roads.isEmpty ? null : _roads[_roadIndex];
        final episodes = road?.episodes ?? const <MediaEpisode>[];
        final numericMode = _allNumericEpisodeTitles(episodes);
        final groupCount =
            (episodes.length + _episodesPerGroup - 1) ~/ _episodesPerGroup;
        final safeGroup = groupCount == 0
            ? 0
            : _episodeGroup.clamp(0, groupCount - 1);
        final playing = _session.playbackEpisode;
        final active = _started
            ? _roads[playing.road].episodes[playing.episode - 1]
            : null;
        final columns = _computeEpisodeColumns(
          maxWidth: constraints.maxWidth,
          numericMode: numericMode,
          episodesOnly: episodesOnly,
          scaler: MediaQuery.textScalerOf(context),
        );
        final indices = _computeGroupEpisodeIndices(
          total: episodes.length,
          group: safeGroup,
        );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEpisodeSectionHeader(
                      context,
                      road: road,
                      episodes: episodes,
                      active: active,
                      showAllTrigger: false,
                      showCloseDrawer: drawer,
                    ),
                    if (_roads.length >= 2) ...[
                      const SizedBox(height: 10),
                      PlayraSegmentedTabBar(
                        controller: _roadTabController,
                        labels: [for (final r in _roads) r.name],
                        verticalPadding: 0,
                        expand: _roads.length <= 3,
                        onTap: _selectRoadFromTab,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (groupCount > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildRangePillBar(
                    context,
                    episodes: episodes,
                    groupCount: groupCount,
                    selectedGroup: safeGroup,
                  ),
                ),
              ),
            if (road != null && episodes.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                sliver: _buildEpisodeSliverGrid(
                  context,
                  road: road,
                  episodes: episodes,
                  indices: indices,
                  columns: columns,
                  numericMode: numericMode,
                  episodesOnly: episodesOnly,
                  drawer: drawer,
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '暂无剧集',
                    style: TextStyle(color: t.textSecondary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTabletInfoPane(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final theme = Theme.of(context);
    final metaParts = _compactMetaParts;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  _detail.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontSize: 21,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_detail.score != null) ...[
                                const SizedBox(width: 10),
                                _ScoreInlineBadge(score: _detail.score!),
                              ],
                            ],
                          ),
                          if (metaParts.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              metaParts.join(' · '),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.demoUrl == null) ...[
                      const SizedBox(width: 12),
                      _buildFavoriteButton(context, compactIconOnly: false),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _buildQuickToolStrip(context),
                const SizedBox(height: 12),
                if (_detail.description.trim().isNotEmpty)
                  Text(
                    _detail.description.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.68,
                      color: t.textSecondary,
                    ),
                  ),
                if (_detail.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    '别名：${_detail.subtitle}',
                    style: TextStyle(fontSize: 12, color: t.textSecondary.withValues(alpha: 0.68)),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (_detail.related.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                '相关推荐',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          MediaPosterGrid(
            items: _detail.related,
            insets: const EdgeInsets.fromLTRB(4, 0, 4, 24),
            onTap: (item) => context.pushNamed('/detail', arguments: item.key),
          ),
        ],
      ],
    );
  }

  int get _currentEpisodeNumber {
    final ref = _started ? _session.playbackEpisode : _session.selectedEpisode;
    return ref.episode > 0
        ? _roads[ref.road].episodes[ref.episode - 1].number
        : widget.request.episode;
  }

  Future<void> _chooseRoad() async {
    setState(() => _drawerOpen = false);
    while (true) {
      if (!mounted || _loading) return;
      final currentNumber = _currentEpisodeNumber;
      final playingRoad = _started
          ? _session.playbackEpisode.road
          : _session.selectedEpisode.road;
      final options = <PlayerOption<int>>[];
      for (final (i, road) in _roads.indexed) {
        final playable =
            !road.vipOnly && road.episodes.any((ep) => !ep.vipOnly);
        final hasEpisode =
            playable &&
            road.episodes.any(
              (ep) => ep.number == currentNumber && !ep.vipOnly,
            );
        options.add(
          PlayerOption(
            i,
            road.name,
            icon: Icons.alt_route_rounded,
            enabled: playable,
            opensPage: playable && !hasEpisode,
            detail: road.vipOnly
                ? '需要会员'
                : road.episodes.isEmpty
                ? '暂无剧集'
                : !playable
                ? '暂无可播放剧集'
                : !hasEpisode
                ? '缺第 $currentNumber 集 · 查看其他集'
                : _started && i == playingRoad
                ? '当前线路 · 第 $currentNumber 集'
                : null,
          ),
        );
      }
      final index = await showPlayerOptions<int>(
        context,
        title: '切换线路',
        options: options,
        selected: playingRoad,
        narrow: true,
      );
      if (!mounted || index == null || _loading) return;
      final road = _roads[index];
      final target = road.episodes.indexWhere(
        (ep) => ep.number == _currentEpisodeNumber && !ep.vipOnly,
      );
      if (target < 0) {
        var returnToRoads = false;
        final position = await showRoadEpisodes(
          context,
          roadName: road.name,
          onBack: () => returnToRoads = true,
          episodes: [
            for (final (i, ep) in road.episodes.indexed)
              PlayerOption(
                i + 1,
                ep.number.toString().padLeft(2, '0'),
                detail: ep.vipOnly ? '需要会员 · ${ep.title}' : ep.title,
                enabled: !ep.vipOnly,
              ),
          ],
        );
        if (!mounted || _loading) return;
        if (returnToRoads) continue;
        if (position == null) return;
        await _changeEpisode(position, currentRoad: index);
        return;
      }
      if (_started && index == _session.playbackEpisode.road) return;
      _saveProgress();
      _session.selectEpisode(target + 1, road: index);
      await _play(
        target + 1,
        roadIndex: index,
        switchingRoad: _started,
        offset: _resumeOffset,
      );
      return;
    }
  }

  Widget _buildEndActions(BuildContext context) {
    final playing = _session.playbackEpisode;
    final last = playing.episode == _roads[playing.road].episodes.length;
    return PlayerStatusOverlay(
      icon: Icons.check_circle_outline_rounded,
      title: last ? '已播至末集' : '本集播完',
      primaryLabel: '重播',
      primaryIcon: Icons.replay_rounded,
      onPrimary: _player.playback.restartFromBeginning,
      secondaryLabel: '选集',
      secondaryIcon: Icons.playlist_play_rounded,
      onSecondary: () => setState(() => _drawerOpen = true),
    );
  }

  Widget _switchFailureBar(
    BuildContext context,
    ({int position, int road}) failed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                '换线失败 · 仍在${_roads[_session.playbackEpisode.road].name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    _saveProgress();
                    _session.selectEpisode(failed.position, road: failed.road);
                    _play(
                      failed.position,
                      roadIndex: failed.road,
                      switchingRoad: true,
                    );
                  },
                  child: const Text('重试'),
                ),
                TextButton(onPressed: _chooseRoad, child: const Text('换线')),
                IconButton(
                  tooltip: '关闭提示',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _failedSwitch = null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGate(BuildContext context) {
    final cover = _detail.cover;
    final fallback = Image.asset(
      'assets/images/player/harbor-at-dusk.webp',
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_error == null)
          if (cover.isNotEmpty || _detail.fallbackCover.isNotEmpty)
            MediaCoverImage(
              url: cover,
              fallbackUrl: _detail.fallbackCover,
              errorWidget: fallback,
            )
          else
            fallback
        else
          const ColoredBox(color: Color(0xFF0E1017)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Colors.black54, Colors.black87, Colors.black],
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  tooltip: '返回',
                ),
              ),
              Expanded(
                child: _error == null
                    ? const PlayerBufferingOverlay(
                        player: null,
                        buffering: false,
                        resolving: true,
                      )
                    : _buildGateError(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGateError(BuildContext context) {
    final selected = _session.selectedEpisode;
    final canSwitch = _roads.indexed.any(
      (entry) =>
          entry.$1 != selected.road &&
          !entry.$2.vipOnly &&
          entry.$2.episodes.any((ep) => !ep.vipOnly),
    );
    return PlayerStatusOverlay(
      icon: Icons.error_outline_rounded,
      title: '播放失败',
      message: _error,
      primaryLabel: '重试',
      primaryIcon: Icons.refresh_rounded,
      onPrimary: selected.episode > 0
          ? () => _play(
              selected.episode,
              roadIndex: selected.road,
              offset: _resumeOffset,
            )
          : null,
      secondaryLabel: '切换线路',
      secondaryIcon: Icons.swap_horiz_rounded,
      onSecondary: canSwitch ? _chooseRoad : null,
    );
  }
}

class _ScoreInlineBadge extends StatelessWidget {
  const _ScoreInlineBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC857);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 15, color: gold),
        const SizedBox(width: 2),
        Text(
          score.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: gold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EqualizerIcon extends StatefulWidget {
  const _EqualizerIcon({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  State<_EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<_EqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _EqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _waveHeight(double phaseOffset) {
    final phase = _controller.value * 2 * math.pi + phaseOffset;
    return 3.5 + 7.5 * (0.5 + 0.5 * math.sin(phase));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 11,
        height: 11,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final h1 = widget.playing ? _waveHeight(0.0) : 5.0;
            final h2 = widget.playing ? _waveHeight(2.1) : 11.0;
            final h3 = widget.playing ? _waveHeight(4.2) : 7.0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [_bar(h1), _bar(h2), _bar(h3)],
            );
          },
        ),
      ),
    );
  }

  Widget _bar(double height) => Container(
    width: 2.4,
    height: height,
    decoration: BoxDecoration(
      color: widget.color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Content-first failure and completion controls inside the video viewport.
/// Missing callbacks intentionally hide actions that are not available.
@visibleForTesting
class PlayerStatusOverlay extends StatelessWidget {
  const PlayerStatusOverlay({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC5ABF0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 360, maxHeight: height),
            child: Material(
              key: const ValueKey('player-status-card'),
              color: const Color(0xDB10111B),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: accent),
                    const SizedBox(height: 2),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (message != null && message!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFCFCCD9),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                    if (onPrimary != null || onSecondary != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          if (onPrimary != null)
                            FilledButton.icon(
                              onPressed: onPrimary,
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: const Color(0xFF211735),
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              icon: Icon(primaryIcon, size: 18),
                              label: Text(primaryLabel),
                            ),
                          if (onSecondary != null)
                            OutlinedButton.icon(
                              onPressed: onSecondary,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFF77728A),
                                ),
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              icon: Icon(secondaryIcon, size: 18),
                              label: Text(secondaryLabel),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
