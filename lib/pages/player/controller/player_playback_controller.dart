// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:kazumi/services/platform/platform_io.dart';
import 'package:kazumi/services/platform/media_resource.dart';
import 'package:kazumi/services/player/native_player_access.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';
import 'package:kazumi/services/player/playback_start_position.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/playback/video_source_format.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/media.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';

part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player);

  final Player player;
  VideoController? videoOutput;
  String? mediaResource;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    final resource = mediaResource;
    mediaResource = null;
    try {
      await prepareVideoOutputDisposal(videoOutput);
    } catch (error) {
      KazumiLogger().w(
        'PlayerPlaybackController: video output cleanup failed (${error.runtimeType})',
      );
    }
    try {
      await player.dispose();
    } catch (error) {
      KazumiLogger().e(
        'PlayerPlaybackController: failed to dispose media player (${error.runtimeType})',
      );
      try {
        await player.stop();
      } catch (_) {}
    } finally {
      if (resource != null) releaseMediaResource(resource);
    }
  }
}

/// Detects playback progress even when a stream cannot honor a resume seek.
@visibleForTesting
class PlayerStartupProgress {
  PlayerStartupProgress(this.initialPosition);

  final Duration initialPosition;
  Duration? _previous;
  bool _advanced = false;

  bool observe(Duration position) {
    final previous = _previous;
    _previous = position;
    if (previous != null) {
      final delta = position - previous;
      // A large discontinuity is a seek, not evidence of playback. Require a
      // subsequent small forward update, also for streams that ignore resume.
      if (delta > Duration.zero &&
          delta <= const Duration(seconds: 2) &&
          !(initialPosition > Duration.zero && position == initialPosition)) {
        _advanced = true;
      }
    }
    return _advanced;
  }
}

/// Coordinates bounded retries only while the current media is starting.
/// The injected checks are re-evaluated after the delay, so a user pause,
/// actual playback progress, or a replaced player cannot be undone by a
/// previously scheduled retry. Errors are never surfaced as raw strings.
@visibleForTesting
class PlayerOpenRetryGate {
  PlayerOpenRetryGate({
    required this.isCurrent,
    required this.withinWindow,
    required this.hasProgress,
    required this.isPaused,
    required this.reopen,
    required this.onFailure,
    Future<void> Function()? delay,
    this.maxAttempts = 2,
  }) : _delay =
           delay ??
           (() => Future<void>.delayed(const Duration(milliseconds: 1200)));

  final bool Function() isCurrent;
  final bool Function() withinWindow;
  final bool Function() hasProgress;
  final bool Function() isPaused;
  final Future<void> Function() reopen;
  final VoidCallback onFailure;
  final Future<void> Function() _delay;
  final int maxAttempts;
  int _attempts = 0;
  bool _pending = false;
  bool _reopening = false;
  bool _stopped = false;
  bool _reported = false;
  bool _deferredFailure = false;
  Object? _failureDuringReopen;

  bool request(Object error) {
    if (_reported && isCurrent()) return true;
    if (_stopped || !isCurrent()) return false;
    // A deliberately paused startup can fail with either transient or fatal
    // errors. Keep the failure for the next explicit play rather than losing
    // a non-transient format error in the paused event handler.
    if (isPaused()) {
      if (!hasProgress()) _deferredFailure = true;
      return true;
    }
    if (!PlayerErrorMapper.isTransientOpenFailure(error)) return false;
    if (_pending) {
      if (_reopening) _failureDuringReopen = error;
      return true;
    }
    if (_attempts >= maxAttempts || !withinWindow() || hasProgress()) {
      return false;
    }
    _attempts++;
    _pending = true;
    unawaited(_retry());
    return true;
  }

  bool get isActive => !_stopped && isCurrent();
  bool get failureReported => _reported;

  void stop() => _stopped = true;

  /// A pause before reopening cancels the pending retry but retains its error.
  /// A pause during reopen waits for its result before deciding to report.
  void intentChanged({required bool paused}) {
    if (_stopped || !isCurrent()) return;
    if (paused && _pending && !_reopening) _deferredFailure = true;
    if (!paused && _deferredFailure) {
      _deferredFailure = false;
      if (!hasProgress()) _notifyFailure();
    }
  }

  /// Atomically mark any terminal startup failure before exposing its UI.
  void reportTerminalFailure(VoidCallback report) {
    if (_stopped || !isCurrent()) return;
    _stopped = true;
    _reported = true;
    report();
  }

  void _notifyFailure() {
    if (isPaused()) return;
    reportTerminalFailure(onFailure);
  }

  Future<void> _retry() async {
    Object? failure;
    try {
      await _delay();
      if (_stopped || !isCurrent()) return;
      if (_deferredFailure || hasProgress()) return;
      if (isPaused()) {
        _deferredFailure = true;
        return;
      }
      if (!withinWindow()) {
        _notifyFailure();
        return;
      }
      _reopening = true;
      await reopen();
    } catch (error) {
      failure = error;
    } finally {
      _reopening = false;
      _pending = false;
      final nextFailure = failure ?? _failureDuringReopen;
      _failureDuringReopen = null;
      if (nextFailure != null && !_stopped && isCurrent() && !hasProgress()) {
        if (isPaused()) {
          _deferredFailure = true;
        } else if (!request(nextFailure)) {
          _notifyFailure();
        }
      }
    }
  }
}

/// Reconcile the latest intent after an asynchronous open or native command.
@visibleForTesting
class PlayerRetryIntentSynchronizer {
  PlayerRetryIntentSynchronizer({
    required this.isCurrent,
    required this.isPaused,
    required this.revision,
    required this.play,
    required this.pause,
  });

  final bool Function() isCurrent;
  final bool Function() isPaused;
  final int Function() revision;
  final Future<void> Function() play;
  final Future<void> Function() pause;

  Future<void> reconcile() async {
    while (isCurrent()) {
      final before = revision();
      if (isPaused()) {
        await pause();
      } else {
        await play();
      }
      if (!isCurrent() || before == revision()) return;
    }
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
    required this.isLocalPlayback,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;
  final bool Function() isLocalPlayback;
  late final PlaybackCachePolicy cachePolicy = PlaybackCachePolicy(
    isLocalPlayback: isLocalPlayback,
    currentPlayer: () => mediaPlayer,
  );

  _OwnedPlayer? _ownedPlayer;
  Player? get mediaPlayer => _ownedPlayer?.player;

  /// 仅当前媒体实例上报；来源控制器决定是否重试，避免错误提示自行循环。
  void Function(String message)? onOpenFailure;
  VideoController? videoController;

  final AsyncSerialQueue _prefetchWrites = AsyncSerialQueue();
  bool _prefetchSuspendWanted = false;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool autoPlay = true;
  bool _startupSuspended = false;
  int _startupPauseGeneration = 0;
  int _startupIntentRevision = 0;
  PlayerOpenRetryGate? _startupRetry;
  bool get startupSuspended => _startupSuspended;
  bool get startupFailureReported => _startupRetry?.failureReported ?? false;
  set startupSuspended(bool value) {
    _startupSuspended = value;
    _startupIntentRevision++;
    if (value) _startupPauseGeneration++;
    _startupRetry?.intentChanged(paused: value);
  }

  bool playerDebugMode = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  /// 历史记录传入的 offset
  int startOffset = 0;

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {}
  }

  @action
  void resetForInit() {
    _startupRetry?.stop();
    _startupRetry = null;
    startupSuspended = false;
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    startOffset = 0;
  }

  /// 本次会话是否从距结尾 [nearEndWatchedThreshold] 以内的位置起播。
  /// 这样的"播放完成"并非真正看完，应从头重播而非切下一集
  bool get resumedNearEnd {
    if (startOffset <= 0 || duration <= Duration.zero) {
      return false;
    }
    return Duration(seconds: startOffset) >= duration - nearEndWatchedThreshold;
  }

  /// 从头重播当前视频。[startOffset] 在重播落地后才归零，
  /// 避免自动连播在此期间抢先触发
  Future<void> restartFromBeginning() async {
    final player = mediaPlayer;
    if (player == null) {
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (!isCurrentPlayer(player)) {
        return;
      }
      await player.play();
      startOffset = 0;
    } catch (e) {
      KazumiLogger().w(
        'PlayerController: failed to restart from beginning (${e.runtimeType})',
      );
    }
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  /// Android blocks network access for backgrounded apps; a prefetching
  /// demuxer then burns through ffmpeg's reconnect/segment retries and marks
  /// the stream EOF, leaving playback permanently stuck once foregrounded.
  /// Suspending zeroes the readahead window so no new requests are issued
  /// while buffered data stays available; restore values are mpv defaults,
  /// which media_kit leaves untouched. Writes are serialized and apply the
  /// latest requested state, so rapid lifecycle flips cannot reorder.
  Future<void> setPrefetchSuspended(bool suspended) async {
    if (!Platform.isAndroid) {
      return;
    }
    _prefetchSuspendWanted = suspended;
    await _prefetchWrites.run(() async {
      final wanted = _prefetchSuspendWanted;
      final player = mediaPlayer;
      if (player == null) {
        return;
      }
      try {
        final pp = nativePlayerAccess(player);
        await pp.setProperty('cache-secs', wanted ? '0' : '36000');
        if (!isCurrentPlayer(player)) {
          return;
        }
        await pp.setProperty('demuxer-readahead-secs', wanted ? '0' : '1');
      } catch (e) {
        KazumiLogger().w(
          'PlayerController: failed to ${wanted ? 'suspend' : 'resume'} demuxer prefetch (${e.runtimeType})',
        );
      }
    });
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders, {
    required bool Function() canInstall,
    int offset = 0,
    bool? playWhenReady,
    VideoSourceFormat videoSourceFormat = VideoSourceFormat.auto,
    // CENC 内容密钥（hex）。mov demuxer 在打开媒体时按它解密
    // cenc-aes-ctr 采样；必须在 player.open 之前设置。
    String? decryptionKey,
  }) async {
    startOffset = offset;
    superResolutionMode = kIsWeb
        ? SuperResolutionMode.off
        : SuperResolutionMode.fromStorageValue(
            GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
          );
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES = GStorage.getSetting(
      SettingsKeys.androidEnableOpenSLES,
    );
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = playWhenReady ?? GStorage.getSetting(SettingsKeys.autoPlay);
    // A fresh open starts a new intent and must not resume an old retry.
    _startupRetry?.stop();
    _startupRetry = null;
    startupSuspended = !autoPlay;
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: cachePolicy.bufferSize,
          osc: false,
          logLevel: MPVLogLevel.values[debug.playerLogLevel],
          adBlocker: false,
        ),
      ),
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;
    cachePolicy.startWatching();

    try {
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      final pp = nativePlayerAccess(player);
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await cachePolicy.apply();
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles");
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final bool proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
      if (proxyEnable) {
        final String proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
        final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
        if (formattedProxy != null) {
          await pp.setProperty("http-proxy", formattedProxy);
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
        }
      } else if (SystemProxyService.isActive) {
        final proxy = SystemProxyService.proxyFor('https');
        if (proxy != null) {
          await pp.setProperty("http-proxy", 'http://${proxy.$1}:${proxy.$2}');
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          KazumiLogger().i('Player: 跟随系统代理 http://${proxy.$1}:${proxy.$2}');
        }
      }

      // HTML 视频使用浏览器默认音轨；Web 后端不支持 AudioTrack.auto。
      if (!kIsWeb) await player.setAudioTrack(AudioTrack.auto());
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer = GStorage.getSetting(
          SettingsKeys.androidVideoRenderer,
        );

        if (androidVideoRenderer == 'auto') {
          // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
          // GPU-NEXT 需要 Vulkan 1.2 支持
          // 避免 Android 13 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
          // x86_64 模拟器（雷电等）的 Vulkan HAL 在 gpu-next 初始化时会崩掉
          // 整个虚拟机，实测只能走 OpenGL 的 gpu 输出。
          final int androidSdkVersion =
              await PlatformEnvironmentService.getAndroidSdkVersion();
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          if (androidSdkVersion >= 34 &&
              !PlatformEnvironmentService.isAndroidX64Emulator) {
            videoRenderer = 'gpu-next';
          } else {
            videoRenderer = 'gpu';
          }
        } else {
          videoRenderer = androidVideoRenderer;
        }
      }

      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          enableAndroidSurfaceProducer: false,
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      candidate.videoOutput = videoController;
      await player.setPlaylistMode(PlaylistMode.none);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      final bool showPlayerError = GStorage.getSetting(
        SettingsKeys.showPlayerError,
      );
      DateTime? openStartedAt;
      final initialPosition = Duration(seconds: offset);
      final progress = PlayerStartupProgress(initialPosition);
      final pauseGeneration = _startupPauseGeneration;
      var playbackAdvanced = false;
      player.stream.position.listen((position) {
        if (isCurrentPlayer(player) && !startupSuspended) {
          playbackAdvanced = progress.observe(position);
        }
      });
      bool hasPlaybackProgress() => playbackAdvanced;

      void reportFailure(String message) {
        final report = onOpenFailure;
        if (report != null) {
          report(message);
        } else {
          KazumiDialog.showToast(message: message, showActionButton: true);
        }
      }

      final initialOpenFinished = Completer<void>();
      late final PlayerOpenRetryGate retry;
      final intent = PlayerRetryIntentSynchronizer(
        isCurrent: () => isCurrentPlayer(player) && retry.isActive,
        isPaused: () => startupSuspended,
        revision: () => _startupIntentRevision,
        play: player.play,
        pause: player.pause,
      );
      retry = PlayerOpenRetryGate(
        isCurrent: () => isCurrentPlayer(player),
        withinWindow: () =>
            openStartedAt != null &&
            DateTime.now().difference(openStartedAt) <
                const Duration(seconds: 8),
        hasProgress: hasPlaybackProgress,
        isPaused: () =>
            startupSuspended && _startupPauseGeneration != pauseGeneration,
        reopen: () async {
          await initialOpenFinished.future;
          if (!retry.isActive || hasPlaybackProgress()) {
            return;
          }
          if (openStartedAt == null ||
              DateTime.now().difference(openStartedAt) >=
                  const Duration(seconds: 8)) {
            throw StateError('Startup retry window expired');
          }
          // The prepared URI is also required on Web, where it contains the
          // gateway encoding of the original headers.
          final resource = candidate.mediaResource;
          if (resource == null) throw StateError('Media resource unavailable');
          KazumiLogger().w('PlayerController: 媒体打开失败，正在重试');
          await player.open(
            Media(
              resource,
              start: initialPosition,
              httpHeaders: kIsWeb ? null : httpHeaders,
            ),
            play: false,
          );
          await intent.reconcile();
        },
        onFailure: () => reportFailure('视频未能打开，请重试'),
      );
      _startupRetry = retry;
      player.stream.error.listen((event) {
        if (!isCurrentPlayer(player)) return;
        if (startupSuspended && _startupPauseGeneration != pauseGeneration) {
          retry.request(event);
          return;
        }
        // Once playback has progressed this is no longer an open failure.
        // Do not let the startup callback tear down a stream that already ran.
        if (hasPlaybackProgress()) {
          retry.stop();
          if (showPlayerError) {
            KazumiDialog.showToast(
              message: '播放过程中出现错误，请检查网络',
              duration: const Duration(seconds: 5),
              showActionButton: true,
            );
          }
          KazumiLogger().e('PlayerController: media playback error');
          return;
        }
        if (retry.request(event)) return;
        final message =
            PlayerErrorMapper.openFailureMessage(event) ??
            (PlayerErrorMapper.isTransientOpenFailure(event)
                ? '视频连接失败，请重试'
                : null);
        if (message != null) {
          retry.reportTerminalFailure(() => reportFailure(message));
        } else {
          retry.stop();
          if (showPlayerError) {
            KazumiDialog.showToast(
              message: '播放器内部错误，请重试',
              duration: const Duration(seconds: 5),
              showActionButton: true,
            );
          }
        }
        // Native errors often embed signed URLs or headers: never log them.
        KazumiLogger().e('PlayerController: media playback error');
      });

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      if (videoSourceFormat == VideoSourceFormat.hls) {
        await pp.setProperty('demuxer-lavf-format', 'hls');
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      // CENC（cenc-aes-ctr）分集解密：mpv 与 ffmpeg 共享 libavformat，
      // mov demuxer 直接接受 decryption_key。属性只在打开媒体时读取，
      // 必须先于 player.open 落位。
      if (!kIsWeb && decryptionKey != null && decryptionKey.isNotEmpty) {
        try {
          await pp.setProperty(
            'demuxer-lavf-o',
            'decryption_key=$decryptionKey',
          );
        } catch (error) {
          KazumiLogger().w('PlayerController: 注入解密密钥失败（${error.runtimeType}）');
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      final mediaResource = await prepareMediaResource(videoUrl(), httpHeaders);
      candidate.mediaResource = mediaResource;
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await configureMediaPlayback(player);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      openStartedAt = DateTime.now();
      final initialIntentRevision = _startupIntentRevision;
      try {
        await player.open(
          Media(
            mediaResource,
            start: Duration(seconds: offset),
            // Web 请求头已编码在网关地址中，HTML 视频不能直接设置请求头。
            httpHeaders: kIsWeb ? null : httpHeaders,
          ),
          play: !startupSuspended,
        );
        if (isCurrentPlayer(player) &&
            initialIntentRevision != _startupIntentRevision) {
          await intent.reconcile();
        }
      } catch (error) {
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (!retry.request(error)) rethrow;
      } finally {
        initialOpenFinished.complete();
      }
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      if (kIsWeb && offset > 0) {
        unawaited(
          restorePlaybackStart(
            player,
            Duration(seconds: offset),
            isCurrent: () => isCurrentPlayer(player) && canInstall(),
          ),
        );
      }

      if (cachePolicy.networkAutomatic) {
        KazumiDialog.showToast(message: '移动数据下已自动开启低内存模式，可在播放设置中改为始终关闭');
      }

      return player;
    } catch (error, stackTrace) {
      if (identical(_ownedPlayer, candidate)) {
        cachePolicy.stopWatching();
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      final pp = nativePlayerAccess(currentPlayer);
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      switch (mode) {
        case SuperResolutionMode.efficiency:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShadersLite,
            ),
          ]);
          break;
        case SuperResolutionMode.quality:
          await pp.command([
            'change-list',
            'glsl-shaders',
            'set',
            buildShadersAbsolutePath(
              shaderAssetService.shadersDirectory.path,
              mpvAnime4KShaders,
            ),
          ]);
          break;
        case SuperResolutionMode.off:
          await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
          break;
      }
      superResolutionMode = mode;
    } catch (e) {
      KazumiLogger().w(
        'PlayerController: failed to set shader (${e.runtimeType})',
      );
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.setRate(playerSpeed);
    } catch (e) {
      KazumiLogger().e(
        'PlayerController: failed to set playback speed (${e.runtimeType})',
      );
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (kIsWeb || isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {}
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    // At EOF the final frame timestamp can precede the end of the media.
    final position = state.completed && state.duration > Duration.zero
        ? state.duration
        : state.position;
    if (currentPosition != position) {
      currentPosition = position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    if (completed != state.completed) {
      completed = state.completed;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    _startupRetry?.stop();
    _startupRetry = null;
    cachePolicy.stopWatching();
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    await Future.wait([
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]);
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    // Encode the captured frame natively; PlayerState dimensions may be stale.
    return player.safeScreenshot(format: 'image/png');
  }
}
