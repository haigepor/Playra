import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Downloads extends Fake implements IDownloadRepository {}

class _DownloadManager extends Fake implements IDownloadManager {}

class _Frame extends Fake implements VideoController {
  final rendered = Completer<void>();
  @override
  Future<void> get waitUntilFirstFrameRendered => rendered.future;
}

class _Playback extends Fake implements PlayerPlaybackController {
  Player? measuredPlayer;
  @override
  void Function(String)? onMediaError;
  @override
  VideoController? videoController;
  @override
  Player? get mediaPlayer => measuredPlayer;
  @override
  bool get autoPlay => true;
  @override
  bool get startupSuspended => false;
  @override
  Duration get playerDuration => const Duration(minutes: 24);
  @override
  Duration get playerPosition => Duration.zero;
}

class _MeasuredPlayer extends Fake implements Player {
  _MeasuredPlayer(this.state);
  @override
  final PlayerState state;
}

class _Danmaku extends Fake implements PlayerDanmakuController {
  @override
  void finishDanmakuLoad({bool disableDanmaku = false}) {}
  @override
  void beginDanmakuLoad() {}
  @override
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode,
  ) async => DanmakuLoadResult.success(danmakus: [], bangumiID: bangumiId);
  @override
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {}
}

class _Player extends Fake implements PlayerController {
  @override
  final playback = _Playback();
  @override
  final danmaku = _Danmaku();
  final frames = <_Frame>[];
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration position, {bool enableSync = true}) async =>
      seeks.add(position);
  @override
  Future<void> stop() async {}
  @override
  Future<bool> init(PlaybackInitParams params) async {
    final frame = _Frame();
    frames.add(frame);
    playback.videoController = frame;
    return true;
  }
}

class _Video extends VideoPageController {
  _Video(HistoryController history)
    : super(history, _Downloads(), _DownloadManager());
  final _fullscreen = VideoFullscreenController(applyFullscreen: (_) async {});
  @override
  VideoFullscreenController get fullscreen => _fullscreen;
}

const _source = VideoSource(
  url: 'https://media.example/episode.mp4',
  offset: 0,
  type: VideoSourceType.online,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_startup_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(directory.parent.path, Directory.systemTemp.path);
    expect(
      directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
      startsWith('playra_startup_'),
    );
    await directory.delete(recursive: true);
  });

  late _Video video;
  late _Player player;
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    video = _Video(
      HistoryController(HistoryRepository(historiesBox: GStorage.histories)),
    );
    player = _Player();
    video.applyPlaybackArgs(
      OnlineVideoPlaybackArgs(
        bangumiItem: BangumiItem.fromJson({
          'id': 900502,
          'type': 2,
          'name': 'startup regression',
          'rating': <String, dynamic>{},
          'images': <String, dynamic>{},
        }),
        plugin: Plugin.fromJson({
          'api': '8',
          'type': 'anime',
          'name': 'startup-test',
          'sourceId': 'startup-test',
          'baseURL': 'https://anime.example/',
        }),
        title: 'startup regression',
        src: '/work',
        roads: [
          Road(
            id: '2',
            name: 'road 2',
            data: ['/episode/1', '/episode/2'],
            identifier: ['第1集', '第2集'],
          ),
        ],
      ),
    );
  });

  Future<void> start(
    WidgetTester tester,
    int episode, {
    int offset = 0,
    Duration? expectedDuration,
  }) async {
    // 保留真实 changeEpisode 状态机；只替换媒体设备和已解析地址。
    unawaited(
      video.changeEpisode(
        episode,
        playerController: player,
        offset: offset,
        expectedDuration: expectedDuration,
        preparedSource: offset == 0
            ? _source
            : VideoSource(url: _source.url, offset: offset, type: _source.type),
      ),
    );
    for (var i = 0; i < 10 && player.frames.length < episode; i++) {
      // StreamSubscription.cancel 的完成可能来自创建流时的外层 zone。
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(player.frames.length, episode);
  }

  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  tearDown(() => video.dispose());

  void kazumi({required bool automatic, int? width, int? height}) {
    video.currentPlugin = Plugin.fromJson(
      jsonDecode(
        File('assets/plugins/akianime.json').readAsStringSync(encoding: utf8),
      ),
    );
    video.automaticSource = automatic;
    // 特别篇不能跨站猜集号，失败应停留在本次清晰度结论。
    video.roadList
      ..clear()
      ..add(
        Road(id: '2', name: '官方首线', data: ['/episode/sp'], identifier: ['特别篇']),
      );
    (player.playback as _Playback).measuredPlayer = _MeasuredPlayer(
      PlayerState(width: width, height: height),
    );
  }

  testWidgets('Kazumi automatic rejects a three second Full HD placeholder', (
    tester,
  ) async {
    kazumi(automatic: true, width: 1920, height: 1080);
    (player.playback as _Playback).measuredPlayer = _MeasuredPlayer(
      PlayerState(
        width: 1920,
        height: 1080,
        duration: const Duration(seconds: 3),
      ),
    );
    await start(tester, 1);
    player.frames.single.rendered.complete();
    await tester.pump();
    await advance(tester, 1);
    expect(video.playingEpisode, isNull);
    expect(video.errorMessage, contains('短片段'));
  });

  testWidgets('Kazumi automatic rejects a real 720p first frame', (
    tester,
  ) async {
    kazumi(automatic: true, width: 1280, height: 720);
    await start(tester, 1);
    player.frames.single.rendered.complete();
    await tester.pump();
    await advance(tester, 1);
    expect(video.playingEpisode, isNull);
    expect(video.errorMessage, contains('1080p'));
    expect(video.activeRouteLabel, isNull);
  });

  testWidgets('Kazumi automatic cannot treat missing dimensions as 1080p', (
    tester,
  ) async {
    kazumi(automatic: true);
    await start(tester, 1);
    player.frames.single.rendered.complete();
    await tester.pump();
    await advance(tester, 4);
    expect(video.playingEpisode, isNull);
    expect(video.errorMessage, contains('无法确认达到 1080p'));
  });

  testWidgets(
    'Kazumi manual still accepts low quality without changing its line lock',
    (tester) async {
      kazumi(automatic: false, width: 1280, height: 720);
      await start(tester, 1);
      player.frames.single.rendered.complete();
      await tester.pump();
      await advance(tester, 1);
      expect(video.playingEpisode, isNotNull);
      expect(video.automaticSource, isFalse);
      expect(video.activeRouteLabel, contains('1280×720'));
    },
  );

  testWidgets(
    'Kazumi automatic accepts verified Full HD and displays actual dimensions',
    (tester) async {
      kazumi(automatic: true, width: 1920, height: 1080);
      await start(tester, 1);
      player.frames.single.rendered.complete();
      await tester.pump();
      await advance(tester, 1);
      expect(video.playingEpisode, isNotNull);
      expect(video.errorMessage, isNull);
      expect(video.activeRouteLabel, contains('1920×1080'));
    },
  );

  testWidgets(
    'native media is still starting before the shared 25 second deadline',
    (tester) async {
      await start(tester, 1);
      await advance(tester, 20);
      expect(video.errorMessage, isNull);
      expect(video.loading, isTrue);
      player.frames.single.rendered.complete();
      await tester.pump();
      await advance(tester, 1);
      expect(
        video.playingEpisode,
        const VideoEpisodeSelection(episode: 1, road: 0),
      );
      expect(video.loading, isFalse);
    },
  );

  testWidgets(
    'late first frame from the current media clears only startup timeout',
    (tester) async {
      await start(tester, 1);
      await advance(tester, 26);
      expect(video.errorMessage, isNotNull);
      expect(video.playingEpisode, isNull);
      player.frames.single.rendered.complete();
      await tester.pump();
      expect(video.errorMessage, isNull);
      expect(video.loading, isFalse);
      expect(
        video.playingEpisode,
        const VideoEpisodeSelection(episode: 1, road: 0),
      );
      expect(video.activeRoadId, '2');
      expect(video.automaticSource, isFalse);
    },
  );

  testWidgets('old episode late frame cannot clear the current media failure', (
    tester,
  ) async {
    await start(
      tester,
      1,
      offset: 98,
      expectedDuration: const Duration(minutes: 24),
    );
    await advance(tester, 26);
    await start(tester, 2);
    player.playback.onMediaError!('HTTP 403');
    await advance(tester, 1);
    final error = video.errorMessage;
    expect(error, isNotNull);
    player.frames.first.rendered.complete();
    await tester.pump();
    expect(video.errorMessage, error);
    expect(
      video.selectedEpisode,
      const VideoEpisodeSelection(episode: 2, road: 0),
    );
    expect(video.playingEpisode, isNull);
    expect(player.seeks, isEmpty);
  });

  testWidgets('real media errors survive a late frame from that media', (
    tester,
  ) async {
    await start(tester, 1);
    player.playback.onMediaError!('HTTP 403');
    await advance(tester, 1);
    final error = video.errorMessage;
    expect(error, isNotNull);
    expect(error, isNot(contains('解析失败')));
    player.frames.single.rendered.complete();
    await tester.pump();
    expect(video.errorMessage, error);
    expect(video.playingEpisode, isNull);
  });

  testWidgets(
    'cancelled session late frame cannot recover the abandoned playback',
    (tester) async {
      await start(tester, 1);
      await advance(tester, 26);
      final error = video.errorMessage;
      expect(error, isNotNull);
      video.cancelPendingPlayback();
      player.frames.single.rendered.complete();
      await tester.pump();
      expect(video.errorMessage, error);
      expect(video.playingEpisode, isNull);
      expect(video.activeRoadId, isNull);
    },
  );

  testWidgets('media error after startup timeout still blocks late recovery', (
    tester,
  ) async {
    await start(tester, 1);
    await advance(tester, 26);
    expect(video.errorMessage, isNotNull);
    player.playback.onMediaError!('HTTP 403');
    await tester.pump();
    final mediaError = video.errorMessage;
    player.frames.single.rendered.complete();
    await tester.pump();
    expect(video.errorMessage, mediaError);
    expect(video.errorMessage, isNotNull);
    expect(video.playingEpisode, isNull);
  });

  testWidgets(
    'late first frame restores compatible progress after duration check',
    (tester) async {
      await start(
        tester,
        1,
        offset: 98,
        expectedDuration: const Duration(minutes: 24),
      );
      await advance(tester, 26);
      expect(video.errorMessage, isNotNull);
      expect(player.seeks, isEmpty);
      player.frames.single.rendered.complete();
      await tester.pump();
      expect(player.seeks, [const Duration(seconds: 98)]);
      expect(video.errorMessage, isNull);
      expect(
        video.playingEpisode,
        const VideoEpisodeSelection(episode: 1, road: 0),
      );
    },
  );

  testWidgets(
    'late frame never restores progress from an incompatible duration',
    (tester) async {
      await start(
        tester,
        1,
        offset: 98,
        expectedDuration: const Duration(minutes: 90),
      );
      await advance(tester, 26);
      expect(video.errorMessage, isNotNull);
      player.frames.single.rendered.complete();
      await tester.pump();
      expect(player.seeks, isEmpty);
      expect(video.errorMessage, isNull);
      expect(
        video.playingEpisode,
        const VideoEpisodeSelection(episode: 1, road: 0),
      );
    },
  );
}
