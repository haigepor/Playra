import 'package:kazumi/services/video_source/video_source_service.dart';
import 'video_controller.dart' show VideoEpisodeSelection;
import 'video_playback_args.dart';

/// 规则链的页面内准备结果，尚未提交播放器或观看历史。
class PreparedOnlinePlayback {
  const PreparedOnlinePlayback({
    required this.args,
    required this.selection,
    required this.source,
    required this.resolvedAt,
    this.offset = 0,
    this.expectedDuration,
  });
  final OnlineVideoPlaybackArgs args;
  final VideoEpisodeSelection selection;
  final VideoSource source;
  final DateTime resolvedAt;
  final int offset;
  final Duration? expectedDuration;

  bool matches(OnlineVideoPlaybackArgs next, VideoEpisodeSelection target) =>
      args.plugin.providerId == next.plugin.providerId &&
      selection.road >= 0 &&
      selection.episode > 0 &&
      args.src == next.src &&
      selection == target &&
      selection.road < next.roads.length &&
      selection.road < args.roads.length &&
      selection.episode <= next.roads[selection.road].data.length &&
      selection.episode <= args.roads[selection.road].data.length &&
      args.roads[selection.road].data[selection.episode - 1] ==
          next.roads[selection.road].data[selection.episode - 1];

  bool isFresh(DateTime now) =>
      !now.difference(resolvedAt).isNegative &&
      now.difference(resolvedAt) < const Duration(seconds: 30) &&
      (source.expiresAt == null ||
          source.expiresAt!.isAfter(now.add(const Duration(seconds: 3))));
}
