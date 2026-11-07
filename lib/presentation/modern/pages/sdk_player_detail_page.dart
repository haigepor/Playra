import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/app_brand.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';
import 'package:kazumi/pages/video/video_system_bars.dart';
import 'package:kazumi/services/platform/video_fullscreen_mode.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/player/source_media_player.dart';
import 'package:kazumi/services/player/web_player_surface.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_coordinator.dart';
import 'package:kazumi/services/source/prepared_playback.dart';
import 'package:kazumi/services/source/source_display_names.dart';
import 'package:kazumi/services/source/sdk_playback_resume.dart';
import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/widgets/playra_sheet.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import '../player/playing_mark.dart';
import '../player/player_theme.dart';
import '../settings/modern_back_button.dart';
import '../player/sdk_source_widgets.dart';
import '../player/sdk_quality_selector.dart';
import '../player/sdk_playback_notice.dart';
import '../player/portrait_episode_pager.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

/// 来源作品有独立个人库身份，不创建伪造的Bangumi或弹幕上下文。
class SdkDetailPage extends StatefulWidget {
  const SdkDetailPage({super.key, required this.entry, this.library});
  final SdkPlaybackEntry entry;
  final SdkLibraryStore? library;
  @override
  State<SdkDetailPage> createState() => _SdkDetailPageState();
}

class _SdkDetailPageState extends State<SdkDetailPage>
    with WidgetsBindingObserver {
  SdkLibraryStore get _library => widget.library ?? SdkLibraryStore.shared;
  SdkWatchProgress? _initialResume;
  SdkEpisode? _recordEpisode;
  SdkVideo? _recordVideo;
  String? _recordProvider;
  bool _recordAutomatic = true;
  String? _recordQuality;
  Timer? _historyTimer;
  String? _storageError;
  bool _collectBusy = false;
  String? _lastSavedState;
  final _historySeekGuard = SdkResumeProgressGuard();
  bool _recordStarted = false, _recordRestoreHandled = true;
  Duration _recordResumeAt = Duration.zero,
      _recordResumeDuration = Duration.zero;
  int _recordEpoch = 0;
  String? _recordMediaUrl;
  late SdkSourceBinding source = widget.entry.sources.first;
  late SdkVideo video =
      source.seed ??
      SdkVideoData(
        id: source.contentId,
        title: widget.entry.title,
        cover: widget.entry.cover,
      );
  SdkPlaybackProvider get service => source.provider;
  SdkPlaybackCoordinator? _coordinator;
  SdkPlaybackCoordinator get _playback =>
      _coordinator ??= SdkPlaybackCoordinator(
        source.contentId,
        service,
        singleMovie: video.singleMovie,
        onChanged: _metadataChanged,
      );
  bool automatic = true;
  // 线路锁与画质锁分别保存；恢复自动画质不能解除手动线路。
  String? _manualQualityCode;
  String? _activeSdkId, _activeLineCode;
  String? _installedSdkId, _installedLineCode;
  SdkQuality? selectedQuality;
  String? resumeNotice;
  int _selectionGeneration = 0;
  String? decodedResolution;
  VoidCallback? _refreshLineSheet;

  void _metadataChanged() {
    if (!mounted || _disposed) return;
    setState(() {});
    _refreshLineSheet?.call();
  }

  SdkLine? line;
  List<SdkEpisode> episodes = [];
  CancelToken? _detailCancel, _episodesCancel, _playCancel;
  int _detailGeneration = 0, _episodesGeneration = 0, _playGeneration = 0;
  bool detailLoading = false, episodesLoading = false, playingLoading = false;
  String? detailError, episodesError, playMessage;
  String? playingCode;
  String? playingIdentity;
  SdkEpisode? _requestedEpisode;
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
  bool _hasPlayIntent = false;
  bool _preparingOnly = false;
  PreparedPlayback? _prepared;
  Future<void>? _preparationFuture;
  Stopwatch? _initialResolution;

  SdkLineCandidate? get _qualityCandidate {
    final target = _requestedEpisode;
    if (target == null) return null;
    return _playback.candidates
        .where(
          (item) =>
              item.line.code == target.code &&
              (item.episode == null ||
                  item.episode?.identityKey == target.identityKey),
        )
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library.addListener(_metadataChanged);
    _initialResume = _library.get(service.id, source.contentId)?.lastWatch;
    automatic = _initialResume?.automatic ?? true;
    _manualQualityCode = _initialResume?.qualityCode;
    _historyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
    unawaited(loadDetail());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveProgress();
  }

  void _saveProgress() {
    final episode = _recordEpisode,
        savedVideo = _recordVideo,
        provider = _recordProvider;
    final state = _player?.state;
    if (episode == null ||
        savedVideo == null ||
        provider == null ||
        state == null) {
      return;
    }
    if (!state.playlist.medias.any((media) => media.uri == _recordMediaUrl))
      return;
    // HLS的尺寸回报可能晚于播放时钟；正进度和已知时长足以确认实际播放。
    if (!_recordStarted) {
      if (state.position < const Duration(milliseconds: 200) ||
          state.duration <= Duration.zero)
        return;
      _recordStarted = true;
    }
    if (!_recordRestoreHandled && state.duration > Duration.zero) {
      _recordRestoreHandled = true;
      if (_recordResumeAt > Duration.zero) {
        final offset = sdkResumePosition(
          position: _recordResumeAt,
          previousDuration: _recordResumeDuration,
          targetDuration: state.duration,
        );
        if (offset != null) {
          final player = _player!, epoch = _recordEpoch;
          _historySeekGuard.waitFor(offset);
          unawaited(
            player
                .seek(offset)
                .then((_) {
                  if (!_disposed && epoch == _recordEpoch) _saveProgress();
                })
                .catchError((Object _) {
                  if (mounted && !_disposed && epoch == _recordEpoch) {
                    setState(() => resumeNotice = '进度恢复失败，可手动拖动重试');
                  }
                }),
          );
          return;
        }
        if (mounted && !_disposed)
          setState(() => resumeNotice = '线路版本时长不同，已从头播放');
      }
    }
    if (!_historySeekGuard.accepts(state.position)) return;
    final savedState =
        '$provider:${savedVideo.id}:${episode.code}:${episode.identityKey}:${state.position.inMilliseconds}:${state.duration.inMilliseconds}:$_recordAutomatic:$_recordQuality';
    if (_lastSavedState == savedState) return;
    _lastSavedState = savedState;
    // 使用已装入媒体的快照，准备下一集期间不能把旧进度写入新集。
    unawaited(
      _library
          .record(
            providerId: provider,
            video: savedVideo,
            episode: episode,
            position: state.position,
            duration: state.duration,
            automatic: _recordAutomatic,
            qualityCode: _recordQuality,
          )
          .catchError((Object _) {
            if (_lastSavedState == savedState) _lastSavedState = null;
            if (mounted && !_disposed) {
              setState(() => _storageError = '观看进度保存失败，请检查本地存储');
            }
          }),
    );
  }

  Future<void> _collect(int type) async {
    if (_collectBusy) return;
    setState(() => _collectBusy = true);
    try {
      await _library.collect(providerId: service.id, video: video, type: type);
      if (mounted) setState(() => _storageError = null);
    } catch (_) {
      if (mounted) setState(() => _storageError = '收藏保存失败，请重试');
    } finally {
      if (mounted) setState(() => _collectBusy = false);
    }
  }

  Future<void> loadDetail({
    SdkEpisode? retainedEpisode,
    bool retainedSingleMovie = false,
    Duration resumeAt = Duration.zero,
    Duration resumeDuration = Duration.zero,
    bool? resumePlaying,
  }) async {
    _initialResolution = AppBuildPolicy.developerTools
        ? (Stopwatch()..start())
        : null;
    final initialResume = _initialResume;
    _initialResume = null;
    retainedEpisode ??= _requestedEpisode ?? initialResume?.episode;
    _requestedEpisode = retainedEpisode;
    _detailCancel?.cancel();
    final cancel = _detailCancel = CancelToken();
    final generation = ++_detailGeneration;
    final selection = _selectionGeneration;
    bool current() =>
        mounted &&
        generation == _detailGeneration &&
        !cancel.isCancelled &&
        selection == _selectionGeneration;
    setState(() {
      detailLoading = true;
      detailError = null;
    });
    try {
      final result = await service.detail(source.contentId, cancel: cancel);
      if (!current()) {
        return;
      }
      _coordinator?.dispose();
      _coordinator = null;
      setState(() => video = result);
      if (result.lines.isNotEmpty) {
        if (initialResume != null &&
            !initialResume.automatic &&
            !result.lines.any(
              (candidate) => candidate.code == initialResume.episode.code,
            )) {
          setState(() => playMessage = '上次锁定的线路已不可用，请手动选择线路');
          return;
        }
        // 首次目录直接并发探测，首条慢线路不阻塞其他线路进入候选。
        final initial = await _playback.prepare(
          retainedEpisode,
          result.lines,
          cancel,
          confirmedSingleMovie: retainedSingleMovie && result.singleMovie,
        );
        if (!current()) return;
        final available = initial
            .where((item) => item.episode != null)
            .firstOrNull;
        final preferred = initialResume == null
            ? null
            : initial
                  .where(
                    (item) =>
                        item.line.code == initialResume.episode.code &&
                        item.episode != null,
                  )
                  .firstOrNull;
        final directory = preferred ?? available ?? initial.firstOrNull;
        if (directory != null) await _loadLine(directory.line);
        if (retainedEpisode != null && current()) {
          final target = SdkPlaybackCoordinator.match(
            retainedEpisode,
            episodes,
            singleMovie: retainedSingleMovie && result.singleMovie,
          );
          if (target == null) {
            setState(() => playMessage = '该来源没有对应当前集，请选择剧集或其他来源');
          } else {
            unawaited(
              _hasPlayIntent
                  ? play(
                      target,
                      resumeAt: resumeAt,
                      resumeDuration: resumeDuration,
                      resumePlaying: resumePlaying,
                    )
                  : prepare(target),
            );
          }
          return;
        }
        if (current() && episodes.isNotEmpty) {
          final initial = episodes.firstWhere(
            (e) => e.number == 1,
            orElse: () => episodes.firstWhere(
              (e) => e.number != null,
              orElse: () => episodes.first,
            ),
          );
          unawaited(prepare(initial));
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

  Future<bool> _loadLine(SdkLine selected) async {
    // 切线路作废尚未完成的播放请求，不把旧线路解析结果装到新选择上。
    _playCancel?.cancel();
    _playGeneration++;
    _prepared = null;
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
        return false;
      }
      setState(() => episodes = result);
      return true;
    } catch (_) {
      if (mounted && generation == _episodesGeneration && !cancel.isCancelled) {
        setState(() => episodesError = '剧集加载失败，请重试');
      }
      return false;
    } finally {
      if (mounted && generation == _episodesGeneration) {
        setState(() => episodesLoading = false);
      }
    }
  }

  Future<void> selectLine(SdkLine selected) async {
    final selection = ++_selectionGeneration;
    _detailCancel?.cancel('manual selection');
    final previous = _requestedEpisode;
    final previousSingle = episodes.length == 1;
    final position = _player?.state.position ?? Duration.zero;
    final duration = _player?.state.duration ?? Duration.zero;
    setState(() {
      automatic = false;
      detailLoading = false;
    });
    if (!await _loadLine(selected) ||
        !mounted ||
        selection != _selectionGeneration)
      return;
    final target = previous == null
        ? episodes.firstOrNull
        : SdkPlaybackCoordinator.match(
            previous,
            episodes,
            singleMovie: video.singleMovie && previousSingle,
          ) ??
          (previous.number == null ? episodes.firstOrNull : null);
    if (target == null) {
      setState(
        () => playMessage = episodes.isEmpty
            ? '该线路暂无剧集，可选择其他线路'
            : '该线路没有对应当前集，请选择其他线路',
      );
      return;
    }
    if (_hasPlayIntent) {
      await play(
        target,
        manual: true,
        resumeAt: position,
        resumeDuration: duration,
        resumePlaying: _player?.state.playing,
      );
    } else {
      await prepare(target, manual: true);
    }
  }

  Future<void> switchSource(SdkSourceBinding selected) async {
    final previous = _requestedEpisode;
    final previousSingle = video.singleMovie && episodes.length == 1;
    final position = _player?.state.position ?? Duration.zero;
    final duration = _player?.state.duration ?? Duration.zero;
    final wasPlaying = _player?.state.playing;
    _selectionGeneration++;
    _playCancel?.cancel();
    _playGeneration++;
    _detailCancel?.cancel();
    _episodesCancel?.cancel();
    _coordinator?.dispose();
    _coordinator = null;
    setState(() {
      source = selected;
      video =
          selected.seed ??
          SdkVideoData(
            id: selected.contentId,
            title: widget.entry.title,
            cover: widget.entry.cover,
          );
      line = null;
      episodes = [];
      _requestedEpisode = previous;
      selectedQuality = null;
      _manualQualityCode = null;
      decodedResolution = null;
      automatic = true;
      _prepared = null;
    });
    await loadDetail(
      retainedEpisode: previous,
      retainedSingleMovie: previousSingle,
      resumeAt: position,
      resumeDuration: duration,
      resumePlaying: wasPlaying,
    );
  }

  Future<void> play(
    SdkEpisode episode, {
    bool? manual,
    Duration resumeAt = Duration.zero,
    Duration resumeDuration = Duration.zero,
    bool? resumePlaying,
    bool preservePlayback = false,
  }) async {
    final saved = _library
        .get(service.id, source.contentId)
        ?.progressFor(episode);
    if (!preservePlayback &&
        resumeAt == Duration.zero &&
        (playingIdentity != episode.identityKey ||
            _installedSdkId != service.id)) {
      resumeAt = saved?.completed == true
          ? Duration.zero
          : saved?.position ?? Duration.zero;
      resumeDuration = saved?.duration ?? Duration.zero;
    }
    _hasPlayIntent = true;
    // 点击准备中的同一集共用请求；换集/换源后，旧点击不能打开迟到结果。
    if (playingLoading &&
        _preparingOnly &&
        _requestedEpisode?.code == episode.code &&
        _requestedEpisode?.identityKey == episode.identityKey) {
      final generation = _playGeneration;
      await _preparationFuture;
      if (!mounted || _disposed || generation != _playGeneration) return;
    }
    return _resolveOrPlay(
      episode,
      openMedia: true,
      manual: manual,
      resumeAt: resumeAt,
      resumeDuration: resumeDuration,
      resumePlaying: resumePlaying,
      preservePlayback: preservePlayback,
    );
  }

  Future<void> prepare(SdkEpisode episode, {bool? manual}) {
    final future = _resolveOrPlay(episode, openMedia: false, manual: manual);
    _preparationFuture = future;
    return future;
  }

  Future<void> selectEpisode(SdkEpisode episode) =>
      _hasPlayIntent ? play(episode) : prepare(episode);

  void _retryPlayback() {
    final target = _requestedEpisode;
    if (target == null || target.code != line?.code) return;
    unawaited(
      _hasPlayIntent ? play(target, preservePlayback: true) : prepare(target),
    );
  }

  Future<void> selectQuality(String? code) async {
    final target = _requestedEpisode;
    if (target == null || line?.code != target.code) return;
    if (code != null &&
        _qualityCandidate?.qualities.any(
              (q) => q.code == code && q.height != null,
            ) !=
            true) {
      return;
    }
    if (_manualQualityCode == code &&
        !playingLoading &&
        playMessage == null &&
        _qualityCandidate?.qualityStatus == 'ready') {
      return;
    }
    final state = _player?.state;
    _detailCancel?.cancel('quality selected');
    _playCancel?.cancel('quality selected');
    _playGeneration++;
    setState(() {
      _manualQualityCode = code;
      detailLoading = false;
      // 不等待旧档位的准备请求；新 generation 独立负责当前选择。
      playingLoading = false;
    });
    if (_hasPlayIntent) {
      await play(
        target,
        manual: true,
        preservePlayback: true,
        resumeAt: state?.position ?? Duration.zero,
        resumeDuration: state?.duration ?? Duration.zero,
        resumePlaying: state?.playing,
      );
    } else {
      await prepare(target, manual: true);
    }
  }

  Future<void> _resolveOrPlay(
    SdkEpisode episode, {
    required bool openMedia,
    bool? manual,
    Duration resumeAt = Duration.zero,
    Duration resumeDuration = Duration.zero,
    bool? resumePlaying,
    bool preservePlayback = false,
  }) async {
    _selectionGeneration++;
    _playCancel?.cancel();
    final cancel = _playCancel = CancelToken();
    final generation = ++_playGeneration;
    final prepared = _prepared;
    final resolveClock = Stopwatch()..start();
    var materialAttempt = 0;
    void traceMaterials() {
      if (AppBuildPolicy.developerTools) {
        final initial = _initialResolution;
        if (initial != null) {
          debugPrint(
            'PLAYRA_LUMINA ${jsonEncode({'stage': 'initial_line_ready', 'ms': initial.elapsedMilliseconds})}',
          );
          _initialResolution = null;
        }
        debugPrint(
          'PLAYRA_LUMINA ${jsonEncode({'stage': 'line_ready', 'ms': resolveClock.elapsedMilliseconds, 'generation': generation, 'attempt': ++materialAttempt, 'openMedia': openMedia, 'quality': _manualQualityCode ?? 'auto'})}',
        );
      }
    }

    setState(() {
      _requestedEpisode = episode;
      playingLoading = true;
      playMessage = null;
      resumeNotice = null;
      _preparingOnly = !openMedia;
      if (!openMedia) _prepared = null;
    });
    try {
      // 目录/解析仍在准备时保留旧媒体；只有新地址就绪后才交给播放器切换。
      if (!mounted || generation != _playGeneration || cancel.isCancelled) {
        return;
      }
      var attempt = 0;
      var positionToRestore = resumeAt, durationToRestore = resumeDuration;
      var playingToRestore = resumePlaying;
      var capturedAtCommit = false;
      Future<void> onAttempt(
        SdkLine selected,
        SdkEpisode target,
        SdkQuality? quality,
      ) async {
        final items = selected.code == line?.code
            ? episodes
            : await _playback.episodes(selected);
        if (!mounted || generation != _playGeneration || cancel.isCancelled)
          return;
        setState(() {
          line = selected;
          episodes = items;
          _requestedEpisode = target;
          selectedQuality = quality;
          playMessage = attempt++ == 0 ? null : '正在尝试${selected.label}…';
        });
      }

      final result = openMedia
          ? await _playback.playAutomatic(
              episode,
              video.lines,
              cancel: cancel,
              manual: manual ?? !automatic,
              qualityCode: _manualQualityCode,
              onAttempt: onAttempt,
              prepared: prepared,
              open: (target, media, attemptCancel) {
                traceMaterials();
                // 同集换画质在提交新媒体前读取最新进度，避免解析期间发生倒退。
                if (preservePlayback && !capturedAtCommit) {
                  capturedAtCommit = true;
                  if (_installedSdkId == service.id &&
                      playingCode == episode.code &&
                      playingIdentity == episode.identityKey) {
                    final state = _player?.state;
                    if (state != null) {
                      positionToRestore = state.position;
                      durationToRestore = state.duration;
                      playingToRestore = state.playing;
                    }
                  }
                }
                return _openMedia(
                  target,
                  media,
                  generation,
                  attemptCancel,
                  selectionClock: resolveClock,
                  resumeAt: positionToRestore,
                  resumeDuration: durationToRestore,
                  resumePlaying: playingToRestore,
                );
              },
            )
          : await _playback.preparePlayback(
              episode,
              video.lines,
              cancel: cancel,
              manual: manual ?? !automatic,
              qualityCode: _manualQualityCode,
              onAttempt: onAttempt,
            );
      if (!mounted || generation != _playGeneration || cancel.isCancelled) {
        return;
      }
      if (!openMedia && result.status == 'prepared') traceMaterials();
      if (result.status == 'ready') {
        _activeSdkId = service.id;
        _activeLineCode = line?.code;
      }
      setState(() {
        _prepared = result.prepared;
        playMessage = switch (result.status) {
          'ready' || 'prepared' => null,
          'interaction_required' => '点击播放器继续播放',
          'ad_required' => '来源平台仍要求广告校验，请重试或切换线路。',
          'identity_mismatch' => '播放资源与所选剧集不匹配',
          'invalid_media' => '播放资源地址无效',
          _ => switch (result.errorCode) {
            'UPSTREAM_LIMIT' => '上游解析服务今日配额已满，请切换其他线路。',
            'PARSER' => '该线路解析失败，请尝试切换其他线路。',
            'PARAM_INCOMPLETE' => '线路解析参数不完整，请重试或切换线路。',
            'PROTOCOL' => '内容源协议异常，请重试或切换线路。',
            'NETWORK' => '无法连接到内容源服务器，请检查网络。',
            'BUSINESS_REJECTED' => '内容源服务暂不可用，请切换其他线路。',
            'CORE_REPLY' || 'DECRYPT_ERROR' || 'PARSE_ERROR' => '播放响应解析失败，请重试。',
            'CORE_TIMEOUT' => '播放响应解密超时，请重试。',
            'CLIENT_PARSE_INVALID_RESPONSE' => '该线路解析接口返回了无效数据，请重试或切换线路。',
            'CLIENT_PARSE_NETWORK' || 'TIMEOUT' => '解析请求超时或网络异常，请重试或切换线路。',
            'MEDIA_LOAD_FAILED' => '已取得视频地址，但媒体加载失败，请重试或切换线路。',
            'QUALITY_UNAVAILABLE' => '当前集或线路没有所选画质，请选择其他画质或自动。',
            'CLIENT_PARSE_REJECTED' => '该线路暂未提供可播放地址，可重试或切换线路。',
            'ATTEMPT_BUDGET_EXHAUSTED' =>
              result.untried > 0
                  ? '自动尝试已超时，仍有 ${result.untried} 个候选未试，可手动选择线路。'
                  : '解析或加载已超时，可重试当前线路或手动切换。',
            _ => '暂时无法取得播放资源，可重试或切换线路。',
          },
        };
      });
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
    if (active) {
      _activeSdkId = _installedSdkId;
      _activeLineCode = _installedLineCode;
    }
    // 首帧超时或瞬时媒体错误后仍可能恢复；当前媒体真正播放时撤掉过期的重试遮罩。
    if (active && !playingLoading && playMessage != null) {
      setState(() => playMessage = null);
    }
  }

  Future<bool?> _openMedia(
    SdkEpisode episode,
    Map media,
    int generation,
    CancelToken cancel, {
    Stopwatch? selectionClock,
    Duration resumeAt = Duration.zero,
    Duration resumeDuration = Duration.zero,
    bool? resumePlaying,
  }) async {
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
      _saveProgress();
      _recordEpisode = null;
      _recordEpoch++;
      _recordStarted = false;
      _historySeekGuard.waitFor(Duration.zero);
      for (final subscription in _activitySubscriptions) {
        await subscription.cancel();
      }
      _activitySubscriptions.clear();
      if (!current()) return false;
      setState(() {
        _player = null;
        _videoController = null;
        decodedResolution = null;
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
        playingIdentity = episode.identityKey;
        _installedSdkId = service.id;
        _installedLineCode = episode.code;
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
          (e) => e.code == episode.code && e.identityKey == episode.identityKey,
        );
        if (index < 0) return false;
        _nativeView!.bindSourcePlayer(
          SourcePlayerContext(
            identity: '${service.id}:${video.id}',
            title: video.title,
            sourceName: line!.label,
            artworkUrl: video.poster.isNotEmpty ? video.poster : video.cover,
            referer: headers['Referer'] ?? headers['referer'] ?? '',
          ),
          [
            Road(
              name: line!.label,
              data: episodes
                  .map(
                    (e) =>
                        '${service.id}:${video.id}:${e.code}:${e.identityKey}',
                  )
                  .toList(),
              identifier: episodes.map((e) => e.label).toList(),
            ),
          ],
          VideoEpisodeSelection(episode: index + 1, road: 0),
        );
      }
      final mediaClock = Stopwatch()..start();
      final decryptionKey =
          media['decryptionKey'] is String && (media['decryptionKey'] as String).isNotEmpty
              ? media['decryptionKey'] as String
              : null;
      final player = await _mediaSession.open(
        media['url'] as String,
        headers,
        videoSourceFormat: media['format'] == 'm3u8' || media['format'] == 'hls'
            ? VideoSourceFormat.hls
            : VideoSourceFormat.auto,
        decryptionKey: decryptionKey,
        play: resumePlaying,
        canInstall: current,
        onError: (message) {
          if (!current()) return;
          error = message;
          if (started) setState(() => playMessage = '媒体加载失败，请检查网络或切换线路');
        },
      );
      if (player == null || !current()) {
        if (current() && RegExp(r'\b(?:403|410)\b').hasMatch(error)) {
          throw const SourceException('EXPIRED', '媒体地址已失效');
        }
        return false;
      }
      setState(() {
        _player = player;
        _videoController = _mediaSession.controller;
      });
      if (AppBuildPolicy.developerTools && service.id == 'lumina') {
        final firstFrame =
            _mediaSession.controller?.waitUntilFirstFrameRendered;
        if (firstFrame != null) {
          // Android 库也会在尺寸更新时完成此 Future；该值仅作代理，可见画面另用屏幕采样核验。
          unawaited(
            firstFrame
                .timeout(const Duration(seconds: 25))
                .then((_) {
                  if (current() && identical(_player, player)) {
                    debugPrint(
                      'PLAYRA_LUMINA ${jsonEncode({'stage': 'video_first_frame', 'ms': mediaClock.elapsedMilliseconds, 'selectionMs': selectionClock?.elapsedMilliseconds, 'quality': _manualQualityCode ?? 'auto', 'generation': generation})}',
                    );
                  }
                })
                .catchError((Object _) {}),
          );
        }
      }
      // 先绑定已安装媒体的身份，允许晚出画时仍保存正确作品与分集。
      _recordEpisode = episode;
      _recordVideo = video;
      _recordProvider = service.id;
      _recordAutomatic = automatic;
      _recordQuality = _manualQualityCode;
      _recordMediaUrl = _mediaSession.mediaUrl;
      _recordResumeAt = resumeAt;
      _recordResumeDuration = resumeDuration;
      _recordRestoreHandled = resumeAt <= Duration.zero;
      if (!kIsWeb &&
          resumePlaying != false &&
          _nativePlayer!.playback.autoPlay == false &&
          current()) {
        // 全局关闭自动播放不应吞掉本次明确点击；详情准备阶段从不进入这里。
        await player.play();
        if (!current()) return false;
      }
      _activitySubscriptions.addAll([
        player.stream.playing.listen((_) {
          if (current()) {
            _updateActivity();
            if (!player.state.playing) _saveProgress();
          }
        }),
        player.stream.buffering.listen((_) {
          if (current()) _updateActivity();
        }),
        player.stream.position.listen((_) {
          if (current()) {
            _historySeekGuard.accepts(player.state.position);
            _updateActivity();
          }
        }),
      ]);
      final url = _mediaSession.mediaUrl;
      final clock = Stopwatch()..start();
      while (current() && clock.elapsed < const Duration(seconds: 25)) {
        final state = player.state;
        final selected = state.playlist.medias.any((m) => m.uri == url);
        final hasVideo =
            selected && (state.width ?? 0) > 0 && (state.height ?? 0) > 0;
        if (hasVideo &&
            (state.position > const Duration(milliseconds: 200) ||
                resumePlaying == false && state.duration > Duration.zero)) {
          started = true;
          if (resumeAt > Duration.zero &&
              state.duration > Duration.zero &&
              !_recordRestoreHandled) {
            _recordRestoreHandled = true;
            final offset = sdkResumePosition(
              position: resumeAt,
              previousDuration: resumeDuration,
              targetDuration: state.duration,
            );
            if (offset != null) {
              _historySeekGuard.waitFor(offset);
              await player.seek(offset);
              if (!current()) return false;
            } else {
              setState(() => resumeNotice = '线路版本时长不同，已从头播放');
            }
          }
          if (resumePlaying == false) {
            await player.pause();
            if (!current()) return false;
          }
          if (current()) {
            setState(() {
              final width = SdkQuality.resolution(state.width);
              final height = SdkQuality.resolution(state.height);
              if (width != null && height != null) {
                // 宽银幕电影可能裁掉黑边，不能把 1920×800 简写成低清的“800p”。
                decodedResolution = '$width×$height';
              }
            });
          }
          _updateActivity();
          _recordStarted = true;
          _saveProgress();
          return true;
        }
        if (error.isNotEmpty && clock.elapsed > const Duration(seconds: 2)) {
          if (RegExp(r'\b(?:403|410)\b').hasMatch(error)) {
            throw const SourceException('EXPIRED', '媒体地址已失效');
          }
          return false;
        }
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
    } catch (error) {
      if (current() && RegExp(r'\b(?:403|410)\b').hasMatch('$error')) {
        throw const SourceException('EXPIRED', '媒体地址已失效');
      }
      rethrow;
    } finally {
      // 预算取消只停止本次打开的媒体，避免迟到起播或干扰新选择。
      try {
        if (cancel.isCancelled && mounted && generation == _playGeneration) {
          await _mediaSession.player?.pause();
        }
      } finally {
        done.complete();
      }
    }
  }

  Widget _sourceControls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final saved = _library.get(service.id, source.contentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saved?.lastWatch != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '上次看到 ${saved!.progressLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (_storageError != null)
          Text(_storageError!, style: TextStyle(color: colors.error)),
        // 只保留播放源一行：线路/分辨率/画质这类描述全部移入点击后的弹窗。
        PlaybackSourcePanel(
          selectorKey: const ValueKey('sdk-line-selector'),
          sourceLabel: playbackSourceName(
            service.id,
            service.name,
            anime: video.isAnime,
          ),
          onSelectSource: video.lines.isEmpty ? null : () => showLines(context),
          trailing: PopupMenuButton<int>(
            tooltip: '设置收藏状态',
            enabled: !_collectBusy,
            initialValue: saved?.collectionType ?? 0,
            onSelected: (type) => unawaited(_collect(type)),
            itemBuilder: (_) => [
              for (final type in CollectType.values)
                PopupMenuItem(
                  value: type.value,
                  child: Text(type == CollectType.none ? '取消收藏' : type.label),
                ),
            ],
            icon: Icon(
              saved != null &&
                      CollectType.fromValue(saved.collectionType).isCollected
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        if (video.lines.isEmpty && !detailLoading && detailError == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('该作品暂无播放线路'),
          ),
        if (resumeNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              resumeNotice!,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Future<void> showLines(BuildContext pageContext) async {
    try {
      await showPlayraSheet<void>(
        context: pageContext,
        size: PlayraSheetSize.standard,
        showDragHandle: false,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, update) {
            _refreshLineSheet = () {
              if (context.mounted) update(() {});
            };
            return PlaybackLineSheet(
              sdkName: playbackSourceName(
                service.id,
                service.name,
                anime: video.isAnime,
              ),
              onClose: () => Navigator.of(sheetContext).pop(),
              sources: widget.entry.sources.length < 2
                  ? null
                  : Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final binding in widget.entry.sources)
                          PlaybackSdkChip(
                            name: playbackSourceName(
                              binding.provider.id,
                              binding.provider.name,
                              anime: video.isAnime,
                            ),
                            selected: binding.provider.id == service.id,
                            onSelected: () {
                              if (binding.provider.id != service.id) {
                                Navigator.of(sheetContext).pop();
                                unawaited(switchSource(binding));
                              }
                            },
                          ),
                      ],
                    ),
              // 画质从卡片行移入弹窗：弹窗内选择后关闭并立即切换。
              quality: service.supportsQualities &&
                      episodes.isNotEmpty &&
                      _requestedEpisode != null &&
                      _requestedEpisode?.code == line?.code
                  ? SdkQualitySelector(
                      qualities: [...?_qualityCandidate?.qualities]..sort(
                        (a, b) => service
                            .qualityPreference(b)
                            .compareTo(service.qualityPreference(a)),
                      ),
                      automaticLabel: service.automaticQualityLabel,
                      selectedCode: _manualQualityCode,
                      status: switch (_qualityCandidate?.status) {
                        'timeout' || 'failed' => _qualityCandidate!.status,
                        'loading' => 'loading',
                        _ => _qualityCandidate?.qualityStatus ?? 'loading',
                      },
                      busy: playingLoading,
                      showStatus: playMessage == null,
                      onRetry: playingLoading || playMessage != null
                          ? null
                          : _retryPlayback,
                      onSelected: (code) {
                        Navigator.of(sheetContext).pop();
                        unawaited(selectQuality(code));
                      },
                    )
                  : null,
              automaticOption: SdkLineOption(
                title: '自动（优选线路）',
                subtitle: '在当前 SDK 内选线，保留画质偏好',
                automatic: true,
                selected: automatic,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => automatic = true);
                  final target = _requestedEpisode ?? episodes.firstOrNull;
                  if (target != null)
                    unawaited(
                      _hasPlayIntent
                          ? play(
                              target,
                              resumeAt:
                                  _player?.state.position ?? Duration.zero,
                              resumeDuration:
                                  _player?.state.duration ?? Duration.zero,
                              resumePlaying: _player?.state.playing,
                            )
                          : prepare(target),
                    );
                },
              ),
              children: [
                for (final candidate in video.lines)
                  // 没有对应当前集的线路点了也播不了，不再罗列；
                  // 探测仍在后台跑，匹配成功后弹窗刷新会重新出现。
                  if (!_lineUnavailable(candidate))
                    sdkLineOption(sheetContext, candidate),
                if (video.lines.every(_lineUnavailable))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '当前选集没有可用线路，可换一集或换来源',
                      style: Theme.of(sheetContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    } finally {
      _refreshLineSheet = null;
    }
  }

  /// 该线路在当前选集下没有可播条目（缺目录或集号对不上）。
  /// 探测完成前状态是 loading，按可用处理，避免弹窗瞬间清空。
  bool _lineUnavailable(SdkLine line) {
    final status = _playback.candidates
        .where((item) => item.line.code == line.code)
        .firstOrNull
        ?.status;
    return status == 'mismatch' || status == 'empty';
  }

  Widget sdkLineOption(BuildContext sheetContext, SdkLine candidate) {
    final metadata = _playback.candidates
        .where((item) => item.line.code == candidate.code)
        .firstOrNull;
    return SdkLineOption(
      title: candidate.label,
      subtitle: metadata?.bestQuality?.height != null
          ? '${metadata!.summary} · 来源声明'
          : metadata?.summary ?? '',
      current: _activeSdkId == service.id && _activeLineCode == candidate.code,
      selected: !automatic && line?.code == candidate.code,
      onTap: () {
        Navigator.of(sheetContext).pop();
        unawaited(selectLine(candidate));
      },
    );
  }

  void showDescription(BuildContext pageContext) {
    showPlayraSheet<void>(
      context: pageContext,
      size: PlayraSheetSize.standard,
      title: video.title,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video.subtitle.isNotEmpty) ...[
              Text(
                video.subtitle,
                style: TextStyle(
                  fontSize: PlayraType.caption,
                  color: PlayraTokens.of(context).foregroundMuted,
                ),
              ),
              const SizedBox(height: PlayraSpace.md),
            ],
            Text(
              video.description.isEmpty ? '暂无简介' : video.description,
              style: TextStyle(
                fontSize: PlayraType.body,
                height: PlayraType.readingHeight,
                color: PlayraTokens.of(context).foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<SdkEpisode> get inlineEpisodes {
    final current = _displayEpisodeIndex(episodes);
    final start = current > 3 ? current - 3 : 0;
    return episodes.skip(start).take(12).toList();
  }

  int _displayEpisodeIndex(List<SdkEpisode> items) {
    // 待播放也应显示用户实际选中的集，不能只跟随上一次已打开的媒体。
    final selected = items.indexWhere(
      (e) =>
          e.code == _requestedEpisode?.code &&
          e.identityKey == _requestedEpisode?.identityKey,
    );
    if (selected >= 0) return selected;
    return items.indexWhere(
      (e) => e.code == playingCode && e.identityKey == playingIdentity,
    );
  }

  Widget episodeButton(
    SdkEpisode episode, {
    _EpisodeCardSize size = _EpisodeCardSize.compact,
  }) => _SdkEpisodeButton(
    episode: episode,
    size: size,
    selected:
        _requestedEpisode?.code == episode.code &&
        _requestedEpisode?.identityKey == episode.identityKey,
    activity: _activity,
    onPressed: () => selectEpisode(episode),
  );

  void showEpisodes(BuildContext pageContext) {
    // 弹层只调整显示顺序；点击始终传回真实线路与剧集编号。
    final ascending = List<SdkEpisode>.of(episodes);
    var descending = false;
    final currentIndex = _displayEpisodeIndex(ascending);
    var segment = currentIndex < 0 ? 0 : currentIndex ~/ 50;
    showPlayraSheet<void>(
      context: pageContext,
      size: PlayraSheetSize.standard,
      title: '全部选集',
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final ordered = descending ? ascending.reversed.toList() : ascending;
          final groups = (ordered.length / 50).ceil();
          final visible = ordered.skip(segment * 50).take(50).toList();
          return LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context);
              final contentWidth = constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width - 32;
              final columns =
                  (contentWidth / (82 * textScale.scale(1)))
                      .floor()
                      .clamp(2, 6);
              final tileHeight = 48 + (textScale.scale(12) - 12).clamp(0, 24);
              final tileWidth = (contentWidth - 8 * (columns - 1)) / columns;
              final rows = _episodeRows(
                context,
                visible,
                contentWidth,
                tileWidth,
                columns,
              );
              final hasWide = rows.any(
                (row) => row.size != _EpisodeCardSize.compact,
              );
              return ModernPlayerScope(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${line?.label ?? ''} · 共 ${ascending.length} 集',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: PlayraTokens.of(context).foregroundMuted,
                                ),
                              ),
                            ),
                            PlayraButton.ghost(
                              onPressed: () => update(() {
                                descending = !descending;
                                segment = 0;
                              }),
                              child: Text(descending ? '降序' : '升序'),
                            ),
                            if (playingCode == line?.code &&
                                playingIdentity != null)
                              PlayraIconButton(
                                tooltip: '定位当前集',
                                onPressed: () => update(() {
                                  final index = ordered.indexWhere(
                                    (e) => e.identityKey == playingIdentity,
                                  );
                                  if (index >= 0) segment = index ~/ 50;
                                }),
                                icon: Icon(
                                  Icons.my_location,
                                  size: 20,
                                  color: PlayraTokens.of(context).primary,
                                ),
                              ),
                          ],
                        ),
                      if (groups > 1)
                        _SdkEpisodeSegments(
                          labels: [
                            for (var i = 0; i < groups; i++)
                              // 有真实集号时保留非连续编号；原文 part 不伪造数字身份。
                              '${ordered[i * 50].number ?? i * 50 + 1}–${ordered[((i + 1) * 50).clamp(1, ordered.length) - 1].number ?? ((i + 1) * 50).clamp(1, ordered.length)}',
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
                                  Widget button(SdkEpisode episode) =>
                                      _SdkEpisodeButton(
                                        episode: episode,
                                        activity: _activity,
                                        size: row.size,
                                        selected:
                                            episode.code == playingCode &&
                                            episode.identityKey ==
                                                playingIdentity,
                                        onPressed: () {
                                          Navigator.of(sheetContext).pop();
                                          unawaited(selectEpisode(episode));
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
                                  return _SdkEpisodeButton(
                                    episode: episode,
                                    activity: _activity,
                                    selected:
                                        episode.code == playingCode &&
                                        episode.identityKey == playingIdentity,
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      unawaited(selectEpisode(episode));
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

  @override
  void dispose() {
    _saveProgress();
    _historyTimer?.cancel();
    _library.removeListener(_metadataChanged);
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _detailGeneration++;
    _episodesGeneration++;
    _playGeneration++;
    _detailCancel?.cancel();
    _episodesCancel?.cancel();
    _playCancel?.cancel();
    _coordinator?.dispose();
    for (final subscription in _activitySubscriptions) {
      unawaited(subscription.cancel());
    }
    _activity.dispose();
    _keyboardFocus.dispose();
    unawaited(_mediaTail.then((_) => _mediaSession.dispose()));

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernPlayerScope(
    // 页面操作必须拿到深色 Theme 下的上下文，弹层才能捕获相同主题。
    child: Builder(
      builder: (context) {
        if (_nativeView == null) return _buildPage(context);
        return Observer(
          builder: (_) {
            final fullscreen = _nativeView?.isFullscreen == true;
            final pip = _nativeView?.isPip == true;
            final portrait =
                _nativeView?.fullscreen.mode ==
                VideoFullscreenMode.portrait;
            if (_nativePlayer != null &&
                // 竖屏翻页时播放器表面会随切集重建（_videoController 短暂为
                // null），不能因此退回详情页布局——保持全屏分支避免闪屏。
                (_videoController != null || portrait) &&
                (fullscreen || pip)) {
              final surface = _nativePlayerSurface(fillsWindow: true);
              // 抖音式竖屏：PageView 一页一集，当前页是播放器表面，
              // 邻页是封面占位；落定才播放，失败由 currentIndex 回弹。
              final playingIndex = portrait ? _playingEpisodeIndex() : -1;
              return VideoSystemBars(
                fullscreen: fullscreen,
                isPip: pip,
                child: Scaffold(
                  body: portrait && playingIndex >= 0 && episodes.isNotEmpty
                      ? PortraitEpisodePager(
                          currentIndex: playingIndex,
                          itemCount: episodes.length,
                          titleFor: (index) => episodes[index].label,
                          coverFor: (index) => video?.cover ?? '',
                          surfaceBuilder: () =>
                              _nativePlayerSurface(fillsWindow: true),
                          onPageSelected: (index) =>
                              unawaited(play(episodes[index])),
                        )
                      : surface,
                ),
              );
            }
            return _buildPage(context);
          },
        );
      },
    ),
  );

  /// 竖屏翻页器的当前播放集下标；未知返回 -1（翻页器停在原地等待）。
  int _playingEpisodeIndex() {
    final index = episodes.indexWhere(
      (e) => e.code == playingCode && e.identityKey == playingIdentity,
    );
    if (index >= 0) return index;
    final requested = _requestedEpisode;
    if (requested != null) {
      final j = episodes.indexWhere(
        (e) =>
            e.code == requested.code &&
            e.identityKey == requested.identityKey,
      );
      if (j >= 0) return j;
    }
    return -1;
  }

  Widget _nativePlayerSurface({required bool fillsWindow}) => PlayerItem(
    key: _nativeSurfaceKey,
    playerController: _nativePlayer!,
    videoPageController: _nativeView!,
    fillsWindow: fillsWindow,
    keyboardFocus: _keyboardFocus,
    changeEpisode: (index, {int currentRoad = 0, int offset = 0}) async {
      if (!detailLoading &&
          !episodesLoading &&
          index > 0 &&
          index <= episodes.length) {
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(PlayraRadius.card),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_videoController != null)
                          kIsWeb
                              ? WebPlayerSurface(
                                  controller: _videoController!,
                                  onNext: episodes.length < 2
                                      ? null
                                      : () {
                                          final index = episodes.indexWhere(
                                            (episode) =>
                                                episode.code == playingCode &&
                                                episode.identityKey ==
                                                    playingIdentity,
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
                            builder: (context, size) {
                              final hasPoster = video.poster.isNotEmpty;
                              final hasCover = video.cover.isNotEmpty;
                              final targetEpisode =
                                  _requestedEpisode ?? episodes.firstOrNull;
                              final episodeLabel = targetEpisode != null
                                  ? '播放 ${targetEpisode.name}'
                                  : episodes.isNotEmpty
                                      ? '播放 ${episodes.first.name}'
                                      : '立即播放';

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  border: Border.all(
                                    color: PlayraTokens.of(context)
                                        .borderSubtle
                                        .withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // 1. 底层画面：若有横版剧照则直接全景铺满；若为竖版封面则采用高斯模糊环境光，避免粗暴裁切
                                    if (hasPoster)
                                      NetworkImgLayer(
                                        src: video.poster,
                                        fallbackTitle: video.title,
                                        width: size.maxWidth,
                                        height: size.maxHeight,
                                        type: 'bg',
                                        borderRadius: BorderRadius.zero,
                                      )
                                    else if (hasCover) ...[
                                      ImageFiltered(
                                        imageFilter: ImageFilter.blur(
                                          sigmaX: 30,
                                          sigmaY: 30,
                                        ),
                                        child: Transform.scale(
                                          scale: 1.2,
                                          child: NetworkImgLayer(
                                            src: video.cover,
                                            fallbackTitle: video.title,
                                            width: size.maxWidth,
                                            height: size.maxHeight,
                                            type: 'bg',
                                            borderRadius: BorderRadius.zero,
                                          ),
                                        ),
                                      ),
                                      const ColoredBox(color: Color(0x65000000)),
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              PlayraRadius.poster,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(
                                                      alpha: 0.65,
                                                    ),
                                                    blurRadius: 24,
                                                    spreadRadius: 2,
                                                    offset: const Offset(0, 6),
                                                  ),
                                                ],
                                              ),
                                              child: NetworkImgLayer(
                                                src: video.cover,
                                                fallbackTitle: video.title,
                                                width: size.maxHeight * 0.68,
                                                height: size.maxHeight * 0.92,
                                                type: 'cover',
                                                borderRadius: BorderRadius.zero,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    // 2. 顶部和底部电影感平滑阴影蒙层
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      height: 76,
                                      child: const IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Color(0x85000000),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      height: 80,
                                      child: const IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                              colors: [
                                                Color(0x95000000),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 3. 居中微光毛玻璃小胶囊播放按钮
                                    Center(
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: episodes.isEmpty
                                              ? null
                                              : () => play(
                                                  _requestedEpisode ??
                                                      episodes.first,
                                                ),
                                          borderRadius:
                                              BorderRadius.circular(28),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 22,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.92),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.35,
                                                ),
                                                width: 1.2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.45),
                                                  blurRadius: 20,
                                                  spreadRadius: 2,
                                                  offset: const Offset(0, 4),
                                                ),
                                                const BoxShadow(
                                                  color: Colors.black45,
                                                  blurRadius: 10,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.play_arrow_rounded,
                                                  size: 26,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  episodeLabel,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      if (playingLoading && !_preparingOnly)
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: PlayraTokens.of(
                                context,
                              ).background.withValues(alpha: 0.8),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(PlayraRadius.card),
                              ),
                            ),
                            child: const Padding(
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
                          child: PlayraIconButton(
                            tooltip: '重试当前集',
                            onPressed: () => play(_requestedEpisode!),
                            icon: const Icon(Icons.replay_rounded, size: 28),
                          ),
                        ),
                      if (kIsWeb || _videoController == null)
                        Positioned(
                          left: 14,
                          top: 14,
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    width: 1,
                                  ),
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: '返回',
                                  onPressed: () {
                                    if (_nativeView != null &&
                                        _nativeView!.isFullscreen) {
                                      unawaited(
                                        _nativeView!.fullscreen.setFullscreen(
                                          false,
                                        ),
                                      );
                                    } else {
                                      Navigator.of(context).maybePop();
                                    }
                                  },
                                  icon: const Icon(
                                    LucideIcons.chevronLeft,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                          PlayraButton.ghost(
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
                            PlayraButton.ghost(
                              onPressed: loadDetail,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      if (playMessage != null)
                        SdkPlaybackNotice(
                          message: playMessage!,
                          onSwitch: video.lines.length < 2
                              ? null
                              : () => showLines(context),
                          onRetry:
                              playingLoading ||
                                  _requestedEpisode == null ||
                                  _requestedEpisode!.code != line?.code
                              ? null
                              : () => selectEpisode(_requestedEpisode!),
                        ),
                      _sourceControls(context),
                      const SizedBox(height: 8),
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
                          PlayraButton.ghost(
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
                            PlayraButton.ghost(
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

String _episodeLabel(SdkEpisode episode) =>
    '${episode.vip ? 'VIP · ' : ''}${episode.label}';

enum _EpisodeCardSize { compact, half, full }

_EpisodeCardSize _episodeSize(
  BuildContext context,
  SdkEpisode episode,
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
  final List<SdkEpisode> episodes;
}

Widget _episodeRow(_EpisodeRow row, Widget Function(SdkEpisode) button) => Row(
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
  List<SdkEpisode> episodes,
  double width,
  double tileWidth,
  int columns,
) {
  final rows = <_EpisodeRow>[];
  var current = <SdkEpisode>[];
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

class _SdkEpisodeSegments extends StatefulWidget {
  const _SdkEpisodeSegments({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  State<_SdkEpisodeSegments> createState() => _SdkEpisodeSegmentsState();
}

class _SdkEpisodeSegmentsState extends State<_SdkEpisodeSegments>
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
  void didUpdateWidget(covariant _SdkEpisodeSegments oldWidget) {
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
          borderRadius: BorderRadius.circular(24),
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
class _SdkEpisodeButton extends StatelessWidget {
  const _SdkEpisodeButton({
    required this.episode,
    required this.selected,
    required this.onPressed,
    this.activity,
    this.size = _EpisodeCardSize.compact,
  });
  final SdkEpisode episode;
  final bool selected;
  final VoidCallback onPressed;
  final ValueListenable<bool>? activity;
  final _EpisodeCardSize size;

  @override
  Widget build(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    final expanded = size == _EpisodeCardSize.full;
    final wide = size != _EpisodeCardSize.compact;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PlayraRadius.control),
      side: BorderSide(
        color: selected ? tokens.primary : tokens.borderSubtle,
      ),
    );
    return Material(
      color: selected ? tokens.primaryContainer : tokens.surfaceRaised,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: Container(
          constraints: BoxConstraints(minHeight: _episodeHeight(context, size)),
          padding: EdgeInsets.symmetric(
            horizontal: wide ? PlayraSpace.md : PlayraSpace.sm,
            vertical: expanded ? 10 : 0,
          ),
          alignment: wide ? Alignment.centerLeft : Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: wide
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (selected) ...[
                if (activity == null)
                  PlayingMark(active: false, color: tokens.primary)
                else
                  ValueListenableBuilder<bool>(
                    valueListenable: activity!,
                    builder: (_, active, _) =>
                        PlayingMark(active: active, color: tokens.primary),
                  ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  '${episode.vip ? 'VIP · ' : ''}${episode.label}',
                  maxLines: expanded ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: selected ? tokens.primary : tokens.foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
