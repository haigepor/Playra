import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/play_pause_icon.dart';
import 'package:kazumi/pages/player/player_adjustment_hud.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/pages/player/player_panel_hold.dart';
import 'package:kazumi/pages/player/player_option_sheet.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:kazumi/services/platform/video_fullscreen_mode.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/player/remote.dart';
import 'package:kazumi/services/player/cast_eligibility.dart';
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/constants.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:kazumi/pages/player/player_progress_bar.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/pages/player/kazumi_original_transport.dart';
import 'package:kazumi/pages/player/kazumi_video_details_sheet.dart';
import 'package:kazumi/pages/player/player_screenshot_controls.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

enum _PlayerTool {
  speed,
  aspect,
  resolution,
  timer,
  capture,
  lock,
  pip,
  cast,
  videoInfo,
  external,
}

class PlayerItemPanel extends StatefulWidget {
  const PlayerItemPanel({
    super.key,
    required this.playerController,
    required this.videoPageController,
    required this.fillsWindow,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.handleFullscreen,
    required this.handlePortraitFullscreen,
    required this.enterAndroidPictureInPicture,
    required this.handleScreenShot,
    required this.showScreenshotCandidates,
    required this.onNextEpisode,
    required this.onToggleLock,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarDragUpdate,
    required this.handleProgressBarDragEnd,
    required this.handleProgressBarSeek,
    required this.handleSuperResolutionChange,
    required this.panelVisibilityController,
    this.onToggleSidePanel,
    required this.keyboardFocus,
    required this.acquirePlayerPanelHold,
    required this.onMenuVisibilityChanged,
    required this.skipOP,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
  });

  final PlayerController playerController;
  final PlaybackSession videoPageController;
  final bool fillsWindow;
  final VoidCallback onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final VoidCallback? onToggleSidePanel;
  final VoidCallback handleFullscreen;
  final VoidCallback handlePortraitFullscreen;
  final Future<void> Function() enterAndroidPictureInPicture;
  final VoidCallback handleScreenShot;
  final VoidCallback showScreenshotCandidates;
  final VoidCallback handleProgressBarDragStart;
  final ValueChanged<Duration> handleProgressBarDragUpdate;
  final ValueChanged<bool> handleProgressBarDragEnd;
  final Future<void> Function(Duration duration) handleProgressBarSeek;
  final Future<void> Function(SuperResolutionMode mode)
  handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final FocusNode keyboardFocus;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final ValueChanged<bool> onMenuVisibilityChanged;
  final VoidCallback onNextEpisode;
  final VoidCallback onToggleLock;
  final VoidCallback skipOP;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  @override
  State<PlayerItemPanel> createState() => _PlayerItemPanelState();
}

class _PlayerItemPanelState extends State<PlayerItemPanel> {
  late final Animation<Offset> _topOffsetAnimation;
  late final Animation<Offset> _bottomOffsetAnimation;
  late final Animation<Offset> _rightOffsetAnimation;
  late final PlaybackSession videoPageController = widget.videoPageController;
  late final PlayerController playerController;
  final TextEditingController textController = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  @override
  void dispose() {
    textController.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  void _showForwardChange() {
    KazumiDialog.show(
      context: context,
      builder: (context) {
        var input = '';
        return PlayraDialog(
          title: const Text('跳过秒数'),
          content: PlayraTextField(
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.never,
              labelText: playerController.playback.buttonSkipTime.toString(),
            ),
            onChanged: (value) {
              input = value;
            },
          ),
          actions: <Widget>[
            PlayraButton.ghost(
              onPressed: () => KazumiDialog.dismiss(context: context),
              child: const Text('取消'),
            ),
            PlayraButton(
              onPressed: () {
                if (input.isNotEmpty) {
                  final seconds = int.tryParse(input);
                  if (seconds == null || seconds > 86400) {
                    KazumiDialog.showToast(
                      context: context,
                      message: '请输入 0 到 86400 之间的秒数',
                    );
                    return;
                  }
                  playerController.setButtonForwardTime(seconds);
                }
                KazumiDialog.dismiss(context: context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    final visibility = widget.panelVisibilityController.drive(
      CurveTween(curve: Curves.easeInOut),
    );
    _topOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero),
    );
    _bottomOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero),
    );
    _rightOffsetAnimation = visibility.drive(
      Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero),
    );
  }

  Widget _forwardButton({bool compact = false}) {
    return Tooltip(
      message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: _showForwardChange,
        child: IconButton(
          constraints: compact
              ? const BoxConstraints(minWidth: 40, minHeight: 40)
              : null,
          padding: compact ? const EdgeInsets.symmetric(horizontal: 6) : null,
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: Colors.white,
            height: compact ? 21 : 24,
          ),
          onPressed: widget.skipOP,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final portraitFullscreen =
          videoPageController.fullscreen.mode == VideoFullscreenMode.portrait;
      return LayoutBuilder(
        builder: (context, constraints) => _buildPanel(
          !portraitFullscreen &&
              (_mobile
                  ? !widget.fillsWindow || constraints.maxWidth < 420
                  : constraints.maxWidth <
                        MediaQuery.textScalerOf(context).scale(600)),
        ),
      );
    },
  );

  Widget _buildPanel(bool compact) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: (compact ? 60 : 88) + MediaQuery.paddingOf(context).top,
            colors: const [Color(0x94000000), Colors.transparent],
            stops: const [0.0, 1.0],
            offset: _topOffsetAnimation,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height:
                (compact ? 62 : 136) +
                (widget.fillsWindow ? MediaQuery.paddingOf(context).bottom : 0),
            colors: const [Colors.transparent, Color(0xA6000000)],
            stops: const [0.0, 1.0],
            offset: _bottomOffsetAnimation,
          ),
        ),
        if (_mobile && !videoPageController.isPip)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Observer(
              builder: (context) {
                if ((compact || !widget.fillsWindow) &&
                    !playerController.panel.lockPanel) {
                  return const SizedBox.shrink();
                }
                return Visibility(
                  visible:
                      !widget.disableAnimations ||
                      playerController.panel.showVideoController,
                  child: widget.disableAnimations
                      ? _rightControls()
                      : SlideTransition(
                          position: _rightOffsetAnimation,
                          child: _rightControls(),
                        ),
                );
              },
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Observer(
            builder: (context) {
              return Visibility(
                visible:
                    !playerController.panel.lockPanel &&
                    (widget.disableAnimations
                        ? playerController.panel.showVideoController
                        : true),
                child: widget.disableAnimations
                    ? _buildTopControls(compact)
                    : SlideTransition(
                        position: _topOffsetAnimation,
                        child: _buildTopControls(compact),
                      ),
              );
            },
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Observer(
            builder: (context) {
              return Visibility(
                visible:
                    !playerController.panel.lockPanel &&
                    (widget.disableAnimations
                        ? playerController.panel.showVideoController
                        : true),
                child: widget.disableAnimations
                    ? _buildBottomControls(compact)
                    : SlideTransition(
                        position: _bottomOffsetAnimation,
                        child: _buildBottomControls(compact),
                      ),
              );
            },
          ),
        ),
        Positioned(
          top: 12,
          child: Observer(
            builder: (context) {
              // Hidden HUDs must not observe playback ticks.
              final visible = playerController.panel.showSeekTime;
              return PlayerSeekHud(
                visible: visible,
                currentPosition: visible
                    ? playerController.playback.currentPosition
                    : Duration.zero,
                playerPosition: visible
                    ? playerController.playback.playerPosition
                    : Duration.zero,
                duration: visible
                    ? playerController.playback.duration
                    : Duration.zero,
                direction: playerController.panel.seekDirection,
                cancelPending: playerController.panel.seekCancelPending,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
        Positioned(
          top: 12,
          child: Observer(
            builder: (context) {
              return PlayerSpeedHud(
                visible: playerController.panel.showPlaySpeed,
                speed: playerController.playback.playerSpeed,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
        Positioned(
          top: 12,
          child: Observer(
            builder: (context) {
              final showVolume = playerController.panel.showVolume;
              final showBrightness = playerController.panel.showBrightness;
              return PlayerAdjustmentHud(
                visible: showVolume || showBrightness,
                type: showVolume
                    ? PlayerAdjustmentHudType.volume
                    : PlayerAdjustmentHudType.brightness,
                value: showVolume
                    ? playerController.playback.volume
                    : playerController.panel.brightness,
                disableAnimations: widget.disableAnimations,
              );
            },
          ),
        ),
      ],
    );
  }

  // Kazumi's fullscreen side controls, adapted to Playra's screenshot and lock callbacks.
  Widget _rightControls() => SafeArea(
    top: false,
    bottom: false,
    left: false,
    child: PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      cursor: SystemMouseCursors.basic,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!playerController.panel.lockPanel)
            IconButton(
              onPressed: playerController.screenshots.busy
                  ? null
                  : widget.handleScreenShot,
              tooltip: '截图',
              icon: const Icon(
                Icons.photo_camera_outlined,
                color: Colors.white,
              ),
            ),
          IconButton(
            onPressed: widget.onToggleLock,
            tooltip: playerController.panel.lockPanel ? '解锁面板' : '锁定面板',
            icon: Icon(
              playerController.panel.lockPanel
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildScrim({
    required double height,
    required List<Color> colors,
    required List<double> stops,
    required Animation<Offset> offset,
  }) => Observer(
    builder: (context) {
      final scrim = IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: stops,
            ),
          ),
        ),
      );
      return Visibility(
        visible:
            !playerController.panel.lockPanel &&
            (!widget.disableAnimations ||
                playerController.panel.showVideoController),
        child: widget.disableAnimations
            ? scrim
            : SlideTransition(position: offset, child: scrim),
      );
    },
  );

  List<Widget> _choiceItems<T>(
    Iterable<T> values, {
    required String Function(T) label,
    required bool Function(T) selected,
    required void Function(T) onSelected,
  }) => [
    for (final value in values)
      KazumiMenuItem(
        onPressed: () => onSelected(value),
        label: label(value),
        selected: selected(value),
      ),
  ];

  List<Widget> get _aspectRatioItems => _choiceItems(
    PlayerAspectRatio.values,
    label: (value) => value.label,
    selected: (value) => value == playerController.panel.aspectRatioMode,
    onSelected: (value) => playerController.panel.aspectRatioMode = value,
  );

  List<Widget> get _speedItems => _choiceItems(
    defaultPlaySpeedList,
    label: (value) => '$value×',
    selected: (value) => value == playerController.playback.playerSpeed,
    onSelected: widget.setPlaybackSpeed,
  );

  List<Widget> get _superResolutionItems => kIsWeb
      ? [const KazumiMenuItem(onPressed: null, label: '浏览器不支持 MPV 超分辨率')]
      : _choiceItems(
          SuperResolutionMode.values,
          label: (value) => value.label,
          selected: (value) =>
              value == playerController.playback.superResolutionMode,
          onSelected: widget.handleSuperResolutionChange,
        );

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _cast() async {
    if (kIsWeb) {
      KazumiDialog.showToast(
        message: 'DLNA 投屏需要原生局域网权限，请使用 Windows 或 Android 客户端',
      );
      return;
    }
    final videoUrl = playerController.videoUrl;
    final title = playerController.mediaTitle;
    final reason = castUnavailableReason(
      isLocalPlayback: playerController.isLocalPlayback,
      url: videoUrl,
      referer: playerController.referer,
      hasPlaybackHeaders: playerController.hasPlaybackHeaders,
    );
    if (reason != null) {
      KazumiDialog.showToast(message: reason);
      return;
    }
    final lease = playerController.playback.playing
        ? playerController.pauseTemporarily()
        : null;
    try {
      if (lease != null) await lease.completed;
      if (!mounted ||
          playerController.videoUrl != videoUrl ||
          playerController.mediaTitle != title ||
          castUnavailableReason(
                isLocalPlayback: playerController.isLocalPlayback,
                url: playerController.videoUrl,
                referer: playerController.referer,
                hasPlaybackHeaders: playerController.hasPlaybackHeaders,
              ) !=
              null) {
        return;
      }
      await RemotePlay().castVideo(videoUrl, title: title);
    } catch (_) {
      if (mounted) KazumiDialog.showToast(message: '投屏启动失败，请稍后重试');
    } finally {
      if (mounted && lease != null) {
        await playerController.resumeTemporaryPause(lease);
      }
    }
  }

  Future<void> _mobileMenu({bool speedOnly = false}) async {
    final visibility = widget.onMenuVisibilityChanged;
    final hold = widget.acquirePlayerPanelHold();
    visibility(true);
    try {
      while (true) {
        if (!mounted) return;
        final playback = playerController.playback;
        final panel = playerController.panel;
        final timer = TimedShutdownService();
        var returnToMore = false;
        void backToMore() => returnToMore = true;
        final tool = speedOnly
            ? _PlayerTool.speed
            : await showPlayerOptions<_PlayerTool>(
                context,
                title: '更多选项',
                shortcuts: [
                  const PlayerOption(
                    _PlayerTool.capture,
                    '截图',
                    icon: Icons.photo_camera_outlined,
                  ),
                  const PlayerOption(
                    _PlayerTool.lock,
                    '锁定面板',
                    icon: Icons.lock_outline,
                  ),
                  if (defaultTargetPlatform == TargetPlatform.android)
                    const PlayerOption(
                      _PlayerTool.pip,
                      '画中画',
                      icon: Icons.picture_in_picture_alt_outlined,
                    ),
                  const PlayerOption(
                    _PlayerTool.cast,
                    '远程投屏',
                    icon: Icons.cast_rounded,
                  ),
                ],
                options: [
                  PlayerOption(
                    _PlayerTool.speed,
                    '倍速',
                    opensPage: true,
                    icon: Icons.speed_rounded,
                    detail: '${playback.playerSpeed}×',
                  ),
                  PlayerOption(
                    _PlayerTool.aspect,
                    '视频比例',
                    opensPage: true,
                    icon: Icons.aspect_ratio_rounded,
                    detail: panel.aspectRatioMode.label,
                  ),
                  PlayerOption(
                    _PlayerTool.resolution,
                    '超分辨率',
                    opensPage: true,
                    icon: Icons.hd_outlined,
                    detail: playback.superResolutionMode.label,
                  ),
                  PlayerOption(
                    _PlayerTool.timer,
                    '定时关闭',
                    opensPage: true,
                    icon: Icons.timer_outlined,
                    detail: timer.isActive
                        ? timer.formatRemainingTime()
                        : '未开启',
                  ),
                  const PlayerOption(
                    _PlayerTool.videoInfo,
                    '视频详情',
                    icon: Icons.info_outline_rounded,
                  ),
                  const PlayerOption(
                    _PlayerTool.external,
                    '外部播放',
                    icon: Icons.open_in_new_rounded,
                  ),
                ],
              );
        if (!mounted || tool == null) return;
        switch (tool) {
          case _PlayerTool.speed:
            final value = await showPlayerSpeed(
              context,
              defaultPlaySpeedList,
              playback.playerSpeed,
              onBack: speedOnly ? null : backToMore,
            );
            if (!mounted) return;
            if (returnToMore) continue;
            if (value != null) await widget.setPlaybackSpeed(value);
          case _PlayerTool.aspect:
            final value = await showPlayerOptions<PlayerAspectRatio>(
              context,
              title: '视频比例',
              onBack: backToMore,
              selected: panel.aspectRatioMode,
              options: [
                for (final value in PlayerAspectRatio.values)
                  PlayerOption(value, value.label),
              ],
            );
            if (!mounted) return;
            if (returnToMore) continue;
            if (value == null) return;
            panel.aspectRatioMode = value;
          case _PlayerTool.resolution:
            final value = await showPlayerOptions<SuperResolutionMode>(
              context,
              title: '超分辨率',
              onBack: backToMore,
              selected: playback.superResolutionMode,
              options: [
                for (final value in SuperResolutionMode.values)
                  PlayerOption(value, value.label),
              ],
            );
            if (!mounted) return;
            if (returnToMore) continue;
            if (value == null) return;
            await widget.handleSuperResolutionChange(value);
          case _PlayerTool.timer:
            final value = await showPlayerOptions<int>(
              context,
              title: '定时关闭',
              onBack: backToMore,
              selected: timer.isActive ? timer.setMinutes : 0,
              options: const [
                PlayerOption(0, '不开启'),
                PlayerOption(15, '15 分钟'),
                PlayerOption(30, '30 分钟'),
                PlayerOption(60, '60 分钟'),
                PlayerOption(-1, '自定义'),
              ],
            );
            if (!mounted) return;
            if (returnToMore) continue;
            if (value == null) return;
            if (value == 0) {
              timer.cancel();
            } else if (value < 0) {
              TimedShutdownService.showCustomTimerDialog(
                onExpired: widget.pauseForTimedShutdown,
              );
            } else {
              _startTimer(value);
            }
          case _PlayerTool.capture:
            widget.handleScreenShot();
          case _PlayerTool.lock:
            widget.onToggleLock();
          case _PlayerTool.pip:
            await widget.enterAndroidPictureInPicture();
          case _PlayerTool.cast:
            await _cast();
          case _PlayerTool.videoInfo:
            await _showVideoInfo();
          case _PlayerTool.external:
            playerController.launchExternalPlayer();
        }
        return;
      }
    } finally {
      visibility(false);
      hold.release();
    }
  }

  Future<void> _showVideoInfo() async {
    final hold = widget.acquirePlayerPanelHold();
    widget.onMenuVisibilityChanged(true);
    try {
      await showKazumiVideoDetailsSheet(context, debug: playerController.debug);
    } finally {
      widget.onMenuVisibilityChanged(false);
      hold.release();
    }
  }

  void _startTimer(int minutes) {
    TimedShutdownService().start(
      minutes,
      onExpired: widget.pauseForTimedShutdown,
    );
    KazumiDialog.showToast(
      message:
          '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭',
    );
  }

  Widget _menuButton({
    required Widget child,
    required List<Widget> items,
    String? tooltip,
  }) => PlayerPanelHoldMenuAnchor(
    acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
    onVisibilityChanged: widget.onMenuVisibilityChanged,
    builder: (context, toggle) => tooltip == null
        ? TextButton(onPressed: toggle, child: child)
        : IconButton(onPressed: toggle, icon: child, tooltip: tooltip),
    menuChildren: items,
  );

  Widget get _wideControls => Row(
    children: [
      const Spacer(),
      if (_desktop)
        _menuButton(
          child: const Text('超分辨率', style: TextStyle(color: Colors.white)),
          items: _superResolutionItems,
        ),
      _menuButton(
        child: Text(
          playerController.playback.playerSpeed == 1
              ? '倍速'
              : '${playerController.playback.playerSpeed}x',
          style: const TextStyle(color: Colors.white),
        ),
        items: _speedItems,
      ),
      if (_desktop)
        _menuButton(
          child: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
          tooltip: '视频比例',
          items: _aspectRatioItems,
        ),
      if (widget.onToggleSidePanel != null)
        IconButton(
          color: Colors.white,
          tooltip: '选集面板',
          onPressed: widget.onToggleSidePanel,
          icon: const Icon(Icons.menu_open_rounded),
        ),
    ],
  );

  Widget _buildBottomControls(bool compact) => SafeArea(
    top: false,
    bottom: widget.fillsWindow,
    left: widget.fillsWindow,
    right: widget.fillsWindow,
    child: PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      cursor:
          (videoPageController.isFullscreen &&
              !playerController.panel.showVideoController)
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      child: KazumiOriginalTransport(
        compact: compact,
        timePlacement: KazumiTimeLabelPlacement.forViewport(
          MediaQuery.sizeOf(context),
          desktop: _desktop,
        ),
        playPause: IconButton(
          tooltip: playerController.playback.playing ? '暂停' : '播放',
          constraints: compact
              ? const BoxConstraints(minWidth: 38, minHeight: 38)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          style: compact
              ? IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )
              : null,
          onPressed: () => playerController.playOrPause(),
          icon: PlayPauseIcon(
            iconColor: Colors.white,
            iconSize: compact ? 22 : 25,
            playing: playerController.playback.playing,
          ),
        ),
        nextEpisode:
            playerController.playback.completed &&
                videoPageController.playbackEpisode.episode ==
                    videoPageController
                        .roadList[videoPageController.playbackEpisode.road]
                        .data
                        .length
            ? const SizedBox.shrink()
            : IconButton(
                color: Colors.white,
                icon: const Icon(Icons.skip_next_rounded),
                tooltip: '下一集',
                onPressed: widget.onNextEpisode,
              ),
        // Playback ticks only rebuild the progress bar and its time labels.
        progressBuilder: (location) => Observer(
          builder: (context) => PlayerProgressBar(
            progress: playerController.playback.currentPosition,
            buffered: playerController.playback.buffer,
            total: playerController.playback.duration,
            sideLabels: location == TimeLabelLocation.sides,
            compact: compact,
            onSeek: widget.handleProgressBarSeek,
            onDragStart: widget.handleProgressBarDragStart,
            onDragUpdate: widget.handleProgressBarDragUpdate,
            onDragEnd: widget.handleProgressBarDragEnd,
          ),
        ),
        timeLabel: Observer(
          builder: (context) => Text(
            '${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: !compact && _desktop
                  ? 16
                  : compact
                  ? 11.5
                  : 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        controls: compact ? const SizedBox.shrink() : _wideControls,
        fullscreen: _buildFullscreenButton(compact),
      ),
    ),
  );

  Widget _buildFullscreenButton(bool compact) {
    if (videoPageController.isPip ||
        (widget.fillsWindow &&
            !videoPageController.isFullscreen &&
            !_desktop)) {
      return const SizedBox.shrink();
    }

    final portrait =
        videoPageController.fullscreen.mode == VideoFullscreenMode.portrait;
    return IconButton(
      color: Colors.white,
      constraints: compact
          ? const BoxConstraints(minWidth: 38, minHeight: 38)
          : null,
      padding: compact ? EdgeInsets.zero : null,
      style: compact
          ? IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      icon: Icon(
        portrait
            ? Icons.screen_rotation_rounded
            : videoPageController.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        size: compact ? 21 : 24,
      ),
      tooltip: portrait
          ? '横屏播放'
          : videoPageController.isFullscreen
          ? '退出全屏'
          : '全屏',
      onPressed: portrait
          ? () => unawaited(
              videoPageController.fullscreen.setMode(
                VideoFullscreenMode.landscape,
              ),
            )
          : widget.handleFullscreen,
    );
  }

  Widget _buildTopControls(bool compact) {
    return EmbeddedNativeControlArea(
      requireOffset: compact || !videoPageController.isFullscreen,
      child: SafeArea(
        // 窗口内播放时状态栏是可见的（edge-to-edge），控件必须让开它；
        // 全屏隐藏状态栏后 MediaQuery 的 top padding 归零，这里不会多留空白。
        top: true,
        bottom: false,
        left: widget.fillsWindow,
        right: widget.fillsWindow,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor:
              (videoPageController.isFullscreen &&
                  !playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: compact ? 21 : 24,
                ),
                constraints: compact
                    ? const BoxConstraints(minWidth: 38, minHeight: 38)
                    : null,
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 6)
                    : null,
                style: compact
                    ? IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                    : null,
                tooltip: '返回',
                onPressed: widget.onBackPressed,
              ),
              Expanded(
                child: dtb.DragToMoveArea(
                  child: Text(
                    '${videoPageController.title} · ${videoPageController.currentEpisode?.title ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact
                          ? 14
                          : Theme.of(context).textTheme.titleMedium!.fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (_desktop || _mobile) _forwardButton(compact: compact),
              if (kIsWeb || _desktop)
                PlayerScreenshotControls(
                  controller: playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              if (_mobile)
                Observer(
                  builder: (_) {
                    final screenshots = playerController.screenshots;
                    if (screenshots.candidates.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: '挑选截图 · ${screenshots.candidates.length} 张',
                      onPressed: screenshots.saving
                          ? null
                          : widget.showScreenshotCandidates,
                      constraints: compact
                          ? const BoxConstraints(minWidth: 40, minHeight: 40)
                          : null,
                      padding: compact
                          ? const EdgeInsets.symmetric(horizontal: 6)
                          : null,
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                        size: 21,
                      ),
                    );
                  },
                ),
              if (kIsWeb ||
                  (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android &&
                      !videoPageController.isPip) ||
                  (_desktop && (compact || !videoPageController.isFullscreen)))
                IconButton(
                  onPressed: () async {
                    if (kIsWeb) {
                      await widget.enterAndroidPictureInPicture();
                      return;
                    }
                    if (_desktop) {
                      if (videoPageController.isPip) {
                        await PipUtils.exitDesktopPIPWindow();
                      } else {
                        await PipUtils.enterDesktopPIPWindow(
                          width: playerController.debug.playerWidth,
                          height: playerController.debug.playerHeight,
                        );
                      }
                      videoPageController.isPip = !videoPageController.isPip;
                      return;
                    }
                    await widget.enterAndroidPictureInPicture();
                  },
                  tooltip: '画中画',
                  constraints: compact
                      ? const BoxConstraints(minWidth: 40, minHeight: 40)
                      : null,
                  padding: compact
                      ? const EdgeInsets.symmetric(horizontal: 6)
                      : null,
                  icon: Icon(
                    Icons.picture_in_picture,
                    color: Colors.white,
                    size: compact ? 20 : 24,
                  ),
                ),
              if (_mobile && !compact && !videoPageController.isPip)
                IconButton(
                  tooltip:
                      videoPageController.fullscreen.mode ==
                          VideoFullscreenMode.portrait
                      ? '退出竖屏全屏'
                      : '竖屏全屏',
                  onPressed: widget.handlePortraitFullscreen,
                  icon: const Icon(
                    Icons.stay_current_portrait_rounded,
                    color: Colors.white,
                  ),
                ),
              if (_mobile && MediaQuery.textScalerOf(context).scale(14) > 20)
                IconButton(
                  tooltip: '更多选项',
                  onPressed: _mobileMenu,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                )
              else
                PlayerPanelHoldMenuAnchor(
                  acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                  onVisibilityChanged: widget.onMenuVisibilityChanged,
                  builder: (context, toggle) {
                    return IconButton(
                      onPressed: toggle,
                      tooltip: '更多选项',
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                    );
                  },
                  menuChildren: [
                    KazumiMenuItem(
                      onPressed: widget.handlePortraitFullscreen,
                      label:
                          videoPageController.fullscreen.mode ==
                              VideoFullscreenMode.portrait
                          ? '退出竖屏全屏'
                          : '竖屏全屏',
                    ),
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
                      KazumiMenuItem(
                        onPressed: widget.enterAndroidPictureInPicture,
                        label: '画中画',
                      ),
                    if (!_desktop) ...[
                      KazumiMenuItem(
                        onPressed: widget.handleScreenShot,
                        label: '截图',
                      ),
                      KazumiMenuItem(
                        onPressed: widget.onToggleLock,
                        label: '锁定面板',
                      ),
                    ],
                    if (compact || !_desktop) ...[
                      SubmenuButton(
                        menuChildren: _aspectRatioItems,
                        child: const Text('视频比例'),
                      ),
                      SubmenuButton(
                        menuChildren: _speedItems,
                        child: const Text('倍速'),
                      ),
                      SubmenuButton(
                        menuChildren: _superResolutionItems,
                        child: const Text('超分辨率'),
                      ),
                    ],
                    KazumiMenuItem(onPressed: _showVideoInfo, label: '视频详情'),
                    KazumiMenuItem(onPressed: _cast, label: '远程投屏'),
                    KazumiMenuItem(
                      onPressed: playerController.launchExternalPlayer,
                      label: '外部播放',
                    ),
                    SubmenuButton(
                      menuChildren: [
                        KazumiMenuItem(
                          onPressed: TimedShutdownService().cancel,
                          label: '不开启',
                          selected: !TimedShutdownService().isActive,
                        ),
                        for (final int minutes in [15, 30, 60])
                          KazumiMenuItem(
                            onPressed: () => _startTimer(minutes),
                            label: '$minutes 分钟',
                            selected:
                                TimedShutdownService().setMinutes == minutes,
                          ),
                        KazumiMenuItem(
                          onPressed: () {
                            TimedShutdownService.showCustomTimerDialog(
                              onExpired: widget.pauseForTimedShutdown,
                            );
                          },
                          label: '自定义',
                        ),
                      ],
                      child: ValueListenableBuilder<int>(
                        valueListenable:
                            TimedShutdownService().remainingSecondsNotifier,
                        builder: (context, remainingSeconds, _) => Text(
                          remainingSeconds > 0
                              ? "定时关闭 (${TimedShutdownService().formatRemainingTime()})"
                              : "定时关闭",
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
