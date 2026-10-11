import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/platform/browser_display.dart';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';

import 'package:kazumi/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/media_error_widget.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_episode_sheet.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/episode_comments_sheet.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';
import 'package:kazumi/pages/video/player_content_tabs.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/video_page_layout.dart';
import 'package:kazumi/pages/video/video_side_panel.dart';
import 'package:kazumi/pages/video/video_system_bars.dart';
import 'package:kazumi/services/player/pip_utils.dart';
import 'package:kazumi/services/player/timed_shutdown_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';

class PlaybackScaffold extends StatefulWidget {
  const PlaybackScaffold({
    super.key,
    this.args,
    this.idlePlayerBuilder,
    this.contentBuilder,
    this.verifyHistoryIdentity = false,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.downloadController,
  });

  final VideoPlaybackArgs? args;
  final bool verifyHistoryIdentity;
  final WidgetBuilder? idlePlayerBuilder;
  final Widget Function(BuildContext, PlaybackScaffoldState)? contentBuilder;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final DownloadController downloadController;

  @override
  State<PlaybackScaffold> createState() => PlaybackScaffoldState();
}

class PlaybackScaffoldState extends State<PlaybackScaffold>
    with SingleTickerProviderStateMixin, WindowListener {
  PlayerController get playerController => widget.playerController;
  VideoPageController get videoPageController => widget.videoPageController;
  bool _didInitializePlayback = false;
  bool hasPlayback = false;
  bool _isExiting = false;
  HistoryController get historyController => widget.historyController;
  DownloadController get downloadController => widget.downloadController;
  late bool playResume;
  bool showDebugLog = false;
  List<String> webviewLogLines = [];
  StreamSubscription<String>? _logSubscription;
  final FocusNode keyboardFocus = FocusNode(
    debugLabel: 'Video player shortcut scope',
  );

  final _episodePanelKey = GlobalKey<EpisodeSelectionPanelState>();
  final _sidePanelKey = GlobalKey<VideoSidePanelState>();
  late TabController tabController;

  late final bool disableAnimations;

  StreamSubscription<SyncPlayChatMessage>? _syncChatSubscription;
  late final mobx.ReactionDisposer _pipModeListener;
  LocalHistoryEntry? _desktopPipEntry;
  void Function()? _browserFullscreenListener;

  static const Duration _offlinePlayerInitDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    hasPlayback = widget.args != null;
    if (widget.args case final args?) {
      videoPageController.applyPlaybackArgs(args);
    }
    windowManager.addListener(this);

    tabController = TabController(length: 2, vsync: this);

    playResume = GStorage.getSetting(SettingsKeys.playResume);
    disableAnimations = GStorage.getSetting(
      SettingsKeys.playerDisableAnimations,
    );
    _pipModeListener = mobx.reaction<bool>(
      (_) => videoPageController.isPip,
      _syncDesktopPipHistory,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializePlayback) {
      return;
    }
    _didInitializePlayback = true;
    videoPageController.fullscreen.attach(ModalRoute.of(context)!);
    if (kIsWeb) {
      // 浏览器 Escape 会先退出全屏，需要同步页面布局和本地导航状态。
      _browserFullscreenListener = listenBrowserFullscreen(
        videoPageController.fullscreen.onDesktopFullscreenChanged,
      );
    } else if (isDesktop()) {
      unawaited(
        videoPageController.fullscreen.initializeDesktop(
          windowManager.isFullScreen,
        ),
      );
    }
    _initializePlayback();
  }

  void _initializePlayback() {
    if (hasPlayback) {
      if (videoPageController.isOfflineMode) {
        _initOfflineMode();
      } else {
        _initOnlineMode();
      }
    }

    _syncChatSubscription = playerController.syncplay.chatStream.listen((
      event,
    ) {
      final localUsername =
          playerController.syncplay.syncplayController?.username ?? '';
      final String displayText = '${event.username}：${event.message}';

      if (playerController.danmaku.danmakuOn &&
          event.username != localUsername &&
          event.fromRemote) {
        playerController.danmaku.canvasController.addDanmaku(
          DanmakuContentItem(
            displayText,
            color: Colors.orange,
            isColorful: true,
            type: DanmakuItemType.bottom,
            extra: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    });
  }

  void _initOfflineMode() {
    final identity = videoPageController.currentHistoryIdentity;
    videoPageController.historyOffset = identity == null
        ? 0
        : videoPageController.getHistoryOffsetFor(identity);
    _revealCurrentEpisode();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(_offlinePlayerInitDelay);
      if (!mounted) {
        return;
      }

      await changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: videoPageController.historyOffset,
      );
    });
  }

  void _initOnlineMode() {
    videoPageController.historyOffset = 0;

    var progress = historyController.lastWatching(
      videoPageController.bangumiItem,
      videoPageController.currentPlugin.name,
    );
    if (widget.verifyHistoryIdentity &&
        widget.args is OnlineVideoPlaybackArgs) {
      final resume = verifiedResume(
        widget.args! as OnlineVideoPlaybackArgs,
        historyController.histories,
      );
      if (resume != null) {
        videoPageController.resetEpisodeState(
          episode: resume.selection.episode,
          road: resume.selection.road,
        );
        if (playResume) videoPageController.historyOffset = resume.offset;
      }
    } else if (progress != null) {
      if (videoPageController.roadList.length > progress.road) {
        if (videoPageController.roadList[progress.road].data.length >=
            progress.episode) {
          videoPageController.resetEpisodeState(
            episode: progress.episode,
            road: progress.road,
          );
          if (playResume) {
            videoPageController.historyOffset = progress.progress.inSeconds;
          }
        }
      }
    }
    _revealCurrentEpisode();

    _logSubscription = videoPageController.logStream.listen((log) {
      if (mounted) {
        setState(() {
          webviewLogLines.add(log);
          if (webviewLogLines.length > 100) {
            webviewLogLines.removeAt(0);
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: videoPageController.historyOffset,
      );
    });
  }

  @override
  void dispose() {
    videoPageController.cancelPendingPlayback();
    if (!_isExiting) unawaited(playerController.stop());
    _browserFullscreenListener?.call();
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      _syncChatSubscription?.cancel();
    } catch (_) {}
    try {
      _logSubscription?.cancel();
    } catch (_) {}
    _pipModeListener();
    _desktopPipEntry?.remove();
    _desktopPipEntry = null;
    if (!isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }
    unawaited(videoPageController.fullscreen.detach());
    keyboardFocus.dispose();
    tabController.dispose();
    TimedShutdownService().cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(false);
  }

  void _toggleDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
  }) async {
    if (!mounted || _isExiting) {
      return;
    }
    setState(() {
      webviewLogLines.clear();
      showDebugLog = false;
    });
    await videoPageController.changeEpisode(
      episode,
      currentRoad: currentRoad,
      offset: offset,
      playerController: playerController,
    );
  }

  void _revealCurrentEpisode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodePanelKey.currentState?.revealCurrentEpisode();
    });
  }

  void _toggleSidePanel() => _sidePanelKey.currentState?.toggle();

  void _closeSidePanel() => _sidePanelKey.currentState?.close();

  // Only desktop PiP participates in local navigation.
  void _syncDesktopPipHistory(bool isPip) {
    if (!isDesktop()) return;
    if (isPip && _desktopPipEntry == null) {
      _desktopPipEntry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          _desktopPipEntry = null;
          if (videoPageController.isPip) {
            videoPageController.isPip = false;
            unawaited(PipUtils.exitDesktopPIPWindow());
          }
        },
      );
      ModalRoute.of(context)!.addLocalHistoryEntry(_desktopPipEntry!);
    } else if (!isPip) {
      _desktopPipEntry?.remove();
      _desktopPipEntry = null;
    }
  }

  void _onBackPressed() {
    unawaited(Navigator.of(context).maybePop());
  }

  void pauseForTimedShutdown() {
    if (playerController.playback.playing) {
      playerController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          setState(() => _isExiting = true);
          playerController.beginShutdown();
        }
      },
      child: Observer(
        builder: (context) {
          final bool isPip = videoPageController.isPip;
          return VideoSystemBars(
            fullscreen: videoPageController.isFullscreen,
            isPip: isPip,
            child: Scaffold(
              body: VideoPageLayout(
                fullscreen: videoPageController.isFullscreen,
                isPip: isPip,
                playerBuilder: (context, layout) => ColoredBox(
                  color: Colors.black,
                  child: Focus(
                    focusNode: keyboardFocus,
                    autofocus: true,
                    // Cleanup resets loading while the route is still visible.
                    child: _isExiting
                        ? const SizedBox.expand()
                        : Observer(builder: (_) => _buildPlayerBody(layout)),
                  ),
                ),
                tabs: tabBody,
                sidePanel: VideoSidePanel(
                  key: _sidePanelKey,
                  fullscreen: videoPageController.isFullscreen,
                  disableAnimations: disableAnimations,
                  onOpened: _revealCurrentEpisode,
                  onClosed: keyboardFocus.requestFocus,
                  child: tabBody,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 选源结果只更换会话上下文，不替换播放器外壳或路由。
  Future<void> startSource(
    OnlineVideoPlaybackArgs args,
    VideoEpisodeSelection selection, {
    int offset = 0,
  }) async {
    if (!mounted || _isExiting) return;
    await videoPageController.switchOnlineSource(
      args,
      selection: selection,
      offset: offset,
      playerController: playerController,
      onReady: () {
        if (mounted) setState(() => hasPlayback = true);
      },
    );
  }

  Widget _buildPlayerBody(VideoPlayerLayout layout) {
    if (!hasPlayback) {
      return widget.idlePlayerBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final bool playerLoading = playerController.playback.loading;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (videoPageController.loading ||
                  playerLoading ||
                  videoPageController.errorMessage != null)
                Container(
                  color: Colors.black,
                  child: Observer(
                    builder: (context) {
                      final errorMessage = videoPageController.errorMessage;
                      if (errorMessage != null) {
                        return MediaErrorWidget(
                          title: '暂时无法播放',
                          errMsg: errorMessage,
                          icon: Icons.videocam_off_outlined,
                        );
                      }
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LoadingIndicator(
                              color: Theme.of(
                                context,
                              ).colorScheme.tertiaryContainer,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              videoPageController.loading
                                  ? '视频资源解析中'
                                  : '视频资源解析成功, 播放器加载中',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              Visibility(
                visible:
                    (videoPageController.loading || playerLoading) &&
                    showDebugLog,
                child: Container(
                  color: Colors.black,
                  child: Align(
                    alignment: Alignment.center,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: webviewLogLines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          webviewLogLines[index],
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !videoPageController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: _onBackPressed,
                          ),
                          const Expanded(
                            child: dtb.DragToMoveArea(
                              child: SizedBox(height: 40),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh_outlined,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              changeEpisode(
                                videoPageController.selectedEpisode.episode,
                                currentRoad:
                                    videoPageController.selectedEpisode.road,
                              );
                            },
                          ),
                          if (layout.hasSidePanel)
                            IconButton(
                              onPressed: _toggleSidePanel,
                              icon: const Icon(
                                Icons.menu_open_rounded,
                                color: Colors.white,
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              showDebugLog
                                  ? Icons.bug_report
                                  : Icons.bug_report_outlined,
                              color: Colors.white,
                            ),
                            onPressed: _toggleDebugConsole,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerLoading
              ? const SizedBox.shrink()
              : PlayerItem(
                  fillsWindow: layout.fillsWindow,
                  playerController: playerController,
                  videoPageController: videoPageController,
                  onToggleSidePanel: layout.hasSidePanel
                      ? _toggleSidePanel
                      : null,
                  changeEpisode: changeEpisode,
                  onBackPressed: _onBackPressed,
                  keyboardFocus: keyboardFocus,
                  disableAnimations: disableAnimations,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                ),
        ),
      ],
    );
  }

  Widget get episodePanel => Observer(
    builder: (context) {
      final downloads = <String, DownloadEpisode>{};
      if (!videoPageController.isOfflineMode) {
        for (final record in downloadController.records) {
          if (record.bangumiId != videoPageController.bangumiItem.id ||
              record.pluginName != videoPageController.currentPlugin.name) {
            continue;
          }
          for (final episode in record.episodes.values) {
            if (episode.episodePageUrl.isNotEmpty) {
              downloads[episode.episodePageUrl] = episode;
            } else if (episode.road >= 0 &&
                episode.road < videoPageController.roadList.length) {
              // Older records have no URL; only match within their own road.
              final urls = videoPageController.roadList[episode.road].data;
              if (episode.episodeNumber > 0 &&
                  episode.episodeNumber <= urls.length) {
                downloads[urls[episode.episodeNumber - 1]] = episode;
              }
            }
          }
        }
      }
      return EpisodeSelectionPanel(
        key: _episodePanelKey,
        title: videoPageController.title,
        roads: videoPageController.roadList,
        selectedRoad: videoPageController.selectedEpisode.road,
        selectedEpisode: videoPageController.selectedEpisode.episode,
        downloads: downloads,
        isOffline: videoPageController.isOfflineMode,
        isPlaying:
            playerController.playback.playing &&
            !playerController.playback.loading &&
            !videoPageController.loading,
        disableAnimations: disableAnimations,
        onEpisodeSelected: (episode, road) {
          if (episode == videoPageController.selectedEpisode.episode &&
              road == videoPageController.selectedEpisode.road) {
            return;
          }
          _closeSidePanel();
          changeEpisode(episode, currentRoad: road);
        },
        onDownload: (road) => showAdaptiveBottomSheet<void>(
          context: context,
          builder: (context) => DownloadEpisodeSheet(
            road: road,
            videoPageController: videoPageController,
          ),
        ),
      );
    },
  );

  Widget get tabBody {
    if (widget.contentBuilder != null) {
      return widget.contentBuilder!(context, this);
    }
    final colors = Theme.of(context).colorScheme;
    final int episodeNum = videoPageController.commentsEpisode;

    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayerContentTabs(
            controller: tabController,
            onEpisodesSelected: _revealCurrentEpisode,
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                episodePanel,
                EpisodeCommentsSheet(
                  episode: episodeNum,
                  selection: videoPageController.selectedEpisode,
                  videoPageController: videoPageController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
