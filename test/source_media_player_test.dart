import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/services/player/source_media_player.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Player implements Player {
  double rate = 1;
  int pauses = 0, plays = 0;
  @override
  Future<void> pause({bool sync = true}) async {
    pauses++;
  }

  @override
  Future<void> play({bool sync = true}) async {
    plays++;
  }

  @override
  Future<void> setRate(double value, {bool sync = true}) async => rate = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback implements PlayerPlaybackController {
  _Playback(this.url);
  final String Function() url;
  final current = _Player();
  int stops = 0, opens = 0;
  Map<String, String>? receivedHeaders;
  bool? receivedAdBlock;
  VideoSourceFormat? receivedFormat;
  void Function()? duringOpen;
  @override
  Player? get mediaPlayer => current;
  @override
  final VideoController videoController = _VideoController();
  @override
  void Function(String)? onMediaError;
  @override
  bool loading = true;
  @override
  Future<void> stop() async => stops++;
  @override
  void resetForInit() {}
  @override
  Future<Player?> createVideoController(
    Map<String, String> headers,
    bool adBlockerEnabled, {
    required bool Function() canInstall,
    int offset = 0,
    VideoSourceFormat videoSourceFormat = VideoSourceFormat.auto,
  }) async {
    opens++;
    receivedHeaders = headers;
    receivedAdBlock = adBlockerEnabled;
    receivedFormat = videoSourceFormat;
    duringOpen?.call();
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a paused quality switch keeps native playback paused without changing global settings',
    () async {
      late _Playback core;
      final player = SourceMediaPlayer(
        useWeb: false,
        createNative: (url, debug) => core = _Playback(url),
        defaultRate: () => 1,
        logLevel: () => 2,
      );
      await player.open(
        'https://media.example/1080.mp4',
        {},
        canInstall: () => true,
        onError: (_) {},
        play: false,
      );
      expect(core.current.pauses, 1);
      expect(core.current.plays, 0);
      await player.dispose();
    },
  );
  test(
    'native Mio playback delegates headers and configuration to the original core',
    () async {
      late _Playback core;
      final player = SourceMediaPlayer(
        useWeb: false,
        createNative: (url, debug) => core = _Playback(url),
        defaultRate: () => 1.5,
        logLevel: () => 2,
      );
      final opened = await player.open(
        'https://media.example/playlist?id=1',
        {'Referer': 'https://source.example/'},
        canInstall: () => true,
        onError: (_) {},
        videoSourceFormat: VideoSourceFormat.hls,
      );
      expect(opened, same(core.current));
      expect(core.url(), 'https://media.example/playlist?id=1');
      expect(core.receivedFormat, VideoSourceFormat.hls);
      expect(core.receivedHeaders, {'Referer': 'https://source.example/'});
      expect(core.receivedAdBlock, false);
      expect(core.current.rate, 1.5);
      expect(player.controller, same(core.videoController));
      expect(core.loading, false);
      await player.dispose();
      await player.dispose();
      expect(core.stops, 2); // 打开前清理一次，页面退出后释放一次。
    },
  );

  test(
    'cancelled initialization releases native resources and does not publish a controller',
    () async {
      var active = true;
      late _Playback core;
      final player = SourceMediaPlayer(
        useWeb: false,
        createNative: (url, debug) =>
            core = _Playback(url)..duringOpen = () => active = false,
        defaultRate: () => 1,
        logLevel: () => 2,
      );
      final opened = await player.open(
        'https://media.example/cancelled.mp4',
        {},
        canInstall: () => active,
        onError: (_) {},
      );
      expect(opened, isNull);
      expect(player.player, isNull);
      expect(player.controller, isNull);
      expect(core.stops, 2);
      await player.dispose();
    },
  );

  test('closed source session never creates a native player', () async {
    var creations = 0;
    final player = SourceMediaPlayer(
      useWeb: false,
      createNative: (url, debug) {
        creations++;
        return _Playback(url);
      },
      defaultRate: () => 1,
      logLevel: () => 2,
    );
    await player.dispose();
    expect(
      await player.open(
        'https://media.example/a.mp4',
        {},
        canInstall: () => true,
        onError: (_) {},
      ),
      isNull,
    );
    expect(creations, 0);
  });
}
