import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_system_bars.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/player/source_media_player.dart';
import 'package:kazumi/services/player/web_player_surface.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_playback_coordinator.dart';
import 'miomedia_playing_mark.dart';
import '../home/home_theme.dart';
import '../settings/modern_back_button.dart';

/// 来源作品有独立身份；不创建 Bangumi 收藏、历史或弹幕上下文。
class MioDetailPage extends StatefulWidget {
  const MioDetailPage({
    super.key,
    required this.item,
    this.service,
    this.autoPlay = false,
  });
  final MioVideo item;
  final MioMediaService? service;
  final bool autoPlay;
  @override
  State<MioDetailPage> createState() => _MioDetailPageState();
}

class _MioDetailPageState extends State<MioDetailPage> {
  late MioVideo video = widget.item;
  late final service = widget.service ?? MioMediaService();
  late final _playback = MioPlaybackCoordinator(
    widget.item.id,
    service,
    singleMovie: widget.item.kind == MioKind.movie,
  );
  MioLine? line;
  List<MioEpisode> episodes = [];
  CancelToken? _detailCancel, _episodesCancel, _playCancel;
  int _detailGeneration = 0, _episodesGeneration = 0, _playGeneration = 0;
  bool detailLoading = false, episodesLoading = false, playingLoading = false;
  String? detailError, episodesError, playMessage;
  String? playingCode;
  int? playingNumber;
  MioEpisode? _requestedEpisode;
  Player? _player;
  VideoController? _videoController;
  PlayerController? _nativePlayer;
  VideoPageController? _nativeView;
  final _nativeSurfaceKey = GlobalKey();
  final _keyboardFocus = FocusNode();
  late final _mediaSession = SourceMediaPlayer(
    createNative: (url, debug) => _nativePlayer!.playback,
  );
  final _activity = ValueNotifier(false);
  final _activitySubscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _mediaTail = Future.value();
  bool _disposed = false;
  bool _autoStarted = false;

  @override
  void initState() {
    super.initState();
    unawaited(loadDetail());
  }

  Future<void> loadDetail() async {
    _detailCancel?.cancel();
    final cancel = _detailCancel = CancelToken();
    final generation = ++_detailGeneration;
    setState(() {
      detailLoading = true;
      detailError = null;
    });
    try {
      final result = await service.detail(video.id, cancel: cancel);
      if (!mounted || generation != _detailGeneration || cancel.isCancelled) {
        return;
      }
      setState(() => video = result);
      if (result.lines.isNotEmpty) {
        await selectLine(_playback.ranked(result.lines).first);
        if (widget.autoPlay &&
            !_autoStarted &&
            mounted &&
            !cancel.isCancelled &&
            generation == _detailGeneration &&
            episodes.isNotEmpty) {
          _autoStarted = true;
          unawaited(play(episodes.first));
        }
      }
    } catch (_) {
      if (mounted && generation == _detailGeneration && !cancel.isCancelled) {
        setState(() => detailError = '作品资料加载失败，请重试');
      }
    } finally {
      if (mounted && generation == _detailGeneration) {
        setState(() => detailLoading = false);
      }
    }
  }

  Future<void> selectLine(MioLine selected) async {
    // 切线路作废尚未完成的播放请求，不把旧线路解析结果装到新选择上。
    _playCancel?.cancel();
    _playGeneration++;
    _episodesCancel?.cancel();
    final cancel = _episodesCancel = CancelToken();
    final generation = ++_episodesGeneration;
    setState(() {
      line = selected;
      episodes = [];
      episodesLoading = true;
      episodesError = null;
      playingLoading = false;
      playMessage = null;
    });
    try {
      // 底层读取属于页面会话；快速换线只取消本次 UI 展示，不丢共享缓存。
      final result = await _playback.episodes(selected);
      if (!mounted || generation != _episodesGeneration || cancel.isCancelled) {
        return;
      }
      setState(() => episodes = result);
    } catch (_) {
      if (mounted && generation == _episodesGeneration && !cancel.isCancelled) {
        setState(() => episodesError = '剧集加载失败，请重试');
      }
    } finally {
      if (mounted && generation == _episodesGeneration) {
        setState(() => episodesLoading = false);
      }
    }
  }

  Future<void> play(MioEpisode episode) async {
    _playCancel?.cancel();
    final cancel = _playCancel = CancelToken();
    final generation = ++_playGeneration;
    setState(() {
      _requestedEpisode = episode;
      playingLoading = true;
      playMessage = null;
    });
    try {
      await _player?.pause();
      if (!mounted || generation != _playGeneration || cancel.isCancelled) {
        return;
      }
      var attempt = 0;
      final result = await _playback.play(
        episode,
        video.lines,
        cancel: cancel,
        onAttempt: (selected, target) async {
          final items = selected.code == line?.code
              ? episodes
              : await _playback.episodes(selected);
          if (!mounted || generation != _playGeneration || cancel.isCancelled)
            return;
          setState(() {
            line = selected;
            episodes = items;
            _requestedEpisode = target;
            playMessage = attempt++ == 0 ? null : '正在尝试${selected.label}…';
          });
        },
        open: (target, media) => _openMedia(target, media, generation, cancel),
      );
      if (!mounted || generation != _playGeneration || cancel.isCancelled) {
        return;
      }
      setState(
        () => playMessage = switch (result.status) {
          'ready' => null,
          'interaction_required' => '点击播放器继续播放',
          'ad_required' => '来源平台仍要求广告校验，请重试或切换线路。',
          'identity_mismatch' => '播放资源与所选剧集不匹配',
          'invalid_media' => '播放资源地址无效',
          _ => switch (result.errorCode) {
            'CLIENT_PARSE_INVALID_RESPONSE' => '该线路解析接口返回了无效数据，请重试或切换线路。',
            'CLIENT_PARSE_NETWORK' || 'TIMEOUT' => '解析请求超时或网络异常，请重试或切换线路。',
            'MEDIA_LOAD_FAILED' => '已取得视频地址，但媒体加载失败，请重试或切换线路。',
            'CLIENT_PARSE_REJECTED' => '来源解析接口未提供可播放资源，请切换线路。',
            _ => '暂时无法取得播放资源，可重试或切换线路。',
          },
        },
      );
    } catch (_) {
      if (mounted && generation == _playGeneration && !cancel.isCancelled) {
        setState(() => playMessage = '播放请求失败，请重试');
      }
    } finally {
      if (mounted && generation == _playGeneration) {
        setState(() => playingLoading = false);
      }
    }
  }

  void _updateActivity() {
    if (_disposed || _player == null) return;
    final state = _player!.state;
    final active =
        state.playing &&
        !state.buffering &&
        state.position > Duration.zero &&
        (state.width ?? 0) > 0 &&
        (state.height ?? 0) > 0;
    if (_activity.value != active) _activity.value = active;
  }

  Future<bool?> _openMedia(
    MioEpisode episode,
    Map media,
    int generation,
    CancelToken cancel,
  ) async {
    // stop/open 串行，旧操作未退出前不向同一个播放器装入另一份媒体。
    final previous = _mediaTail;
    final done = Completer<void>();
    _mediaTail = done.future;
    bool current() =>
        !_disposed &&
        mounted &&
        generation == _playGeneration &&
        !cancel.isCancelled;
    try {
      await previous;
      if (!current()) return false;
      for (final subscription in _activitySubscriptions) {
        await subscription.cancel();
      }
      _activitySubscriptions.clear();
      if (!current()) return false;
      setState(() {
        _player = null;
        _videoController = null;
      });
      _activity.value = false;
      if (!current()) return false;
      var error = '', started = false;
      final headers = <String, String>{};
      if (media['headers'] is Map) {
        for (final entry in (media['headers'] as Map).entries) {
          if (entry.key is String && entry.value is String)
            headers[entry.key as String] = entry.value as String;
        }
      }
      setState(() {
        playingCode = episode.code;
        playingNumber = episode.number;
      });
      if (!kIsWeb) {
        if (!mounted) return false;
        _nativePlayer ??= context.read<PlayerController>();
        _nativeView ??= context.read<VideoPageController>();
        _nativeView!.fullscreen.attach(ModalRoute.of(context)!);
        await _nativePlayer!.bindSourceControls(
          media['url'] as String,
          headers['Referer'] ?? headers['referer'] ?? '',
          canInstall: current,
        );
        if (!current()) return false;
        final index = episodes.indexWhere(
          (e) => e.code == episode.code && e.number == episode.number,
        );
        if (index < 0) return false;
        _nativeView!.bindSourcePlayer(
          SourcePlayerContext(
            identity: 'miomedia:${video.id}',
            title: video.title,
            sourceName: line!.label,
            artworkUrl: video.poster.isNotEmpty ? video.poster : video.cover,
            referer: headers['Referer'] ?? headers['referer'] ?? '',
          ),
          [
            Road(
              name: line!.label,
              data: episodes
                  .map((e) => 'miomedia:${video.id}:${e.code}:${e.number}')
                  .toList(),
              identifier: episodes.map((e) => e.label).toList(),
            ),
          ],
          VideoEpisodeSelection(episode: index + 1, road: 0),
        );
      }
      final player = await _mediaSession.open(
        media['url'] as String,
        headers,
        videoSourceFormat: media['format'] == 'm3u8' || media['format'] == 'hls'
            ? VideoSourceFormat.hls
            : VideoSourceFormat.auto,
        canInstall: current,
        onError: (message) {
          if (!current()) return;
          error = message;
          if (started) setState(() => playMessage = '媒体加载失败，请检查网络或切换线路');
        },
      );
      if (player == null || !current()) return false;
      setState(() {
        _player = player;
        _videoController = _mediaSession.controller;
      });
      _activitySubscriptions.addAll([
        player.stream.playing.listen((_) => _updateActivity()),
        player.stream.buffering.listen((_) => _updateActivity()),
        player.stream.position.listen((_) => _updateActivity()),
      ]);
      final url = _mediaSession.mediaUrl;
      final clock = Stopwatch()..start();
      while (current() && clock.elapsed < const Duration(seconds: 25)) {
        final state = player.state;
        final selected = state.playlist.medias.any((m) => m.uri == url);
        final hasVideo =
            selected && (state.width ?? 0) > 0 && (state.height ?? 0) > 0;
        if (hasVideo && state.position > const Duration(milliseconds: 200)) {
          started = true;
          _updateActivity();
          return true;
        }
        if (error.isNotEmpty && clock.elapsed > const Duration(seconds: 2))
          return false;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!current()) return false;
      // 媒体已就绪却暂停时，保留用户点击继续的路径，不把暂停误判为来源失败。
      final state = player.state;
      if (error.isEmpty &&
          !state.playing &&
          (state.width ?? 0) > 0 &&
          state.duration > Duration.zero)
        return null;
      return false;
    } finally {
      done.complete();
    }
  }

  void showDescription(BuildContext pageContext) {
    final colors = Theme.of(pageContext).colorScheme;
    showModalBottomSheet<void>(
      context: pageContext,
      backgroundColor: colors.surface,
      barrierColor: Colors.black.withValues(alpha: .65),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        video.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭简介',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  video.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  video.description.isEmpty ? '暂无简介' : video.description,
                  style: const TextStyle(fontSize: 14, height: 1.65),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<MioEpisode> get inlineEpisodes {
    final current = episodes.indexWhere(
      (e) => e.code == playingCode && e.number == playingNumber,
    );
    final start = current > 3 ? current - 3 : 0;
    return episodes.skip(start).take(12).toList();
  }

  Widget episodeButton(
    MioEpisode episode, {
    _EpisodeCardSize size = _EpisodeCardSize.compact,
  }) => _MioEpisodeButton(
    episode: episode,
    size: size,
    selected: playingCode == episode.code && playingNumber == episode.number,
    activity: _activity,
    onPressed: () => play(episode),
  );

  void showEpisodes(BuildContext pageContext) {
    final colors = Theme.of(pageContext).colorScheme;
    // 弹层只调整显示顺序；点击始终传回真实线路与剧集编号。
    final ascending = List<MioEpisode>.of(episodes);
    var descending = false;
    final currentIndex = ascending.indexWhere(
      (e) => e.code == playingCode && e.number == playingNumber,
    );
    var segment = currentIndex < 0 ? 0 : currentIndex ~/ 50;
    showModalBottomSheet<void>(
      context: pageContext,
      backgroundColor: colors.surface,
      barrierColor: Colors.black.withValues(alpha: .65),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final ordered = descending ? ascending.reversed.toList() : ascending;
          final groups = (ordered.length / 50).ceil();
          final visible = ordered.skip(segment * 50).take(50).toList();
          final textScale = MediaQuery.textScalerOf(context);
          final columns =
              (MediaQuery.sizeOf(context).width / (82 * textScale.scale(1)))
                  .floor()
                  .clamp(2, 6);
          final tileHeight = 48 + (textScale.scale(12) - 12).clamp(0, 24);
          final width = MediaQuery.sizeOf(context).width - 32;
          final tileWidth = (width - 8 * (columns - 1)) / columns;
          final rows = _episodeRows(
            context,
            visible,
            width,
            tileWidth,
            columns,
          );
          final hasWide = rows.any(
            (row) => row.size != _EpisodeCardSize.compact,
          );
          // 单集作品采用紧凑弹层；长篇保留较高弹层与独立网格滚动。
          final contentHeight =
              (190 +
                      rows.fold<double>(
                        0,
                        (height, row) =>
                            height + _episodeHeight(context, row.size) + 8,
                      ) +
                      (groups > 1 ? 48 : 0))
                  .clamp(0, MediaQuery.sizeOf(context).height * .8)
                  .toDouble();
          return ModernHomeScope(
            child: SafeArea(
              child: SizedBox(
                height: contentHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '全部选集',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => update(() {
                              descending = !descending;
                              segment = 0;
                            }),
                            child: Text(descending ? '降序' : '升序'),
                          ),
                          if (playingCode == line?.code &&
                              playingNumber != null)
                            IconButton(
                              tooltip: '定位当前集',
                              onPressed: () => update(() {
                                final index = ordered.indexWhere(
                                  (e) => e.number == playingNumber,
                                );
                                if (index >= 0) segment = index ~/ 50;
                              }),
                              icon: Icon(
                                Icons.my_location,
                                size: 20,
                                color: colors.primary,
                              ),
                            ),
                          IconButton(
                            tooltip: '关闭选集',
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${line?.label ?? ''} · 共 ${ascending.length} 集',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (groups > 1)
                        _MioEpisodeSegments(
                          labels: [
                            for (var i = 0; i < groups; i++)
                              '${ordered[i * 50].number}–${ordered[((i + 1) * 50).clamp(1, ordered.length) - 1].number}',
                          ],
                          selected: segment,
                          onChanged: (index) => update(() => segment = index),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: hasWide
                            ? ListView.separated(
                                key: ValueKey(
                                  'mio-episode-rows-$segment-$descending',
                                ),
                                itemCount: rows.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  Widget button(MioEpisode episode) =>
                                      _MioEpisodeButton(
                                        episode: episode,
                                        activity: _activity,
                                        size: row.size,
                                        selected:
                                            episode.code == playingCode &&
                                            episode.number == playingNumber,
                                        onPressed: () {
                                          Navigator.of(sheetContext).pop();
                                          unawaited(play(episode));
                                        },
                                      );
                                  return _episodeRow(row, button);
                                },
                              )
                            : GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: tileHeight.toDouble(),
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                    ),
                                itemCount: visible.length,
                                itemBuilder: (context, index) {
                                  final episode = visible[index];
                                  return _MioEpisodeButton(
                                    episode: episode,
                                    activity: _activity,
                                    selected:
                                        episode.code == playingCode &&
                                        episode.number == playingNumber,
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      unawaited(play(episode));
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _detailGeneration++;
    _episodesGeneration++;
    _playGeneration++;
    _detailCancel?.cancel();
    _episodesCancel?.cancel();
    _playCancel?.cancel();
    _playback.dispose();
    for (final subscription in _activitySubscriptions) {
      unawaited(subscription.cancel());
    }
    _activity.dispose();
    _keyboardFocus.dispose();
    unawaited(_mediaTail.then((_) => _mediaSession.dispose()));
    if (widget.service == null) service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    // 页面操作必须拿到深色 Theme 下的上下文，弹层才能捕获相同主题。
    child: Builder(
      builder: (context) {
        if (_nativeView == null) return _buildPage(context);
        return Observer(
          builder: (_) {
            final fullscreen = _nativeView?.isFullscreen == true;
            final pip = _nativeView?.isPip == true;
            if (_nativePlayer != null &&
                _videoController != null &&
                (fullscreen || pip)) {
              return VideoSystemBars(
                fullscreen: fullscreen,
                isPip: pip,
                child: Scaffold(body: _nativePlayerSurface(fillsWindow: true)),
              );
            }
            return _buildPage(context);
          },
        );
      },
    ),
  );

  Widget _nativePlayerSurface({required bool fillsWindow}) => PlayerItem(
    key: _nativeSurfaceKey,
    playerController: _nativePlayer!,
    videoPageController: _nativeView!,
    fillsWindow: fillsWindow,
    keyboardFocus: _keyboardFocus,
    changeEpisode: (index, {int currentRoad = 0, int offset = 0}) async {
      if (index > 0 && index <= episodes.length) {
        await play(episodes[index - 1]);
      }
    },
    onBackPressed: () {
      if (_nativeView!.isFullscreen) {
        unawaited(_nativeView!.fullscreen.setFullscreen(false));
      } else {
        Navigator.of(context).maybePop();
      }
    },
    pauseForTimedShutdown: () => unawaited(_nativePlayer!.pause()),
  );

  Widget _buildPage(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              ConstrainedBox(
                // 横屏时给资料/选集保留可滚动空间，避免播放器挤出视口。
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .65,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_videoController != null)
                        kIsWeb
                            ? WebPlayerSurface(
                                controller: _videoController!,
                                onNext: () {
                                  final index = episodes.indexWhere(
                                    (episode) =>
                                        episode.code == playingCode &&
                                        episode.number == playingNumber,
                                  );
                                  if (index >= 0 &&
                                      index + 1 < episodes.length) {
                                    unawaited(play(episodes[index + 1]));
                                  }
                                },
                              )
                            : _nativePlayerSurface(fillsWindow: false)
                      else
                        LayoutBuilder(
                          builder: (context, size) => Stack(
                            fit: StackFit.expand,
                            children: [
                              if (video.poster.isNotEmpty ||
                                  video.cover.isNotEmpty)
                                NetworkImgLayer(
                                  src: video.poster.isNotEmpty
                                      ? video.poster
                                      : video.cover,
                                  width: size.maxWidth,
                                  height: size.maxHeight,
                                ),
                              const ColoredBox(color: Color(0x66000000)),
                              Center(
                                child: IconButton.filled(
                                  tooltip: '播放所选线路第一集',
                                  onPressed: episodes.isEmpty || playingLoading
                                      ? null
                                      : () => play(episodes.first),
                                  icon: const Icon(Icons.play_arrow, size: 34),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (playingLoading)
                        const Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xcc11141c),
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: LoadingIndicator(
                                size: 38,
                                semanticsLabel: '正在解析并加载视频',
                              ),
                            ),
                          ),
                        ),
                      if (_videoController != null &&
                          playMessage != null &&
                          !playingLoading &&
                          _requestedEpisode != null &&
                          _requestedEpisode!.code == line?.code)
                        Center(
                          child: IconButton.filled(
                            tooltip: '重试当前集',
                            onPressed: () => play(_requestedEpisode!),
                            icon: const Icon(Icons.replay_rounded, size: 28),
                          ),
                        ),
                      if (kIsWeb || _videoController == null)
                        Positioned(
                          left: 8,
                          top: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const ModernBackButton(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: loadDetail,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              video.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => showDescription(context),
                            child: const Text('简介 ›'),
                          ),
                        ],
                      ),
                      Text(
                        video.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (detailError != null)
                        Row(
                          children: [
                            Expanded(child: Text(detailError!)),
                            TextButton(
                              onPressed: loadDetail,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      if (playMessage != null)
                        _MioPlaybackNotice(
                          message: playMessage!,
                          onRetry:
                              playingLoading ||
                                  _requestedEpisode == null ||
                                  _requestedEpisode!.code != line?.code
                              ? null
                              : () => play(_requestedEpisode!),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '播放线路',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (video.lines.isNotEmpty)
                            Text(
                              '${video.lines.length} 条线路',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (detailLoading && video.lines.isEmpty)
                        const SkeletonEpisodes(),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final candidate in video.lines)
                            ChoiceChip(
                              label: Text(
                                candidate.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: line?.code == candidate.code,
                              onSelected: (_) {
                                if (line?.code != candidate.code) {
                                  selectLine(candidate);
                                }
                              },
                              selectedColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              labelStyle: TextStyle(
                                color: line?.code == candidate.code
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              checkmarkColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              side: BorderSide(
                                color: line?.code == candidate.code
                                    ? Theme.of(context).colorScheme.primary
                                          .withValues(alpha: .45)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                        ],
                      ),
                      if (video.lines.isEmpty &&
                          !detailLoading &&
                          detailError == null)
                        const Text('该作品暂无播放线路'),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '选集',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: episodes.isEmpty
                                ? null
                                : () => showEpisodes(context),
                            child: Text(
                              '全部 ${episodes.length}集 ›',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (episodesLoading && episodes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: SkeletonEpisodes(),
                        ),
                      if (episodesError != null)
                        Row(
                          children: [
                            Expanded(child: Text(episodesError!)),
                            TextButton(
                              onPressed: line == null
                                  ? null
                                  : () => selectLine(line!),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, bounds) {
                          final columns =
                              ((bounds.maxWidth + 8) /
                                      (104 *
                                          (MediaQuery.textScalerOf(
                                                context,
                                              ).scale(12) /
                                              12)))
                                  .floor()
                                  .clamp(2, 6);
                          final tileWidth =
                              (bounds.maxWidth - 8 * (columns - 1)) / columns;
                          final rows = _episodeRows(
                            context,
                            inlineEpisodes,
                            bounds.maxWidth,
                            tileWidth,
                            columns,
                          );
                          return Column(
                            children: [
                              for (var i = 0; i < rows.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                _episodeRow(
                                  rows[i],
                                  (episode) => episodeButton(
                                    episode,
                                    size: rows[i].size,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      if (!episodesLoading &&
                          episodes.isEmpty &&
                          episodesError == null &&
                          line != null)
                        const Text('该线路暂无剧集'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _episodeLabel(MioEpisode episode) =>
    '${episode.vip ? 'VIP · ' : ''}${episode.label}';

enum _EpisodeCardSize { compact, half, full }

_EpisodeCardSize _episodeSize(
  BuildContext context,
  MioEpisode episode,
  double width,
  double tileWidth,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: _episodeLabel(episode),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // 预留两侧间距与播放标记，选中后也不截断或跳动布局。
  final textWidth = painter.width;
  painter.dispose();
  // 日期/特辑类名称超过八字时至少用半行卡片，避免在宽屏里又挤回小格子。
  if (episode.label.runes.length <= 8 && textWidth <= tileWidth - 40) {
    return _EpisodeCardSize.compact;
  }
  if (textWidth <= (width - 8) / 2 - 40) return _EpisodeCardSize.half;
  return _EpisodeCardSize.full;
}

double _episodeHeight(BuildContext context, _EpisodeCardSize size) =>
    size == _EpisodeCardSize.full
    ? (MediaQuery.textScalerOf(context).scale(12) * 2.8 + 20).clamp(
        64,
        double.infinity,
      )
    : size == _EpisodeCardSize.half
    ? 56
    : 48 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24);

class _EpisodeRow {
  const _EpisodeRow(this.size, this.columns, this.episodes);
  final _EpisodeCardSize size;
  final int columns;
  final List<MioEpisode> episodes;
}

Widget _episodeRow(_EpisodeRow row, Widget Function(MioEpisode) button) => Row(
  children: [
    for (var i = 0; i < row.columns; i++) ...[
      if (i > 0) const SizedBox(width: 8),
      Expanded(
        child: i < row.episodes.length
            ? button(row.episodes[i])
            : const SizedBox(),
      ),
    ],
  ],
);

List<_EpisodeRow> _episodeRows(
  BuildContext context,
  List<MioEpisode> episodes,
  double width,
  double tileWidth,
  int columns,
) {
  final rows = <_EpisodeRow>[];
  var current = <MioEpisode>[];
  var size = _EpisodeCardSize.compact;
  int count(_EpisodeCardSize size) => switch (size) {
    _EpisodeCardSize.compact => columns,
    _EpisodeCardSize.half => 2,
    _EpisodeCardSize.full => 1,
  };
  void flush() {
    if (current.isNotEmpty) {
      rows.add(_EpisodeRow(size, count(size), current));
      current = [];
    }
  }

  for (final episode in episodes) {
    final next = _episodeSize(context, episode, width, tileWidth);
    if (next != size) flush();
    size = next;
    current.add(episode);
    if (current.length == count(size)) flush();
  }
  flush();
  return rows;
}

class _MioEpisodeSegments extends StatefulWidget {
  const _MioEpisodeSegments({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  State<_MioEpisodeSegments> createState() => _MioEpisodeSegmentsState();
}

class _MioEpisodeSegmentsState extends State<_MioEpisodeSegments>
    with TickerProviderStateMixin {
  TabController? _tabs;
  bool? _reduceMotion;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _tabs?.dispose();
    _tabs = TabController(
      length: widget.labels.length,
      initialIndex: widget.selected,
      vsync: this,
      animationDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
    );
  }

  @override
  void didUpdateWidget(covariant _MioEpisodeSegments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs!.index != widget.selected) {
      _tabs!.animateTo(
        widget.selected,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: TabBar(
        key: const ValueKey('mio-episode-segments'),
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 6,
        ),
        indicator: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.primary.withValues(alpha: .35)),
        ),
        automaticIndicatorColorAdjustment: false,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        onTap: widget.onChanged,
        tabs: [
          for (final label in widget.labels)
            Tab(
              height: 48,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 88),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: Text(label)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 页面内与弹层共用剧集样式；长名称单独占一行，最多显示两行。
class _MioEpisodeButton extends StatelessWidget {
  const _MioEpisodeButton({
    required this.episode,
    required this.selected,
    required this.onPressed,
    this.activity,
    this.size = _EpisodeCardSize.compact,
  });
  final MioEpisode episode;
  final bool selected;
  final VoidCallback onPressed;
  final ValueListenable<bool>? activity;
  final _EpisodeCardSize size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expanded = size == _EpisodeCardSize.full;
    final wide = size != _EpisodeCardSize.compact;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, _episodeHeight(context, size)),
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 12 : 8,
          vertical: expanded ? 10 : 0,
        ),
        foregroundColor: selected ? colors.primary : colors.onSurface,
        backgroundColor: selected
            ? colors.surfaceContainerHighest
            : colors.surfaceContainerLow,
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: wide
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          if (selected) ...[
            if (activity == null)
              MioPlayingMark(active: false, color: colors.primary)
            else
              ValueListenableBuilder<bool>(
                valueListenable: activity!,
                builder: (_, active, _) =>
                    MioPlayingMark(active: active, color: colors.primary),
              ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              '${episode.vip ? 'VIP · ' : ''}${episode.label}',
              maxLines: expanded ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _MioPlaybackNotice extends StatelessWidget {
  const _MioPlaybackNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('miomedia-playback-notice'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
