import 'dart:async';
import 'package:kazumi/services/platform/platform_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/pages/player/controller/player_seek_controller.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_panel_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/services/player/external_playback_launcher.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:kazumi/utils/device.dart';

export 'package:kazumi/pages/player/controller/player_models.dart';

/// Serializes play/pause commands while suppressing stale completions.
@visibleForTesting
class PlayerPlaybackIntentQueue {
  final AsyncSerialQueue _queue = AsyncSerialQueue();
  int _revision = 0;

  int get revision => _revision;
  bool isRevisionCurrent(int revision) => _revision == revision;

  Future<void> submit({
    required bool Function() isCurrent,
    required Future<void> Function() command,
    required VoidCallback onApplied,
  }) {
    final revision = ++_revision;
    return _queue.run(() async {
      if (revision != _revision || !isCurrent()) return;
      try {
        await command();
      } catch (_) {
        return;
      }
      if (revision == _revision && isCurrent()) onApplied();
    });
  }

  void invalidate() => _revision++;
}

/// One temporary pause, valid only until another playback intent is submitted.
class PlayerTemporaryPause {
  PlayerTemporaryPause._(this._owner, this._revision, this.completed);

  final PlayerController _owner;
  final int _revision;
  final Future<void> completed;
}

/// 独立播放器控制器：只管理媒体、音量、倍速、截图和全屏。
///
/// 不再持有 Bangumi 身份、弹幕、同步播放或下载控制器；新页面通过
/// `PlaybackInitParams` 传入媒体本身。
class PlayerController {
  PlayerController(this.shaderAssetService, this.audioController);

  final ShaderAssetService shaderAssetService;
  final AudioController audioController;
  final AsyncSessionOwner _initializations = AsyncSessionOwner();
  final PlayerPlaybackIntentQueue _playbackIntents =
      PlayerPlaybackIntentQueue();
  Future<void>? _shutdownFuture;
  final PlayerPanelController panel = PlayerPanelController();
  final PlayerScreenshotController screenshots = PlayerScreenshotController();
  final PlayerDebugController debug = PlayerDebugController();

  late final PlayerPlaybackController playback = PlayerPlaybackController(
    shaderAssetService: shaderAssetService,
    debug: debug,
    videoUrl: () => videoUrl,
    isLocalPlayback: () => isLocalPlayback,
  );
  late final PlayerSeekController seeking = PlayerSeekController(
    playback: playback,
    pause: pause,
    play: play,
    onSeekCompleted: _onSeekCompleted,
  );
  late final ExternalPlaybackLauncher externalPlayback =
      ExternalPlaybackLauncher(
        videoUrl: () => videoUrl,
        referer: () => referer,
      );

  int currentEpisode = 1;
  int currentRoad = 0;
  String referer = '';
  String? coverUrl;
  String videoUrl = '';
  String _workTitle = '';
  String _episodeTitle = '';
  String _sourceName = '';
  bool isLocalPlayback = false;
  bool hasPlaybackHeaders = false;
  Timer? hideVolumeUITimer;
  Timer? _volumeGestureSyncTimer;
  double? _pendingGestureVolume;

  bool muted = false;
  double _preMuteVolume = 100;

  String get sourceName => _sourceName;

  Future<void> toggleMute() async {
    if (!muted && playback.volume > 0) {
      _preMuteVolume = playback.volume;
      muted = true;
      _persistMuteState();
      await setVolume(0);
    } else {
      muted = false;
      _persistMuteState();
      await setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  void _persistMuteState() {
    if (!kIsWeb && !isDesktop()) {
      return;
    }
    unawaited(GStorage.putSetting<bool>(SettingsKeys.playerMuted, muted));
  }

  /// 在音量被主动调高（手势 / 按键 / 滚轮）时退出静音状态。
  void _clearMuteIfNeeded(double value) {
    if (muted && value > 0) {
      muted = false;
      _persistMuteState();
    }
  }

  void setVolumeDuringGesture(double value) {
    _pendingGestureVolume = value.clamp(0.0, 100.0);
    playback.updateVolume(_pendingGestureVolume!);
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = Timer(const Duration(milliseconds: 80), () {
      final vol = _pendingGestureVolume;
      if (vol == null) {
        return;
      }
      unawaited(playback.syncVolumeToDevice(vol));
    });
  }

  Future<void> finishVolumeGesture() async {
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = null;
    final vol = _pendingGestureVolume;
    _pendingGestureVolume = null;
    if (vol != null) {
      playback.volume = vol;
    }
    playback.invalidatePreciseVolume();
    await playback.syncVolumeToDevice(vol);
    final resolved = vol ?? playback.volume;
    _clearMuteIfNeeded(resolved);
    _persistDesktopVolume(resolved);
  }

  void _persistDesktopVolume(double value) {
    if (!kIsWeb && !isDesktop()) {
      return;
    }
    if (muted) {
      return;
    }
    final clamped = value.clamp(0.0, 100.0);
    final stored = GStorage.getSetting(SettingsKeys.defaultVolume);
    if (stored.round() == clamped.round()) {
      return;
    }
    unawaited(GStorage.putSetting<double>(SettingsKeys.defaultVolume, clamped));
  }

  /// Describes [videoUrl], not the episode the page may still be resolving.
  String get mediaTitle {
    final episode = _episodeTitle.isNotEmpty
        ? _episodeTitle
        : '第 $currentEpisode 集';
    return _workTitle.isEmpty ? episode : '$_workTitle · $episode';
  }

  Future<bool> init(PlaybackInitParams params) async {
    if (_initializations.isClosed) {
      return false;
    }
    final initialization = _initializations.begin();
    _playbackIntents.invalidate();

    videoUrl = params.videoUrl;
    _workTitle = params.workTitle;
    _episodeTitle = params.episodeTitle.trim();
    _sourceName = params.sourceName;
    isLocalPlayback = params.isLocalPlayback;
    hasPlaybackHeaders = params.httpHeaders.isNotEmpty;
    currentEpisode = params.episode;
    currentRoad = params.currentRoad;
    referer = params.referer;

    // Playback URLs may contain expiring credentials or private local paths.
    KazumiLogger().i(
      'PlayerController: ${params.isLocalPlayback ? "local" : "online"} playback starting',
    );

    playback.resetForInit();
    debug.playerLogLevel = GStorage.getSetting(SettingsKeys.playerLogLevel);
    playback.playerSpeed =
        params.speed ?? GStorage.getSetting(SettingsKeys.defaultPlaySpeed);
    panel.aspectRatioMode = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultAspectRatioType),
    );

    playback.buttonSkipTime = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    playback.arrowKeySkipTime = GStorage.getSetting(
      SettingsKeys.arrowKeySkipTime,
    );
    try {
      await _releasePlaybackResources();
    } catch (_) {}
    if (initialization.isStale) {
      return false;
    }

    final Player? player;
    try {
      player = await playback.createVideoController(
        params.httpHeaders,
        canInstall: () => initialization.isActive,
        offset: params.offset,
        playWhenReady: params.playWhenReady,
        videoSourceFormat: params.videoSourceFormat,
        decryptionKey: params.decryptionKey,
      );
    } catch (e) {
      if (initialization.isStale) {
        return false;
      }
      playback.loading = false;
      KazumiLogger().e(
        'PlayerController: failed to initialize video (${e.runtimeType})',
      );
      return false;
    }
    if (player == null || !_ownsInitialization(initialization, player)) {
      return false;
    }

    if (kIsWeb || isDesktop()) {
      final freshStart = playback.volume == -1;
      if (freshStart) {
        muted = GStorage.getSetting(SettingsKeys.playerMuted);
        final remembered = GStorage.getSetting(SettingsKeys.defaultVolume);
        _preMuteVolume = remembered > 0 ? remembered : 100;
        playback.volume = muted ? 0 : remembered;
      }
      await setVolume(playback.volume);
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    } else {
      await FlutterVolumeController.getVolume().then((value) {
        playback.volume = (value ?? 0.0) * 100;
      });
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }

      await FlutterVolumeController.updateShowSystemUI(false);
      if (!_ownsInitialization(initialization, player)) {
        await FlutterVolumeController.updateShowSystemUI(true);
        return false;
      }

      FlutterVolumeController.addListener(
        (volume) {
          if (player == null || !_ownsInitialization(initialization, player)) {
            return;
          }
          if (panel.volumeSeeking) {
            return;
          }
          playback.applyExternalVolume(volume * 100);
          if (!Platform.isAndroid && !panel.volumeSeeking) {
            panel.showVolume = true;
            hideVolumeUITimer?.cancel();
            hideVolumeUITimer = Timer(const Duration(seconds: 1), () {
              panel.showVolume = false;
              hideVolumeUITimer = null;
            });
          }
        },
        category: AudioSessionCategory.playback,
        emitOnStart: false,
      );
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    }
    await setPlaybackSpeed(playback.playerSpeed);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    KazumiLogger().i('PlayerController: video initialized');
    playback.loading = false;
    coverUrl = params.coverUrl;
    return true;
  }

  bool _ownsInitialization(AsyncSession initialization, Player player) {
    return initialization.isActive && playback.isCurrentPlayer(player);
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    await playback.setShader(mode, player: player);
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    await playback.setPlaybackSpeed(playerSpeed);
  }

  Future<void> setVolume(double value) async {
    await playback.setVolume(value);
    _clearMuteIfNeeded(value);
    _persistDesktopVolume(value);
  }

  void syncPlaybackState() {
    playback.syncPlaybackState();
  }

  Future<void> playOrPause() async {
    await playback.playOrPause(pause: pause, play: play);
  }

  Future<void> seek(Duration duration, {bool enableSync = true}) =>
      seeking.seekTo(duration, enableSync: enableSync);

  Future<void> seekBy(Duration offset, {bool enableSync = true}) =>
      seeking.seekBy(offset, enableSync: enableSync);

  Future<void> _onSeekCompleted(bool enableSync) async {}

  Future<void> pause({bool enableSync = true}) {
    playback.startupSuspended = true;
    final player = playback.mediaPlayer;
    return _playbackIntents.submit(
      isCurrent: () => player != null && playback.isCurrentPlayer(player),
      command: () => player!.pause(),
      onApplied: () => playback.playing = false,
    );
  }

  Future<void> play({bool enableSync = true}) {
    playback.startupSuspended = false;
    // A deferred open failure may synchronously replace the player UI with a
    // retry gate. Do not subsequently start that failed hidden player.
    if (playback.startupFailureReported) {
      _playbackIntents.invalidate();
      return Future<void>.value();
    }
    final player = playback.mediaPlayer;
    return _playbackIntents.submit(
      isCurrent: () => player != null && playback.isCurrentPlayer(player),
      command: () => player!.play(),
      onApplied: () => playback.playing = true,
    );
  }

  /// Pause for a transient overlay, recording the intent before any await.
  PlayerTemporaryPause pauseTemporarily() {
    final completed = pause(enableSync: false);
    return PlayerTemporaryPause._(this, _playbackIntents.revision, completed);
  }

  /// Resume only if no later playback command or player replacement intervened.
  Future<void> resumeTemporaryPause(PlayerTemporaryPause lease) {
    if (!identical(lease._owner, this) ||
        !_playbackIntents.isRevisionCurrent(lease._revision)) {
      return Future<void>.value();
    }
    // play() synchronously increments the revision, consuming this lease.
    return play(enableSync: false);
  }

  void dispose() {
    beginShutdown();
  }

  /// Starts the idempotent player shutdown without blocking route navigation.
  void beginShutdown() {
    _initializations.close();
    _playbackIntents.invalidate();
    if (_shutdownFuture != null) {
      return;
    }
    screenshots.dispose();
    final shutdown = _shutdownResources();
    _shutdownFuture = shutdown;
    unawaited(
      shutdown.catchError((Object error, StackTrace _) {
        KazumiLogger().e(
          'PlayerController: failed to dispose asynchronously (${error.runtimeType})',
        );
      }),
    );
  }

  Future<void> _shutdownResources() async {
    await _releasePlaybackResources();
  }

  Future<void> _releasePlaybackResources() async {
    hideVolumeUITimer?.cancel();
    _volumeGestureSyncTimer?.cancel();
    if (!kIsWeb) FlutterVolumeController.removeListener();
    await Future.wait([
      audioController.deactivate(),
      playback.stop(),
      _restoreSystemVolumeUi(),
    ]);
  }

  Future<void> _restoreSystemVolumeUi() async {
    if (kIsWeb) return;
    try {
      await FlutterVolumeController.updateShowSystemUI(true);
    } catch (error) {
      KazumiLogger().w(
        'PlayerController: failed to restore the system volume UI (${error.runtimeType})',
      );
    }
  }

  Future<void> stop() async {
    _initializations.cancel();
    _playbackIntents.invalidate();
    await _releasePlaybackResources();
  }

  Future<Uint8List?> screenshotPng() => playback.screenshotPng();

  void setButtonForwardTime(int time) {
    playback.buttonSkipTime = time;
    GStorage.putSetting(SettingsKeys.buttonSkipTime, time);
  }

  void setArrowKeyForwardTime(int time) {
    playback.arrowKeySkipTime = time;
    GStorage.putSetting(SettingsKeys.arrowKeySkipTime, time);
  }

  Future<void> launchExternalPlayer() async {
    await externalPlayback.launch();
  }
}
