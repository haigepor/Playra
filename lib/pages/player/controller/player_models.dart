import 'package:kazumi/playback/video_source_format.dart';

/// 播放器初始化参数。空壳阶段只描述媒体本身，不携带任何内容源身份。
class PlaybackInitParams {
  const PlaybackInitParams({
    required this.videoUrl,
    this.offset = 0,
    this.isLocalPlayback = false,
    this.videoSourceFormat = VideoSourceFormat.auto,
    this.episode = 1,
    this.httpHeaders = const {},
    this.episodeTitle = '',
    this.workTitle = '',
    this.sourceName = '',
    this.referer = '',
    this.currentRoad = 0,
    this.coverUrl,
    this.decryptionKey,
  });

  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final VideoSourceFormat videoSourceFormat;
  final int episode;
  final Map<String, String> httpHeaders;
  final String episodeTitle;
  final String workTitle;
  final String sourceName;
  final String referer;
  final int currentRoad;
  final String? coverUrl;

  /// CENC 内容密钥（hex）。空壳保留该能力，供未来的加密源直接使用。
  final String? decryptionKey;
}
