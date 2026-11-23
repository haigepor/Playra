import 'dart:async';
import 'package:kazumi/shell/shell_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/pages/player/player_option_sheet.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/player/player_buffering_overlay.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';

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

class _SourcePlayerPageState extends State<SourcePlayerPage> {
  late final ShaderAssetService _shaders;
  late final AudioController _audio;
  late final PlayerController _player;
  late final PlaybackSession _session;
  late final Future<void> _shadersReady;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'source-player');

  late int _roadIndex;
  static const _episodesPerGroup = 20;
  int _episodeGroup = 0;
  bool _allEpisodes = true;
  bool _expanded = false;
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
    _roadIndex = _roads.indexWhere(
      (road) => road.code == widget.request.roadCode,
    );
    if (_roadIndex < 0) _roadIndex = 0;
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
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      final message = switch (error) {
        MediaSourceException(kind: MediaSourceErrorKind.network) => '视频连接失败',
        MediaSourceException(kind: MediaSourceErrorKind.protocol) => '视频源响应异常',
        MediaSourceException(:final message) => message,
        _ => '视频加载失败',
      };
      await fail(message);
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

  @override
  void dispose() {
    _requestToken++;
    _progressTimer?.cancel();
    _saveProgress();
    unawaited(DisplayModeService.releaseSystemBars(this));
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
      final immersive =
          _session.isFullscreen ||
          _session.isPip ||
          MediaQuery.orientationOf(context) == Orientation.landscape;
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
        canPop: !_drawerOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _drawerOpen) setState(() => _drawerOpen = false);
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
                        ],
                      ),
                    );
                    final failed = _failedSwitch;
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
                        if (showEndActions) _buildEndActions(context),
                        if (!immersive)
                          Expanded(
                            child: Observer(
                              builder: (_) {
                                final locked = _player.panel.lockPanel;
                                return ExcludeSemantics(
                                  excluding: locked,
                                  child: AbsorbPointer(
                                    absorbing: locked,
                                    child: _episodeInfo(context, drawer: false),
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

  Widget _episodeInfo(BuildContext context, {required bool drawer}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final road = _roads.isEmpty ? null : _roads[_roadIndex];
        final episodes = road?.episodes ?? const <MediaEpisode>[];
        final first = _episodeGroup * _episodesPerGroup;
        final groupCount =
            (episodes.length + _episodesPerGroup - 1) ~/ _episodesPerGroup;
        final visibleCount = (episodes.length - first).clamp(
          0,
          _episodesPerGroup,
        );
        String groupLabel(int group) {
          final start = group * _episodesPerGroup;
          final end = (start + _episodesPerGroup).clamp(0, episodes.length);
          return '${episodes[start].number}–${episodes[end - 1].number}';
        }

        final playing = _session.playbackEpisode;
        final active = _started
            ? _roads[playing.road].episodes[playing.episode - 1]
            : null;
        final theme = Theme.of(context);
        final measure = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        var labelWidth = 0.0;
        for (final episode in episodes) {
          measure.text = TextSpan(
            text: episode.number.toString().padLeft(2, '0'),
            style: theme.textTheme.labelLarge,
          );
          measure.layout();
          if (measure.width > labelWidth) labelWidth = measure.width;
        }
        measure.dispose();
        final cellWidth = (labelWidth + 34).clamp(48.0, double.infinity);
        final columns = ((constraints.maxWidth - 32 + 6) / (cellWidth + 6))
            .floor()
            .clamp(1, 6);
        final condensed = !drawer && !_allEpisodes;
        final anchor = playing.road == _roadIndex
            ? (playing.episode - 1).clamp(0, episodes.length)
            : 0;
        final quickStart = (anchor ~/ columns * columns).clamp(
          0,
          (episodes.length - columns).clamp(0, episodes.length),
        );
        final schedule = _detail.updateSchedule
            .replaceAll('|', ' · ')
            .replaceFirstMapped(
              RegExp(r'^(\d+)全$'),
              (match) => '全 ${match[1]} 集',
            );
        final playbackStatus = [
          if (active != null) '当前 ${active.title}',
          _detail.episodeStatus,
        ].where((part) => part.isNotEmpty).join(' · ');
        final metadata = <String>{
          if (_detail.year != null) _detail.year.toString(),
          _detail.area,
          _detail.category,
          ..._detail.tags,
          schedule,
          if (_detail.score != null) '评分 ${_detail.score}',
        }..remove('');
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!drawer) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _detail.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontSize: 24,
                                    height: 1.18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (playbackStatus.isNotEmpty)
                                  const SizedBox(height: 2),
                                if (playbackStatus.isNotEmpty)
                                  Text(
                                    playbackStatus,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.demoUrl == null)
                            ValueListenableBuilder(
                              valueListenable: FavoriteStorage.listenable(),
                              builder: (context, box, child) {
                                final favorite = FavoriteStorage.isFavorite(
                                  _detail.key.sourceId,
                                  _detail.key.mediaId,
                                );
                                return IconButton(
                                  tooltip: favorite ? '取消追番' : '加入追番',
                                  icon: Icon(
                                    favorite
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                  ),
                                  onPressed: () => FavoriteStorage.toggle(
                                    FavoriteRecord(
                                      sourceId: _detail.key.sourceId,
                                      mediaId: _detail.key.mediaId,
                                      title: _detail.title,
                                      cover: _detail.cover,
                                      category: _detail.category,
                                      subtitle: _detail.episodeStatus,
                                      updatedAt: DateTime.now(),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      if (metadata.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            metadata.join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Divider(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选集',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!drawer && episodes.length > columns)
                          TextButton(
                            onPressed: () =>
                                setState(() => _allEpisodes = !_allEpisodes),
                            child: Text(
                              _allEpisodes ? '收起' : '全部 ${episodes.length} 集',
                            ),
                          ),
                        if (drawer)
                          IconButton(
                            tooltip: '关闭选集',
                            onPressed: () =>
                                setState(() => _drawerOpen = false),
                            icon: const Icon(Icons.close),
                          )
                        else if (road != null)
                          _roadMenu(context, road),
                      ],
                    ),
                    if (drawer && road != null)
                      _roadMenu(context, road, drawer: true),
                    if (!condensed && groupCount > 1)
                      Row(
                        children: [
                          Text(
                            '共 ${episodes.length} 集',
                            style: theme.textTheme.bodySmall,
                          ),
                          const Spacer(),
                          PopupMenuButton<int>(
                            tooltip: '选择集数区间',
                            initialValue: _episodeGroup,
                            onSelected: (group) =>
                                setState(() => _episodeGroup = group),
                            itemBuilder: (_) => [
                              for (var group = 0; group < groupCount; group++)
                                CheckedPopupMenuItem(
                                  value: group,
                                  checked: group == _episodeGroup,
                                  child: Text(groupLabel(group)),
                                ),
                            ],
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Row(
                                children: [
                                  Text(groupLabel(_episodeGroup)),
                                  const Icon(Icons.expand_more, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent:
                      (MediaQuery.textScalerOf(context).scale(14) * 1.3 + 16)
                          .clamp(48.0, double.infinity),
                  crossAxisSpacing: drawer ? 8 : 6,
                  mainAxisSpacing: 4,
                ),
                itemCount: condensed
                    ? episodes.length.clamp(0, columns)
                    : visibleCount,
                itemBuilder: (context, offset) {
                  final i = (condensed ? quickStart : first) + offset;
                  final item = episodes[i];
                  final current =
                      active != null &&
                      playing.road == _roadIndex &&
                      playing.episode == i + 1;
                  return Semantics(
                    selected: current,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: current
                            ? theme.colorScheme.primary.withValues(alpha: .12)
                            : theme.colorScheme.surfaceContainer,
                        side: BorderSide(
                          color: current
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      onPressed: _loading || item.vipOnly || road!.vipOnly
                          ? null
                          : () {
                              if (drawer) setState(() => _drawerOpen = false);
                              if (!current) {
                                _changeEpisode(i + 1, currentRoad: _roadIndex);
                              }
                            },
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (current && !drawer)
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                            Text(
                              item.number.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontWeight: drawer ? FontWeight.w600 : null,
                                color: current
                                    ? theme.colorScheme.primary
                                    : (item.vipOnly || road!.vipOnly
                                          ? theme.disabledColor
                                          : theme.colorScheme.onSurface),
                              ),
                            ),
                            if (current && drawer) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.equalizer_rounded,
                                color: theme.colorScheme.primary,
                                size: 15,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (!drawer && _detail.description.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_detail.description.isNotEmpty)
                        LayoutBuilder(
                          builder: (context, c) {
                            final style = theme.textTheme.bodyMedium!;
                            final measure = TextPainter(
                              text: TextSpan(
                                text: _detail.description,
                                style: style,
                              ),
                              maxLines: 2,
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                            )..layout(maxWidth: c.maxWidth);
                            final long = measure.didExceedMaxLines;
                            measure.dispose();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '剧情简介',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    if (long)
                                      TextButton(
                                        onPressed: () => setState(
                                          () => _expanded = !_expanded,
                                        ),
                                        child: Text(_expanded ? '收起' : '展开'),
                                      ),
                                  ],
                                ),
                                if (!long) const SizedBox(height: 4),
                                Text(
                                  _detail.description,
                                  maxLines: _expanded ? null : 2,
                                  overflow: _expanded
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: style,
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            if (!drawer && _detail.subtitle.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('作品资料'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(
                            '别名：${_detail.subtitle}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!drawer && _detail.related.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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

  Widget _roadMenu(
    BuildContext context,
    MediaRoad road, {
    bool drawer = false,
  }) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: _loading || _roads.length < 2 ? null : _chooseRoad,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: drawer
            ? double.infinity
            : MediaQuery.sizeOf(context).width * .32,
        minHeight: 44,
      ),
      child: Align(
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: drawer
                ? Theme.of(context).colorScheme.surfaceContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: drawer ? 12 : 9,
              vertical: drawer ? 8 : 4,
            ),
            child: Row(
              mainAxisSize: drawer ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    road.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                if (_roads.length > 1)
                  const Icon(Icons.expand_more_rounded, size: 16),
              ],
            ),
          ),
        ),
      ),
    ),
  );

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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  last ? '已播至末集' : '本集播完',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    onPressed: _player.playback.restartFromBeginning,
                    child: const Text('重播'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _drawerOpen = true),
                    child: const Text('选集'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
        if (cover.isNotEmpty)
          MediaCoverImage(url: cover, errorWidget: fallback)
        else
          fallback,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (selected.episode > 0)
                FilledButton.tonal(
                  onPressed: () => _play(
                    selected.episode,
                    roadIndex: selected.road,
                    offset: _resumeOffset,
                  ),
                  child: const Text('重试'),
                ),
              if (canSwitch)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _chooseRoad,
                  child: const Text('换线'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
