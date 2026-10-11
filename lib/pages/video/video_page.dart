import 'package:flutter/material.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/pages/video/playback_scaffold.dart';

/// 保留旧版播放入口；媒体生命周期由共用外壳管理。
class VideoPage extends StatelessWidget {
  const VideoPage({
    super.key,
    required this.args,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.downloadController,
  });
  final VideoPlaybackArgs args;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final DownloadController downloadController;

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    args: args,
    playerController: playerController,
    videoPageController: videoPageController,
    historyController: historyController,
    downloadController: downloadController,
  );
}
