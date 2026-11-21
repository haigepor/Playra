import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/playback/playback_session.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// 播放器演示页：只验证保留的播放内核与播放器组件，不依赖任何内容源。
///
/// 新数据源接入后，用真实媒体替换 [demoStream] 并通过
/// [PlaybackInitParams] 传入即可。
class PlaybackDemoPage extends StatefulWidget {
  const PlaybackDemoPage({super.key});

  static const demoStream =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  @override
  State<PlaybackDemoPage> createState() => _PlaybackDemoPageState();
}

class _PlaybackDemoPageState extends State<PlaybackDemoPage> {
  late final ShaderAssetService _shaders;
  late final AudioController _audio;
  late final PlayerController _player;
  late final PlaybackSession _session;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'playback-demo');

  @override
  void initState() {
    super.initState();
    _shaders = ShaderAssetService();
    _audio = AudioController();
    _player = PlayerController(_shaders, _audio);
    _session = PlaybackSession(
      title: '播放器演示',
      sourceName: '内置演示流',
      mediaId: 'playback-demo',
      roads: [
        PlaybackRoad(
          name: '演示线路',
          episodes: [
            for (var i = 1; i <= 3; i++)
              PlaybackEpisode(
                title: '第 ${i.toString().padLeft(2, '0')} 集',
                url: PlaybackDemoPage.demoStream,
              ),
          ],
        ),
      ],
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    await _shaders.copyShadersToExternalDirectory();
    final episode = _session.resolveEpisode(_session.selectedEpisode);
    if (episode == null) return;
    await _player.init(
      PlaybackInitParams(
        videoUrl: episode.episode.url,
        workTitle: _session.title,
        episodeTitle: episode.displayTitle,
        sourceName: _session.playbackSourceName,
        isLocalPlayback: false,
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
  }) async {
    final selection = _session.selectEpisode(episode, road: currentRoad);
    final resolved = _session.resolveEpisode(selection);
    if (resolved == null) return;
    await _player.init(
      PlaybackInitParams(
        videoUrl: resolved.episode.url,
        workTitle: _session.title,
        episodeTitle: resolved.displayTitle,
        sourceName: _session.playbackSourceName,
        offset: offset,
      ),
    );
    if (!mounted) return;
    _session.markPlaying(selection.episode, road: selection.road);
    setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    _session.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<PlayraTokens>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: PlayerItem(
          playerController: _player,
          videoPageController: _session,
          fillsWindow: true,
          changeEpisode: _changeEpisode,
          onBackPressed: () => Navigator.of(context).pop(),
          keyboardFocus: _keyboardFocus,
          pauseForTimedShutdown: () => _player.pause(),
          disableAnimations:
              MediaQuery.maybeOf(context)?.disableAnimations ?? false,
        ),
      ),
      bottomNavigationBar: Container(
        color: t?.surface ?? Colors.black,
        padding: const EdgeInsets.fromLTRB(
          PlayraSpace.lg,
          PlayraSpace.sm,
          PlayraSpace.lg,
          PlayraSpace.sm,
        ),
        child: SafeArea(
          top: false,
          child: Text(
            '演示流：${PlaybackDemoPage.demoStream}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t?.mutedForeground ?? Colors.white70,
              fontSize: PlayraType.caption,
            ),
          ),
        ),
      ),
    );
  }
}
