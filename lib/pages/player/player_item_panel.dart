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
import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/utils/constants.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/pages/player/player_transport_bar.dart';
import 'package:kazumi/pages/player/player_screenshot_controls.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

enum _PlayerTool {
  speed,
  aspect,
  resolution,
  timer,
  capture,
  lock,
  pip,
  cast,
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
              onPressed: () => KazumiDialog.dismiss(),
              child: const Text('取消'),
            ),
            PlayraButton(
              onPressed: () {
                if (input.isNotEmpty) {
                  playerController.setButtonForwardTime(int.parse(input));
                }
                KazumiDialog.dismiss();
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
  }

  Widget _forwardButton() {
    return Tooltip(
      message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: _showForwardChange,
        child: IconButton(
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: Colors.white,
            height: 24,
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
            height: 50,
            colors: const [Colors.black45, Colors.transparent],
            offset: _topOffsetAnimation,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildScrim(
            height: 100,
            colors: const [Colors.transparent, Colors.black45],
            offset: _bottomOffsetAnimation,
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

  Widget _buildScrim({
    required double height,
    required List<Color> colors,
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
    label: (value) => '${value}x',
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

  void _cast() {
    if (kIsWeb) {
      KazumiDialog.showToast(
        message: 'DLNA 投屏需要原生局域网权限，请使用 Windows 或 Android 客户端',
      );
      return;
    }
    final needRestart = playerController.playback.playing;
    playerController.pause();
    RemotePlay()
        .castVideo(
          playerController.videoUrl,
          title: playerController.mediaTitle,
        )
        .whenComplete(() {
          if (mounted && needRestart) {
            playerController.play();
          }
        });
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
            _cast();
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
        ? PlayraButton.ghost(onPressed: toggle, child: child)
        : PlayraIconButton(onPressed: toggle, icon: child, tooltip: tooltip),
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
      if (_mobile)
        TextButton(
          onPressed: () => _mobileMenu(speedOnly: true),
          child: Text(
            '${playerController.playback.playerSpeed}×',
            style: const TextStyle(color: Colors.white),
          ),
        )
      else
        _menuButton(
          child: Text(
            playerController.playback.playerSpeed == 1
                ? '1.0×'
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
        TextButton(
          onPressed: widget.onToggleSidePanel,
          child: const Text('选集', style: TextStyle(color: Colors.white)),
        ),
    ],
  );

  Widget _buildBottomControls(bool compact) => SafeArea(
    top: false,
    bottom: widget.fillsWindow,
    left: !compact && widget.fillsWindow,
    right: !compact && widget.fillsWindow,
    child: PlayerPanelHoldMouseRegion(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      cursor:
          (videoPageController.isFullscreen &&
              !playerController.panel.showVideoController)
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      child: PlayerTransportBar(
        compact: compact,
        timeBesideProgress: !_desktop,
        playPause: IconButton(
          tooltip: playerController.playback.playing ? '暂停' : '播放',
          onPressed: () => playerController.playOrPause(),
          icon: PlayPauseIcon(
            iconColor: Colors.white,
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
          builder: (context) => PlayerProgressSemantics(
            progress: playerController.playback.currentPosition,
            total: playerController.playback.duration,
            onSeek: widget.handleProgressBarSeek,
            child: ProgressBar(
              progressBarColor: PlayraTokens.dark.primary,
              thumbColor: PlayraTokens.dark.primary,
              baseBarColor: Colors.white30,
              barHeight: 3,
              thumbRadius: 5,
              thumbGlowRadius: 18,
              timeLabelLocation: location,
              timeLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              progress: playerController.playback.currentPosition,
              buffered: playerController.playback.buffer,
              total: playerController.playback.duration,
              onSeek: widget.handleProgressBarSeek,
              onDragStart: (_) => widget.handleProgressBarDragStart(),
              onDragUpdate: (details) => playerController.seeking
                  .updateInteractiveSeek(details.timeStamp),
            ),
          ),
        ),
        timeLabel: Observer(
          builder: (context) => Text(
            '${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: !compact && _desktop ? 16 : 12,
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
      icon: Icon(
        portrait
            ? Icons.screen_rotation_rounded
            : videoPageController.isFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
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
        left: !compact && widget.fillsWindow,
        right: !compact && widget.fillsWindow,
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
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
                onPressed: widget.onBackPressed,
              ),
              Expanded(
                child: dtb.DragToMoveArea(
                  child: compact
                      ? const SizedBox(height: 40)
                      : Text(
                          '${videoPageController.title} · ${videoPageController.currentEpisode?.title ?? ''}',
                          maxLines: 2,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Theme.of(
                              context,
                            ).textTheme.titleMedium!.fontSize,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ),
              if (_desktop) _forwardButton(),
              if (kIsWeb || _desktop)
                PlayerScreenshotControls(
                  controller: playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              if (kIsWeb ||
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
                  icon: const Icon(
                    Icons.picture_in_picture,
                    color: Colors.white,
                  ),
                ),
              if (_mobile && !videoPageController.isPip)
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
              if (_mobile)
                IconButton(
                  tooltip: '更多选项',
                  onPressed: _mobileMenu,
                  icon: const Icon(Icons.more_horiz, color: Colors.white),
                )
              else
                PlayerPanelHoldMenuAnchor(
                  acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                  onVisibilityChanged: widget.onMenuVisibilityChanged,
                  builder: (context, toggle) {
                    return IconButton(
                      onPressed: toggle,
                      tooltip: '更多选项',
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
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
