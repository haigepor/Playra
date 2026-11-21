import 'package:flutter/material.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/player/source_player_page.dart';
import 'package:kazumi/pages/route_args.dart';

class PlaybackDemoPage extends StatelessWidget {
  const PlaybackDemoPage({super.key});
  static const demoStream = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  @override
  Widget build(BuildContext context) => const SourcePlayerPage(
    demoUrl: demoStream,
    request: PlaybackRequest(
      sourceId: 'demo',
      roadCode: 'hls',
      episode: 1,
      detail: MediaDetail(
        key: MediaKey(sourceId: 'demo', mediaId: 'hls'),
        title: '播放演示',
        subtitle: 'HLS 测试流',
        roads: [
          MediaRoad(
            code: 'hls',
            name: 'HLS',
            episodes: [
              MediaEpisode(number: 1, title: '第 1 集'),
              MediaEpisode(number: 2, title: '第 2 集'),
              MediaEpisode(number: 3, title: '第 3 集'),
            ],
          ),
        ],
      ),
    ),
  );
}
