import 'dart:async';
import 'package:kazumi/services/platform/platform_io.dart';
import 'package:kazumi/services/platform/browser_display.dart';
import 'package:kazumi/services/platform/video_fullscreen_mode.dart';
import 'package:kazumi/pages/player/player_item_panel.dart';
import 'package:kazumi/pages/player/player_buffering_overlay.dart';
import 'package:kazumi/pages/player/player_keyboard_shortcuts.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';
import 'package:kazumi/pages/player/player_pointer_interaction.dart';
import 'package:kazumi/pages/player/player_gesture_detector.dart';
import 'package:kazumi/pages/player/player_screenshot_feedback_overlay.dart';
import 'package:kazumi/pages/player/player_screenshot_sheet.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/pages/player/player_item_surface.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/platform/player_menu_service.dart';

/// Bounds a single platform PiP entry request, including hangs and late replies.
/// A successful method-channel result remains pending until the native mode
/// callback confirms entry; this avoids showing player controls during resize.
@visibleForTesting
enum AndroidPipEntryFailure { unsupported, failed, timeout }

@visibleForTesting
class AndroidPipEntryCoordinator {
  AndroidPipEntryCoordinator({
    required this.onChanged,
    required this.onFailure,
    this.timeout = const Duration(seconds: 8),
  });

  final VoidCallback onChanged;
  final ValueChanged<AndroidPipEntryFailure> onFailure;
  final Duration timeout;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool _pending = false;

  bool get pending => _pending;
  bool _isCurrent(int generation) =>
      !_disposed && _pending && _generation == generation;

  Future<void> request({
    required Future<bool> Function() isSupported,
    required Future<void> Function() prepare,
    required Future<bool> Function() enter,
  }) async {
    if (_disposed || _pending) return;
    _pending = true;
    final generation = ++_generation;
    _timer = Timer(
      timeout,
      () => _fail(generation, AndroidPipEntryFailure.timeout),
    );
    onChanged();
    try {
      final supported = await isSupported();
      if (!_isCurrent(generation)) return;
      if (!supported) {
        _fail(generation, AndroidPipEntryFailure.unsupported);
        return;
      }
      await prepare();
      if (!_isCurrent(generation)) return;
      final entered = await enter();
      if (!_isCurrent(generation)) return;
      if (!entered) _fail(generation, AndroidPipEntryFailure.failed);
      // If entered is true, the native mode callback or timeout finishes it.
    } catch (error, stack) {
      if (!_isCurrent(generation)) return;
      KazumiLogger().w(
        'PlayerItem: Android PiP entry failed',
        error: error,
        stackTrace: stack,
      );
      _fail(generation, AndroidPipEntryFailure.failed);
    }
  }

  void _fail(int generation, AndroidPipEntryFailure failure) {
    if (!_isCurrent(generation)) return;
    _finish();
    onChanged();
    onFailure(failure);
  }

  void confirmModeChanged() {
    if (_disposed || !_pending) return;
    _finish();
    onChanged();
  }

  void rejectModeChanged() {
    if (_disposed || !_pending) return;
    _fail(_generation, AndroidPipEntryFailure.failed);
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _pending = false;
    _generation++;
  }

  void dispose() {
    _disposed = true;
    _finish();
  }
}

/// Coalesces background suspension and invalidates work when the app resumes.
@visibleForTesting
class BackgroundPlaybackCoordinator {
  BackgroundPlaybackCoordinator({
    required this.shouldSuspend,
    required this.setPrefetchSuspended,
    required this.pause,
  });

  final bool Function() shouldSuspend;
  final Future<void> Function(bool) setPrefetchSuspended;
  final Future<void> Function() pause;
  int _generation = 0;
  bool _requested = false;
  bool _disposed = false;

  Future<void> suspend() async {
    if (_disposed || _requested || !shouldSuspend()) return;
    _requested = true;
    final generation = ++_generation;
    final prefetch = Future<void>.sync(() => setPrefetchSuspended(true))
        .catchError((Object error, StackTrace stack) {
          KazumiLogger().w(
            'PlayerItem: failed to suspend prefetch',
            error: error,
            stackTrace: stack,
          );
        });
    try {
      // Give a pending foreground transition an opportunity to invalidate this
      // request before sending a native pause command.
      await Future<void>.value();
      if (!_disposed && generation == _generation && shouldSuspend()) {
        await pause();
      }
    } catch (error, stack) {
      KazumiLogger().w(
        'PlayerItem: failed to pause in background',
        error: error,
        stackTrace: stack,
      );
    } finally {
      await prefetch;
    }
  }

  Future<void> resume() async {
    if (_disposed) return;
    _generation++;
    _requested = false;
    try {
      // The underlying controller serializes its writes and honours the latest
      // requested prefetch state, even if a prior suspend is still in flight.
      await setPrefetchSuspended(false);
    } catch (error, stack) {
      KazumiLogger().w(
        'PlayerItem: failed to resume prefetch',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}

/// The on-screen portion of the video inside its local layout viewport.
@visibleForTesting
Rect visiblePipVideoRect({
  required Size viewport,
  required Size video,
  required BoxFit fit,
  double? frameAspectRatio,
}) {
  if (viewport.isEmpty) return Rect.zero;
  final bounds = Offset.zero & viewport;
  final frame = frameAspectRatio != null && frameAspectRatio > 0
      ? Alignment.center.inscribe(
          applyBoxFit(
            BoxFit.contain,
            Size(frameAspectRatio, 1),
            viewport,
          ).destination,
          bounds,
        )
      : bounds;
  if (video.isEmpty) return frame.intersect(bounds);
  final visible = Alignment.center.inscribe(
    applyBoxFit(fit, video, frame.size).destination,
    frame,
  );
  return visible.intersect(bounds);
}

class PlayerItem extends StatefulWidget {
  const PlayerItem({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.fillsWindow,
    this.onToggleSidePanel,
    this.episodePanelOpen = false,
    this.episodePanelInset = 0,
    required this.changeEpisode,
    required this.onEpisodeEnded,
    this.resolvingLabel,
    required this.onBackPressed,
    required this.keyboardFocus,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
  });

  final PlayerController playerController;
  final PlaybackSession videoPageController;
  final bool fillsWindow;
  final bool episodePanelOpen;
  final double episodePanelInset;
  final VoidCallback? onToggleSidePanel;
  final Future<void> Function(int episode, {int currentRoad, int offset})
  changeEpisode;
  final VoidCallback onEpisodeEnded;
  final String? resolvingLabel;
  final VoidCallback onBackPressed;
  final FocusNode keyboardFocus;
  final bool disableAnimations;
  final VoidCallback pauseForTimedShutdown;

  @override
  State<PlayerItem> createState() => _PlayerItemState();
}

class _ProgressSeekOwner<T> {
  _ProgressSeekOwner(this.player, this.lease, this.wasPlaying);
  final Object player;
  final T lease;
  final bool wasPlaying;
  bool resuming = false;
  final List<bool Function()> resumeGuards = [];
  int overlayHolds = 0;

  bool get canResume => resumeGuards.every((guard) => guard());
}

/// A screenshot overlay holds the same pause lease as an in-flight drag.
class ProgressSeekOverlay<T> {
  ProgressSeekOverlay._(this._owner);
  final _ProgressSeekOwner<T> _owner;
  bool _released = false;
}

class _ProgressSeekSession<T> {
  _ProgressSeekSession(this.owner, this.initial) : target = initial;
  final _ProgressSeekOwner<T> owner;
  final Duration initial;
  Duration target;
}

/// Serializes consecutive progress drags and shares their temporary pause.
@visibleForTesting
class ProgressSeekCoordinator<T> {
  ProgressSeekCoordinator({
    required this.pause,
    required this.pauseCompleted,
    required this.resume,
    required this.seek,
    required this.setPosition,
    required this.isCurrentPlayer,
  });

  final T Function() pause;
  final Future<void> Function(T) pauseCompleted;
  final Future<void> Function(T) resume;
  final Future<void> Function(Duration) seek;
  final void Function(Duration) setPosition;
  final bool Function(Object) isCurrentPlayer;
  _ProgressSeekOwner<T>? _owner;
  _ProgressSeekSession<T>? _active;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  bool get active => _active != null;
  int get generation => _generation;

  void begin(
    Object player,
    Duration position, {
    required bool playing,
    required bool wantsPlayback,
  }) {
    _generation++;
    final previous = _owner;
    final reuse =
        previous != null &&
        identical(previous.player, player) &&
        !previous.resuming;
    final owner = reuse
        ? previous
        : _ProgressSeekOwner<T>(
            player,
            pause(),
            previous != null &&
                    identical(previous.player, player) &&
                    previous.resuming
                ? wantsPlayback
                : playing,
          );
    _owner = owner;
    _active = _ProgressSeekSession<T>(owner, position);
  }

  ProgressSeekOverlay<T>? acquireOverlay(
    Object? player, {
    required bool playing,
    required bool wantsPlayback,
  }) {
    if (player == null) return null;
    var owner = _owner;
    if (owner == null || !identical(owner.player, player) || owner.resuming) {
      final shouldResume =
          owner != null && identical(owner.player, player) && owner.resuming
          ? wantsPlayback
          : playing;
      if (!shouldResume) return null;
      owner = _ProgressSeekOwner<T>(player, pause(), true);
      _owner = owner;
    }
    owner.overlayHolds++;
    return ProgressSeekOverlay<T>._(owner);
  }

  Future<void> overlayPauseCompleted(ProgressSeekOverlay<T> overlay) =>
      pauseCompleted(overlay._owner.lease);

  Future<void> releaseOverlay(
    ProgressSeekOverlay<T> overlay, {
    required bool Function() canResume,
  }) async {
    if (overlay._released) return;
    overlay._released = true;
    final owner = overlay._owner;
    owner.overlayHolds--;
    owner.resumeGuards.add(canResume);
    await _tail;
    if (!identical(_owner, owner) ||
        owner.overlayHolds != 0 ||
        _active != null ||
        owner.resuming ||
        !isCurrentPlayer(owner.player)) {
      return;
    }
    try {
      if (owner.canResume && owner.wasPlaying) {
        owner.resuming = true;
        await resume(owner.lease);
      }
    } finally {
      if (identical(_owner, owner)) _owner = null;
    }
  }

  void update(Duration position) {
    final session = _active;
    if (session == null || !isCurrentPlayer(session.owner.player)) return;
    session.target = position;
    setPosition(position);
  }

  Future<void> end({required bool cancelled}) {
    final session = _active;
    if (session == null) return Future<void>.value();
    _active = null;
    final generation = _generation;
    bool current() =>
        generation == _generation && isCurrentPlayer(session.owner.player);
    if (cancelled && current()) setPosition(session.initial);
    final result = _tail.then((_) async {
      try {
        await pauseCompleted(session.owner.lease);
        if (!current()) return;
        if (!cancelled) await seek(session.target);
        if (!current()) return;
        if (session.owner.wasPlaying &&
            session.owner.canResume &&
            session.owner.overlayHolds == 0 &&
            !session.owner.resuming) {
          session.owner.resuming = true;
          await resume(session.owner.lease);
        }
      } finally {
        if (generation == _generation &&
            identical(_owner, session.owner) &&
            session.owner.overlayHolds == 0) {
          _owner = null;
        }
      }
    });
    // A failed seek must not block a later gesture.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void invalidate() {
    _generation++;
    _active = null;
    _owner = null;
  }
}

class _PlayerItemState extends State<PlayerItem>
    with
        WindowListener,
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        KazumiDialogOwner {
  late final PlayerController playerController;
  late final PlaybackSession videoPageController = widget.videoPageController;
  AudioController get _audioController => playerController.audioController;
  late final Map<String, PlayerShortcutAction> keyboardActions;
  late final Map<String, PlayerLongPressShortcutActions>
  keyboardLongPressActions;

  final _videoSurfaceKey = GlobalKey();

  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;

  // Auto-hide delay in milliseconds.
  late int playerControllerLayerDisappearTime;

  Timer? hideTimer;
  Timer? playerTimer;
  PlaybackEpisodeSelection? _handledEnd;
  Timer? mouseScrollerTimer;
  Timer? _adjustmentHudHideTimer;
  final Set<PlayerPanelHold> _playerPanelHolds = <PlayerPanelHold>{};
  int _openPlayerMenuCount = 0;
  PlayerPanelHold? _progressBarDragHold;
  late final ProgressSeekCoordinator<PlayerTemporaryPause> _progressSeek =
      ProgressSeekCoordinator<PlayerTemporaryPause>(
        pause: playerController.pauseTemporarily,
        pauseCompleted: (lease) => lease.completed,
        resume: playerController.resumeTemporaryPause,
        seek: playerController.seek,
        setPosition: (position) =>
            playerController.playback.currentPosition = position,
        isCurrentPlayer: (player) =>
            mounted && identical(player, playerController.playback.mediaPlayer),
      );
  PlayerPanelHold? _episodePanelHold;
  PointerDeviceKind? _lastTapPointerKind;
  PointerDeviceKind? _lastDoubleTapPointerKind;

  late final AnimationController _panelVisibilityController;
  late final AnimationController _screenshotFeedbackController;
  late final Animation<double> _screenshotFeedbackAnimation;
  late final PlayerScreenshotController _screenshots =
      playerController.screenshots;
  bool _screenshotSheetOpen = false;

  double? _speedBeforeTouch;
  double lastPlayerSpeed = 1.0;
  late double longPressPlaySpeed;
  bool? _lastPipPlaying;
  Rect? _lastPipSourceRect;
  bool _pipSourceRectSyncScheduled = false;
  late final AndroidPipEntryCoordinator _pipEntry = AndroidPipEntryCoordinator(
    onChanged: () {
      if (mounted) setState(() {});
    },
    onFailure: (failure) {
      if (!mounted) return;
      KazumiDialog.showToast(
        message: switch (failure) {
          AndroidPipEntryFailure.unsupported => '当前设备不支持画中画',
          AndroidPipEntryFailure.timeout => '进入画中画超时，请重试',
          AndroidPipEntryFailure.failed => '进入画中画失败',
        },
      );
      // The paused event may have been skipped while a PiP request was pending.
      if (_shouldSuspendForBackground()) {
        unawaited(_backgroundPlaybackCoordinator.suspend());
      }
    },
  );
  bool get _pipEnterRequested => _pipEntry.pending;
  late final BackgroundPlaybackCoordinator _backgroundPlaybackCoordinator =
      BackgroundPlaybackCoordinator(
        shouldSuspend: _shouldSuspendForBackground,
        setPrefetchSuspended: playerController.playback.setPrefetchSuspended,
        pause: () async {
          if (playerController.playback.mediaPlayer != null &&
              playerController.playback.playerPlaying) {
            await playerController.pause(enableSync: false);
          }
        },
      );
  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleAndroidPIPSourceRectSync();
  }

  bool _shouldSuspendForBackground() =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused &&
      !backgroundPlayback &&
      !videoPageController.isPip &&
      !_pipEnterRequested;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      unawaited(_backgroundPlaybackCoordinator.suspend());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_backgroundPlaybackCoordinator.resume());
    }
  }

  Future<void> _syncAndroidAutoEnterPIPSetting() async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool autoEnterPIPEnabled = GStorage.getSetting(
      SettingsKeys.androidAutoEnterPIP,
    );
    try {
      await PipUtils.setAndroidAutoEnterPIPEnabled(autoEnterPIPEnabled);
    } catch (e) {
      KazumiLogger().w(
        'PlayerItem: failed to sync android auto enter pip setting',
        error: e,
      );
    }
  }

  Future<void> _syncAndroidPIPPlayerPageState(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await PipUtils.setAndroidPIPInPlayerPage(inPlayerPage);
    } catch (e) {
      KazumiLogger().w(
        'PlayerItem: failed to sync android pip player page state',
        error: e,
      );
    }
  }

  Future<void> _updateAndroidPIPActions({bool force = false}) async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool playing = playerController.playback.playing;
    // In picture in picture the measured rect is the small window itself.
    final Rect? sourceRect = videoPageController.isPip
        ? _lastPipSourceRect
        : _androidPIPSourceRect();
    if (!force &&
        _lastPipPlaying == playing &&
        _lastPipSourceRect == sourceRect) {
      return;
    }

    _lastPipPlaying = playing;
    _lastPipSourceRect = sourceRect;
    await PipUtils.updateAndroidPIPActions(
      playing: playing,
      danmakuEnabled: false,
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
      sourceRect: sourceRect,
    );
  }

  // Android PiP expects the letterboxed video bounds in physical pixels.
  Rect? _androidPIPSourceRect() {
    if (!mounted) {
      return null;
    }
    final renderObject = _videoSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final Size size = renderObject.size;
    if (size.isEmpty) {
      return null;
    }
    final mode = playerController.panel.aspectRatioMode;
    final rectInSurface = visiblePipVideoRect(
      viewport: size,
      video: Size(
        playerController.debug.playerWidth.toDouble(),
        playerController.debug.playerHeight.toDouble(),
      ),
      fit: mode.fit,
      frameAspectRatio: mode.frameAspectRatio,
    );
    // Convert to window coordinates, clipping to the visible Flutter view.
    final rect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      rectInSurface,
    ).intersect(Offset.zero & MediaQuery.sizeOf(context));
    if (rect.isEmpty) return null;
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return Rect.fromLTRB(
      rect.left * ratio,
      rect.top * ratio,
      rect.right * ratio,
      rect.bottom * ratio,
    );
  }

  // Remove controls before PiP entry to avoid rebuilding during the resize animation.
  Future<void> enterAndroidPictureInPicture() async {
    if (kIsWeb) {
      if (!await enterBrowserPictureInPicture()) {
        KazumiDialog.showToast(message: '当前浏览器或视频不支持画中画');
      }
      return;
    }
    if (!Platform.isAndroid ||
        !mounted ||
        _pipEnterRequested ||
        videoPageController.isPip) {
      return;
    }
    await _pipEntry.request(
      isSupported: PipUtils.isAndroidPIPSupported,
      prepare: () async {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_pipEntry.pending) return;
        await _updateAndroidPIPActions(force: true);
      },
      enter: () => PipUtils.enterAndroidPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      ),
    );
  }

  void _handleAndroidPIPModeChanged(bool inPipMode) {
    if (!mounted ||
        (videoPageController.isPip == inPipMode && !_pipEnterRequested)) {
      return;
    }
    setState(() {
      videoPageController.isPip = inPipMode;
    });
    if (inPipMode) {
      _pipEntry.confirmModeChanged();
    } else {
      _pipEntry.rejectModeChanged();
    }
    if (!inPipMode) {
      _scheduleAndroidPIPSourceRectSync();
    }
  }

  void _scheduleAndroidPIPSourceRectSync() {
    if (!Platform.isAndroid || _pipSourceRectSyncScheduled) {
      return;
    }
    _pipSourceRectSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pipSourceRectSyncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(_updateAndroidPIPActions());
    });
  }

  Future<void> _syncPIPAspectWhenVideoSizeReady() async {
    if (playerController.debug.playerWidth <= 0 ||
        playerController.debug.playerHeight <= 0) {
      return;
    }
    if (Platform.isAndroid) {
      await _updateAndroidPIPActions(force: true);
      return;
    }
    if (isDesktop() && videoPageController.isPip) {
      await PipUtils.enterDesktopPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      );
    }
  }

  void _initKeyboardActions() {
    keyboardActions = {
      'playorpause': () => playerController.playOrPause(),
      'forward': handleShortcutForwardDown,
      'rewind': handleShortcutRewind,
      'next': () => handlePreNextEpisode('next'),
      'prev': () => handlePreNextEpisode('prev'),
      'volumeup': () => handleShortcutVolumeChange('up'),
      'volumedown': () => handleShortcutVolumeChange('down'),
      'togglemute': () => handleShortcutVolumeChange('mute'),
      'fullscreen': () => handleShortcutFullscreen(),
      'screenshot': handleScreenshot,
      'skip': skipOP,
      'exitfullscreen': () => handleShortcutExitFullscreen(),
      'speed1': () => setPlaybackSpeed(1.0),
      'speed2': () => setPlaybackSpeed(2.0),
      'speed3': () => setPlaybackSpeed(3.0),
      'speedup': () => handleSpeedChange('up'),
      'speeddown': () => handleSpeedChange('down'),
    };
    keyboardLongPressActions = {
      'forward': PlayerLongPressShortcutActions(
        onRepeat: handleShortcutForwardRepeat,
        onRelease: handleShortcutForwardUp,
      ),
    };
  }

  void _initPlayerMenu() {
    unawaited(PlayerMenuService.initialize(keyboardActions));
  }

  void _disposePlayerMenu() {
    unawaited(PlayerMenuService.dispose());
  }

  Future<void> handlePreNextEpisode(String direction) async {
    if (videoPageController.loading) return;
    final selection = videoPageController.selectedEpisode;
    final currentRoad = selection.road;
    final episodes = videoPageController.roadList[currentRoad].data;
    int targetEpisode;
    if (direction == 'next') {
      targetEpisode = selection.episode + 1;
    } else if (direction == 'prev') {
      targetEpisode = selection.episode - 1;
    } else {
      return;
    }

    if (targetEpisode > episodes.length) {
      KazumiDialog.showToast(message: '已经是最新一集');
      return;
    }
    if (targetEpisode <= 0) {
      KazumiDialog.showToast(message: '已经是第一集');
      return;
    }

    final targetSelection = PlaybackEpisodeSelection(
      episode: targetEpisode,
      road: currentRoad,
    );
    final targetRef = videoPageController.resolveEpisode(targetSelection);
    if (targetRef != null) {
      KazumiDialog.showToast(message: '正在加载${targetRef.displayTitle}');
    }
    widget.changeEpisode(targetEpisode, currentRoad: currentRoad);
  }

  Future<void> handleShortcutRewind() async {
    try {
      await _seekWithPlayerTimer(
        () => playerController.seekBy(
          Duration(seconds: -playerController.playback.arrowKeySkipTime),
        ),
      );
    } catch (e) {
      KazumiLogger().e('PlayerController: seek failed', error: e);
    }
  }

  void handleShortcutForwardDown() {
    lastPlayerSpeed = playerController.playback.playerSpeed;
  }

  Future<void> handleShortcutForwardRepeat() async {
    final double defaultShortcutForwardPlaySpeed = GStorage.getSetting(
      SettingsKeys.defaultShortcutForwardPlaySpeed,
    );
    if (playerController.playback.playerSpeed <
        defaultShortcutForwardPlaySpeed) {
      playerController.panel.showPlaySpeed = true;
      await setPlaybackSpeed(defaultShortcutForwardPlaySpeed);
    }
  }

  Future<void> handleShortcutForwardUp() async {
    if (playerController.panel.showPlaySpeed) {
      playerController.panel.showPlaySpeed = false;
      await setPlaybackSpeed(lastPlayerSpeed);
    } else {
      try {
        await _seekWithPlayerTimer(
          () => playerController.seekBy(
            Duration(seconds: playerController.playback.arrowKeySkipTime),
          ),
        );
      } catch (e) {
        KazumiLogger().e('PlayerController: seek failed', error: e);
      }
    }
  }

  void handleShortcutFullscreen() {
    if (!videoPageController.isPip) handleFullscreen();
  }

  void handleShortcutExitFullscreen() {
    if (videoPageController.isFullscreen) {
      unawaited(videoPageController.fullscreen.setFullscreen(false));
    } else if (isDesktop() && !Platform.isMacOS) {
      playerController.pause();
      windowManager.hide();
    }
  }

  void _toggleVideoController() {
    if (playerController.panel.showVideoController) {
      hideVideoController();
    } else {
      showVideoController();
    }
  }

  void _handleTap(PointerDeviceKind? pointerKind) {
    if (shouldToggleControllerOnPrimaryTap(
      isDesktop: isDesktop(),
      pointerKind: pointerKind,
    )) {
      _toggleVideoController();
      return;
    }
    playerController.playOrPause();
  }

  void _handleDoubleTap(PointerDeviceKind? pointerKind) {
    if (shouldToggleFullscreenOnDoubleTap(
      isDesktop: isDesktop(),
      isPip: videoPageController.isPip,
      pointerKind: pointerKind,
    )) {
      handleFullscreen();
      return;
    }
    playerController.playOrPause();
  }

  void _handleMouseScroller() {
    playerController.panel.showVolume = true;
    mouseScrollerTimer?.cancel();
    mouseScrollerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        playerController.panel.showVolume = false;
      }
      mouseScrollerTimer = null;
    });
  }

  void _cancelAdjustmentHudHideTimer() {
    _adjustmentHudHideTimer?.cancel();
    _adjustmentHudHideTimer = null;
  }

  void _showVolumeAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showBrightness = false;
    playerController.panel.showVolume = true;
  }

  void _showBrightnessAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showVolume = false;
    playerController.panel.showBrightness = true;
  }

  void _scheduleAdjustmentHudHide({
    Duration delay = const Duration(milliseconds: 650),
  }) {
    _cancelAdjustmentHudHideTimer();
    _adjustmentHudHideTimer = Timer(delay, () {
      if (mounted) {
        playerController.panel.showVolume = false;
        playerController.panel.showBrightness = false;
      }
      _adjustmentHudHideTimer = null;
    });
  }

  void _finishAdjustmentGesture() {
    if (!brightnessVolumeGesture) {
      return;
    }
    if (playerController.panel.volumeSeeking) {
      playerController.panel.volumeSeeking = false;
      unawaited(playerController.finishVolumeGesture());
    }
    if (playerController.panel.brightnessSeeking) {
      playerController.panel.brightnessSeeking = false;
    }
    _scheduleAdjustmentHudHide();
  }

  Future<void> skipOP() async {
    await playerController.seekBy(
      Duration(seconds: playerController.playback.buttonSkipTime),
    );
  }

  Future<void> _bindAudioService() async {
    try {
      await _audioController.bindCallbacks(
        onPlay: () => playerController.play(),
        onPause: () => playerController.pause(),
        onSkipToNext: () => handlePreNextEpisode('next'),
        onSkipToPrevious: () => handlePreNextEpisode('prev'),
        onSeek: (position) => playerController.seek(position),
        artworkUrl: videoPageController.playbackArtwork,
      );
      _syncAudioServiceState();
    } catch (e) {
      KazumiLogger().w('AudioController: failed to bind callbacks', error: e);
    }
  }

  void _syncAudioServiceState() {
    try {
      final selection = videoPageController.playbackEpisode;
      final currentRoad = selection.road;
      final currentEpisode = selection.episode;
      if (videoPageController.roadList.isEmpty ||
          currentRoad < 0 ||
          currentRoad >= videoPageController.roadList.length) {
        return;
      }
      final currentRoadData = videoPageController.roadList[currentRoad];
      if (currentEpisode <= 0 || currentRoadData.data.isEmpty) return;
      final episodeRef = videoPageController.resolveEpisode(selection);
      if (episodeRef == null) return;
      final queueIndex = episodeRef.listIndex - 1;

      if (playerController.playback.duration <= Duration.zero) return;

      final canSkipToPrevious = currentEpisode > 1;
      final canSkipToNext = currentEpisode < currentRoadData.data.length;
      final bangumiTitle = videoPageController.playbackWorkTitle;

      unawaited(
        _audioController.updateSession(
          mediaId:
              '${videoPageController.playbackMediaId}_${currentRoad}_$currentEpisode',
          title: bangumiTitle,
          album: videoPageController.playbackSourceName,
          artist: episodeRef.displayTitle,
          duration: playerController.playback.duration,
          playing: playerController.playback.playing,
          loading: playerController.playback.loading,
          buffering: playerController.playback.isBuffering,
          completed: playerController.playback.completed,
          updatePosition: playerController.playback.currentPosition,
          bufferedPosition: playerController.playback.buffer,
          speed: playerController.playback.playerSpeed,
          queueIndex: queueIndex,
          canSkipToNext: canSkipToNext,
          canSkipToPrevious: canSkipToPrevious,
        ),
      );
    } catch (e) {
      KazumiLogger().w(
        'AudioController: failed to sync playback state',
        error: e,
      );
    }
  }

  void _handleFullscreenChange() async {
    _endTouchSpeed();
    _releasePlayerPanelHolds();
    _scheduleAndroidPIPSourceRectSync();
  }

  void _endTouchSpeed() {
    final original = _speedBeforeTouch;
    if (original == null) return;
    _speedBeforeTouch = null;
    playerController.panel.showPlaySpeed = false;
    unawaited(setPlaybackSpeed(original));
  }

  void _toggleLock() {
    final panel = playerController.panel;
    _endTouchSpeed();
    if (playerController.seeking.hasActiveInteractiveSeek) {
      unawaited(_finishInteractiveSeek(cancelled: true));
    }
    if (_progressSeek.active) {
      unawaited(handleProgressBarDragEnd(true));
    }
    _finishAdjustmentGesture();
    panel.showSeekTime = false;
    panel.showBrightness = false;
    panel.showVolume = false;
    panel.lockPanel = !panel.lockPanel;
    showVideoController();
  }

  void handleProgressBarDragStart() {
    final playback = playerController.playback;
    final player = playback.mediaPlayer;
    if (player == null) return;
    _progressBarDragHold?.release();
    playerTimer?.cancel();
    _progressSeek.begin(
      player,
      playback.currentPosition,
      playing: playback.playerPlaying,
      wantsPlayback: !playback.startupSuspended,
    );
    playerController.panel.showSeekTime = true;
    _syncAudioServiceState();
    _progressBarDragHold = acquirePlayerPanelHold();
  }

  void handleProgressBarDragUpdate(Duration duration) {
    _progressSeek.update(duration);
  }

  Future<void> handleProgressBarDragEnd(bool cancelled) async {
    if (!_progressSeek.active) return;
    final generation = _progressSeek.generation;
    playerController.panel.showSeekTime = false;
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    try {
      await _progressSeek.end(cancelled: cancelled);
      if (mounted && generation == _progressSeek.generation) {
        _syncAudioServiceState();
      }
    } catch (error) {
      KazumiLogger().e('PlayerController: progress seek failed', error: error);
    } finally {
      if (mounted && generation == _progressSeek.generation) {
        _restartPlayerTimer();
      }
    }
  }

  Future<void> handleProgressBarSeek(Duration duration) =>
      playerController.seek(duration);

  void _beginInteractiveSeek() {
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    playerTimer?.cancel();
    playerController.seeking.beginInteractiveSeek();
  }

  Future<void> _finishInteractiveSeek({bool cancelled = false}) async {
    var completed = false;
    try {
      completed = await playerController.seeking.finishInteractiveSeek(
        cancelled: cancelled,
      );
    } catch (e) {
      KazumiLogger().e('PlayerController: interactive seek failed', error: e);
    }
    if (!mounted ||
        (!completed && playerController.seeking.hasActiveInteractiveSeek)) {
      return;
    }
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    if (completed) {
      _syncAudioServiceState();
    }
    _restartPlayerTimer();
  }

  void _restartPlayerTimer() {
    playerTimer?.cancel();
    playerTimer = getPlayerTimer();
  }

  Future<void> _seekWithPlayerTimer(Future<void> Function() seekAction) async {
    playerTimer?.cancel();
    try {
      await seekAction();
    } finally {
      if (mounted) {
        _restartPlayerTimer();
      }
    }
  }

  Future<void> handleScreenshot() async {
    if (!mounted) return;
    if (_screenshots.busy || _screenshotSheetOpen) return;
    final episode = videoPageController.playbackEpisode;
    final source = videoPageController.src;
    final player = playerController.playback.mediaPlayer;
    if (videoPageController.loading || player == null) {
      KazumiDialog.showToast(message: '暂未获取到画面，请等视频显示后重试');
      return;
    }
    final added = await _screenshots.capture(
      capturePng: playerController.screenshotPng,
      title: videoPageController.title,
      episode:
          videoPageController.resolveEpisode(episode)?.displayTitle ??
          '第 ${episode.episode} 集',
      position: player.state.position,
      isCurrent: () =>
          mounted &&
          !videoPageController.loading &&
          videoPageController.playbackEpisode == episode &&
          videoPageController.src == source &&
          identical(playerController.playback.mediaPlayer, player),
    );
    if (!mounted) return;
    if (added) _playScreenshotFeedback();
    if (!_screenshotSheetOpen) {
      showVideoController();
      if (!added || _screenshots.candidates.length == 1) {
        KazumiDialog.showToast(
          message: added
              ? '已截取画面，点击右上角图库挑选保存'
              : _screenshots.message ?? '截图失败，请重试',
          showActionButton: _screenshots.candidates.isNotEmpty,
          actionLabel: '挑选截图',
          onActionPressed: showScreenshotCandidates,
        );
      }
    }
  }

  Future<void> showScreenshotCandidates() async {
    if (!mounted || _screenshotSheetOpen || _screenshots.busy) {
      return;
    }
    _screenshotSheetOpen = true;
    final hold = acquirePlayerPanelHold();
    final player = playerController.playback.mediaPlayer;
    final episode = videoPageController.playbackEpisode;
    final source = videoPageController.src;
    final sleepRemaining =
        TimedShutdownService().remainingSecondsNotifier.value;
    final sleepDeadline = sleepRemaining > 0
        ? DateTime.now().add(Duration(seconds: sleepRemaining))
        : null;
    // Share an in-flight progress pause instead of losing its resume intent.
    final overlay = _progressSeek.acquireOverlay(
      player,
      playing: playerController.playback.playing,
      wantsPlayback: !playerController.playback.startupSuspended,
    );
    try {
      if (overlay != null) await _progressSeek.overlayPauseCompleted(overlay);
      if (!mounted) return;
      await showPlayerScreenshotSheet(context, controller: _screenshots);
    } finally {
      _screenshotSheetOpen = false;
      bool canResume() =>
          mounted &&
          identical(player, playerController.playback.mediaPlayer) &&
          videoPageController.playbackEpisode == episode &&
          videoPageController.src == source &&
          !videoPageController.loading &&
          (sleepDeadline == null || DateTime.now().isBefore(sleepDeadline)) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (ModalRoute.of(context)?.isCurrent ?? false);
      if (mounted) {
        hold.release();
        widget.keyboardFocus.requestFocus();
      } else {
        hold.releaseSilently();
      }
      if (overlay != null) {
        await _progressSeek.releaseOverlay(overlay, canResume: canResume);
      }
    }
  }

  void _playScreenshotFeedback() {
    if (!mounted ||
        widget.disableAnimations ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _screenshotFeedbackController.forward(from: 0);
  }

  Future<void> handleSuperResolutionChange(SuperResolutionMode mode) async {
    if (!mounted) return;

    // The mediacodec_embed renderer cannot apply super-resolution shaders.
    if (Platform.isAndroid && mode != SuperResolutionMode.off) {
      final String androidVideoRenderer = GStorage.getSetting(
        SettingsKeys.androidVideoRenderer,
      );

      if (androidVideoRenderer == 'mediacodec_embed') {
        await KazumiDialog.show(
          builder: (context) {
            return PlayraDialog(
              title: const Text('兼容性提示'),
              content: const Text(
                'MediaCodec 渲染器不支持超分辨率功能。\n\n'
                '如需使用超分辨率，请在播放设置中将视频渲染器切换为 gpu 或 gpu-next。',
              ),
              actions: [
                PlayraButton.ghost(
                  onPressed: () {
                    KazumiDialog.dismiss(context: context);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
        return;
      }
    }

    final bool requiresPerformanceWarning = mode == SuperResolutionMode.quality;
    final bool warningDisabled = GStorage.getSetting(
      SettingsKeys.disableSuperResolutionWarning,
    );

    if (requiresPerformanceWarning && !warningDisabled) {
      bool confirmed = false;

      await KazumiDialog.show(
        builder: (context) {
          bool dontAskAgain = false;

          return StatefulBuilder(
            builder: (context, setState) {
              return PlayraDialog(
                title: const Text('性能提示'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: dontAskAgain,
                          onChanged: (value) =>
                              setState(() => dontAskAgain = value ?? false),
                        ),
                        const Text('下次不再询问'),
                      ],
                    ),
                  ],
                ),
                actions: [
                  PlayraButton.ghost(
                    onPressed: () async {
                      if (dontAskAgain) {
                        await GStorage.putSetting(
                          SettingsKeys.disableSuperResolutionWarning,
                          true,
                        );
                      }
                      if (!context.mounted) return;
                      KazumiDialog.dismiss(context: context);
                    },
                    child: const Text('取消'),
                  ),
                  PlayraButton(
                    onPressed: () async {
                      confirmed = true;
                      if (dontAskAgain) {
                        await GStorage.putSetting(
                          SettingsKeys.disableSuperResolutionWarning,
                          true,
                        );
                      }
                      if (!context.mounted) return;
                      KazumiDialog.dismiss(context: context);
                    },
                    child: const Text('确认'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (confirmed && mounted) {
        playerController.setShader(mode);
      }
    } else {
      playerController.setShader(mode);
    }
  }

  void handleFullscreen() {
    if (!videoPageController.isPip) {
      unawaited(videoPageController.fullscreen.toggle());
    }
  }

  /// 顶部按钮：普通/横屏全屏 -> 竖屏全屏；竖屏全屏 -> 退出。
  void handlePortraitFullscreen() {
    if (!videoPageController.isPip) {
      unawaited(videoPageController.fullscreen.togglePortrait());
    }
  }

  bool get _canHidePlayerPanel =>
      playerController.panel.canHidePlayerPanel && _playerPanelHolds.isEmpty;

  void showVideoController({bool restartHideTimer = true}) {
    // Re-forwarding restarts the ticker and stalls a frame, so hover must not.
    if (!_panelVisibilityController.isForwardOrCompleted) {
      _panelVisibilityController.forward();
    }
    playerController.panel.showVideoController = true;
    if (restartHideTimer && _canHidePlayerPanel) {
      _startHideTimer();
    }
  }

  void hideVideoController() {
    if (!_canHidePlayerPanel) {
      return;
    }
    _panelVisibilityController.reverse();
    _cancelHideTimer();
    playerController.panel.showVideoController = false;
  }

  PlayerPanelHold acquirePlayerPanelHold() {
    late final PlayerPanelHold hold;
    hold = PlayerPanelHold(
      onRelease: () {
        _playerPanelHolds.remove(hold);
        if (_playerPanelHolds.isNotEmpty) {
          return;
        }
        playerController.panel.canHidePlayerPanel = true;
        _startHideTimer();
      },
    );
    _playerPanelHolds.add(hold);
    playerController.panel.canHidePlayerPanel = false;
    _cancelHideTimer();
    showVideoController(restartHideTimer: false);
    return hold;
  }

  void _handlePlayerMenuVisibilityChanged(bool isOpen) {
    if (isOpen) {
      _openPlayerMenuCount++;
    } else if (_openPlayerMenuCount > 0) {
      _openPlayerMenuCount--;
    }
  }

  // Fullscreen and system overlays can dispose controls before their holds are released.
  void _releasePlayerPanelHolds() {
    for (final hold in _playerPanelHolds.toList()) {
      hold.releaseSilently();
    }
    _playerPanelHolds.clear();
    _progressBarDragHold = null;
    playerController.panel.canHidePlayerPanel = true;
    _startHideTimer();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await playerController.setPlaybackSpeed(speed);
  }

  Future<void> handleSpeedChange(String type) async {
    try {
      final currentSpeed = playerController.playback.playerSpeed;
      int index = defaultPlaySpeedList.indexOf(currentSpeed);
      if (type == "up") {
        if (index < defaultPlaySpeedList.length - 1) {
          index++;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          KazumiDialog.showToast(message: '已达倍速上限');
        }
      } else if (type == "down") {
        if (index > 0) {
          index--;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          KazumiDialog.showToast(message: '已达倍速下限');
        }
      }
    } catch (e) {
      KazumiLogger().e('PlayerController: speed change failed', error: e);
    }
  }

  Future<void> handleShortcutVolumeChange(String type) async {
    try {
      switch (type) {
        case 'up':
          await playerController.setVolume(
            playerController.playback.volume + 10,
          );
          break;
        case 'down':
          await playerController.setVolume(
            playerController.playback.volume - 10,
          );
          break;
        case 'mute':
          await playerController.toggleMute();
          break;
        default:
          return;
      }
      _showVolumeAdjustmentHud();
      _scheduleAdjustmentHudHide(delay: const Duration(seconds: 1));
    } catch (e) {
      KazumiLogger().e('PlayerController: volume change failed', error: e);
    }
  }

  Future<void> setBrightness(double value) async {
    if (kIsWeb) {
      setBrowserVideoBrightness(value);
      return;
    }
    try {
      await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
        value,
      );
    } catch (_) {}
  }

  void _startHideTimer() {
    _cancelHideTimer();
    if (!_canHidePlayerPanel) {
      return;
    }
    hideTimer = Timer(
      Duration(milliseconds: playerControllerLayerDisappearTime),
      () {
        if (mounted) {
          hideVideoController();
        }
        hideTimer = null;
      },
    );
  }

  void _cancelHideTimer() {
    hideTimer?.cancel();
    hideTimer = null;
  }

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      playerController.syncPlaybackState();
      unawaited(_updateAndroidPIPActions());
      _syncAudioServiceState();
      if (!playerController.panel.volumeSeeking) {
        if (kIsWeb || isDesktop()) {
          playerController.playback.applyExternalVolume(
            playerController.playback.playerVolume,
          );
        }
      }
      if (!kIsWeb &&
          !Platform.isWindows &&
          !Platform.isMacOS &&
          !Platform.isLinux &&
          !playerController.panel.brightnessSeeking) {
        ScreenBrightnessPlatform.instance.application.then((value) {
          if (!mounted) return;
          playerController.panel.brightness = value;
        });
      }
      final playingSelection = videoPageController.playbackEpisode;
      if (!playerController.playback.completed) {
        _handledEnd = null;
      } else if (!videoPageController.loading &&
          _handledEnd != playingSelection) {
        _handledEnd = playingSelection;
        if (playerController.playback.resumedNearEnd) {
          unawaited(playerController.playback.restartFromBeginning());
        } else {
          widget.onEpisodeEnded();
        }
      }
    });
  }

  @override
  void onWindowRestore() {}

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    _initKeyboardActions();
    _initPlayerMenu();
    _fullscreenListener = mobx.reaction<VideoFullscreenMode>(
      (_) => videoPageController.fullscreen.mode,
      (_) {
        _handleFullscreenChange();
      },
    );
    _playerSizeListener = mobx.reaction<String>(
      (_) =>
          '${playerController.debug.playerWidth}:${playerController.debug.playerHeight}',
      (_) {
        unawaited(_syncPIPAspectWhenVideoSizeReady());
      },
    );
    if (Platform.isAndroid) {
      PipUtils.initPipHandler(
        owner: this,
        onAction: (action) async {
          if (!mounted) return;

          switch (action) {
            case 'play_pause':
              playerController.playOrPause();
              break;

            case 'forward':
              await skipOP();
              break;
          }

          await _updateAndroidPIPActions(force: true);
        },
        onModeChanged: _handleAndroidPIPModeChanged,
      );
      unawaited(_syncAndroidAutoEnterPIPSetting());
      unawaited(_syncAndroidPIPPlayerPageState(true));
      unawaited(_updateAndroidPIPActions(force: true));
      _scheduleAndroidPIPSourceRectSync();
    }
    WidgetsBinding.instance.addObserver(this);
    _panelVisibilityController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _screenshotFeedbackController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _screenshotFeedbackAnimation = CurvedAnimation(
      parent: _screenshotFeedbackController,
      curve: Curves.linear,
    );
    backgroundPlayback = GStorage.getSetting(SettingsKeys.backgroundPlayback);
    brightnessVolumeGesture = GStorage.getSetting(
      SettingsKeys.brightnessVolumeGesture,
    );
    if (kIsWeb) playerController.panel.brightness = 1;
    playerControllerLayerDisappearTime = GStorage.getSetting(
      SettingsKeys.playerControllerLayerDisappearTime,
    );
    longPressPlaySpeed = GStorage.getSetting(
      SettingsKeys.defaultShortcutForwardPlaySpeed,
    );
    unawaited(_bindAudioService());
    playerTimer = getPlayerTimer();
    windowManager.addListener(this);
    showVideoController();
  }

  @override
  void didUpdateWidget(covariant PlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodePanelOpen == widget.episodePanelOpen &&
        oldWidget.episodePanelInset == widget.episodePanelInset) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.episodePanelOpen && widget.episodePanelInset > 0) {
        if (_episodePanelHold?.isReleased != false) {
          _episodePanelHold = acquirePlayerPanelHold();
        }
      } else {
        _episodePanelHold?.release();
        _episodePanelHold = null;
      }
    });
  }

  @override
  void dispose() {
    _pipEntry.dispose();
    _backgroundPlaybackCoordinator.dispose();
    _episodePanelHold?.releaseSilently();
    // The route-scoped PlayerController owns playback disposal.
    _fullscreenListener();
    _playerSizeListener();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _progressSeek.invalidate();
    playerController.seeking.invalidateInteractiveSeek();
    playerTimer?.cancel();
    hideTimer?.cancel();
    mouseScrollerTimer?.cancel();
    _adjustmentHudHideTimer?.cancel();
    _panelVisibilityController.dispose();
    _screenshotFeedbackController.dispose();
    _disposePlayerMenu();
    if (Platform.isAndroid) {
      unawaited(_syncAndroidPIPPlayerPageState(false));
      PipUtils.disposePipHandler(this);
    }
    if (isDesktop() && videoPageController.isPip) {
      videoPageController.isPip = false;
      unawaited(PipUtils.exitDesktopPIPWindow(restoreFullscreen: false));
    }
    playerController.panel.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web DOM 控件直接接收指针；原生手势层保持原样，避免两套控件争抢事件。
      return Stack(
        children: [
          Positioned.fill(
            child: PlayerItemSurface(
              playerController: playerController,
              onNext: () => handlePreNextEpisode('next'),
            ),
          ),
          Positioned(
            left: 8,
            top: 4,
            child: PlayraIconButton(
              tooltip: '返回',
              onPressed: widget.onBackPressed,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ],
      );
    }
    return Observer(
      builder: (context) {
        return ClipRect(
          child: Container(
            color: Colors.black,
            child: MouseRegion(
              cursor:
                  (videoPageController.isFullscreen &&
                      !playerController.panel.showVideoController)
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              onHover: (PointerEvent pointerEvent) {
                // Android taps can emit hover events.
                if (kIsWeb || isDesktop()) {
                  if (pointerEvent.position.dy > 50 &&
                      pointerEvent.position.dy <
                          MediaQuery.of(context).size.height - 70) {
                    showVideoController();
                  } else {
                    if (!playerController.panel.showVideoController) {
                      _panelVisibilityController.forward();
                      playerController.panel.showVideoController = true;
                    }
                  }
                }
              },
              child: Listener(
                onPointerCancel: (_) => _endTouchSpeed(),
                onPointerSignal: (pointerSignal) {
                  if (!playerController.panel.lockPanel &&
                      pointerSignal is PointerScrollEvent) {
                    _handleMouseScroller();
                    final scrollDelta = pointerSignal.scrollDelta;
                    final double volume =
                        playerController.playback.volume - scrollDelta.dy / 60;
                    playerController.setVolume(volume);
                  }
                },
                child: SizedBox.expand(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PlayerKeyboardShortcuts(
                        focusScopeNode: widget.keyboardFocus,
                        actions: keyboardActions,
                        longPressActions: keyboardLongPressActions,
                        isBlocked: () =>
                            _openPlayerMenuCount > 0 ||
                            playerController.panel.lockPanel,
                      ),
                      Center(
                        key: _videoSurfaceKey,
                        child: PlayerItemSurface(
                          playerController: playerController,
                        ),
                      ),
                      Positioned.fill(
                        child: PlayerBufferingOverlay(
                          player: playerController.playback.mediaPlayer,
                          buffering: playerController.playback.isBuffering,
                          resolving: videoPageController.loading,
                          resolvingLabel: widget.resolvingLabel,
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (details) {
                          _lastTapPointerKind = details.kind;
                        },
                        onTap: () {
                          _handleTap(_lastTapPointerKind);
                          _lastTapPointerKind = null;
                        },
                        onTapCancel: () {
                          _lastTapPointerKind = null;
                        },
                        onDoubleTapDown: (playerController.panel.lockPanel)
                            ? null
                            : (details) {
                                _lastDoubleTapPointerKind = details.kind;
                              },
                        onDoubleTap: (playerController.panel.lockPanel)
                            ? null
                            : () {
                                _handleDoubleTap(
                                  _lastDoubleTapPointerKind ??
                                      _lastTapPointerKind,
                                );
                                _lastDoubleTapPointerKind = null;
                                _lastTapPointerKind = null;
                              },
                        onLongPressStart: (_) {
                          if (playerController.panel.lockPanel) return;
                          _speedBeforeTouch =
                              playerController.playback.playerSpeed;
                          playerController.panel.showPlaySpeed = true;
                          unawaited(setPlaybackSpeed(longPressPlaySpeed));
                        },
                        onLongPressEnd: (_) => _endTouchSpeed(),
                        onLongPressCancel: _endTouchSpeed,
                        child: Container(
                          color: Colors.transparent,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      Positioned.fill(
                        child: PlayerScreenshotFeedbackOverlay(
                          animation: _screenshotFeedbackAnimation,
                        ),
                      ),
                      Positioned.fill(
                        left: 16,
                        top: 25,
                        right: 15,
                        bottom: 15,
                        child: (isDesktop() || playerController.panel.lockPanel)
                            ? Container()
                            : PlayerGestureDetector(
                                onSeekStart: () {
                                  playerController.panel.seekDirection = 0;
                                  playerController.panel.seekCancelPending =
                                      false;
                                  _beginInteractiveSeek();
                                },
                                onSeekUpdate: (delta, cancelPending) {
                                  playerController.panel.showSeekTime = true;
                                  playerController.panel.seekCancelPending =
                                      cancelPending;
                                  if (delta == 0) return;
                                  playerController.panel.seekDirection =
                                      delta > 0 ? 1 : -1;
                                  final double scale =
                                      180000 / MediaQuery.sizeOf(context).width;
                                  playerController.seeking
                                      .updateInteractiveSeek(
                                        playerController
                                                .playback
                                                .currentPosition +
                                            Duration(
                                              milliseconds: (delta * scale)
                                                  .round(),
                                            ),
                                      );
                                },
                                onSeekEnd: (cancelled) {
                                  playerController.panel.showSeekTime = false;
                                  playerController.panel.seekCancelPending =
                                      false;
                                  playerController.panel.seekDirection = 0;
                                  unawaited(
                                    _finishInteractiveSeek(
                                      cancelled: cancelled,
                                    ),
                                  );
                                },
                                onAdjust: !brightnessVolumeGesture
                                    ? null
                                    : (left, fraction) {
                                        final panel = playerController.panel;
                                        if (left) {
                                          panel.brightnessSeeking = true;
                                          _showBrightnessAdjustmentHud();
                                          final value =
                                              (panel.brightness - fraction)
                                                  .clamp(0.0, 1.0);
                                          panel.brightness = value;
                                          unawaited(setBrightness(value));
                                        } else {
                                          _showVolumeAdjustmentHud();
                                          if (!panel.volumeSeeking) {
                                            panel.volumeSeeking = true;
                                            playerController.playback
                                                .invalidatePreciseVolume();
                                          }
                                          final playback =
                                              playerController.playback;
                                          final base =
                                              playback.preciseVolume >= 0
                                              ? playback.preciseVolume
                                              : playback.volume;
                                          playerController
                                              .setVolumeDuringGesture(
                                                base - fraction * 100,
                                              );
                                        }
                                      },
                                onAdjustmentEnd: _finishAdjustmentGesture,
                              ),
                      ),
                      (widget.episodePanelOpen &&
                                  widget.episodePanelInset == 0) ||
                              (Platform.isAndroid &&
                                  (videoPageController.isPip ||
                                      _pipEnterRequested))
                          ? const SizedBox.shrink()
                          : Positioned.fill(
                              right: widget.episodePanelInset,
                              child: PlayerItemPanel(
                                fillsWindow: widget.fillsWindow,
                                playerController: playerController,
                                videoPageController: videoPageController,
                                onBackPressed: widget.onBackPressed,
                                setPlaybackSpeed: setPlaybackSpeed,
                                onToggleSidePanel: widget.onToggleSidePanel,
                                handleFullscreen: handleFullscreen,
                                handlePortraitFullscreen:
                                    handlePortraitFullscreen,
                                enterAndroidPictureInPicture:
                                    enterAndroidPictureInPicture,
                                handleProgressBarDragStart:
                                    handleProgressBarDragStart,
                                handleProgressBarDragUpdate:
                                    handleProgressBarDragUpdate,
                                handleProgressBarDragEnd: (cancelled) =>
                                    unawaited(
                                      handleProgressBarDragEnd(cancelled),
                                    ),
                                handleProgressBarSeek: handleProgressBarSeek,
                                handleSuperResolutionChange:
                                    handleSuperResolutionChange,
                                onToggleLock: _toggleLock,
                                onNextEpisode: () =>
                                    handlePreNextEpisode('next'),
                                panelVisibilityController:
                                    _panelVisibilityController,
                                keyboardFocus: widget.keyboardFocus,
                                acquirePlayerPanelHold: acquirePlayerPanelHold,
                                onMenuVisibilityChanged:
                                    _handlePlayerMenuVisibilityChanged,
                                pauseForTimedShutdown:
                                    widget.pauseForTimedShutdown,
                                disableAnimations: widget.disableAnimations,
                                handleScreenShot: handleScreenshot,
                                showScreenshotCandidates:
                                    showScreenshotCandidates,
                                skipOP: skipOP,
                              ),
                            ),
                      if (playerController.panel.lockPanel &&
                          !widget.episodePanelOpen &&
                          !videoPageController.isPip)
                        Positioned.fill(
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  excludeFromSemantics: true,
                                  onTap: showVideoController,
                                ),
                              ),
                              if (playerController.panel.showVideoController ||
                                  !playerController.playback.playing)
                                SafeArea(
                                  top: false,
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Semantics(
                                      button: true,
                                      label: '解锁面板',
                                      onTap: _toggleLock,
                                      child: ExcludeSemantics(
                                        child: Material(
                                          color: const Color(0xe817171d),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: InkWell(
                                            onTapDown: (_) =>
                                                showVideoController(),
                                            onTap: _toggleLock,
                                            onLongPress: _toggleLock,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 14,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.lock_outline_rounded,
                                                    color: Colors.white,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    '解锁',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
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
            ),
          ),
        );
      },
    );
  }
}
