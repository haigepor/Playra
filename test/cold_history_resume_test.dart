import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/pages/player/controller/player_syncplay_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/playback_scaffold.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Downloads extends Fake implements DownloadController {}

class _DownloadRepository extends Fake implements IDownloadRepository {}

class _DownloadManager extends Fake implements IDownloadManager {}

class _LoadingPlayback extends Fake implements PlayerPlaybackController {
  // 留在加载视图，测试真实外壳的恢复决策，不创建原生媒体播放器。
  @override
  bool get loading => true;
}

class _SyncPlay extends Fake implements PlayerSyncPlayController {
  @override
  Stream<SyncPlayChatMessage> get chatStream => const Stream.empty();
}

class _Player extends Fake implements PlayerController {
  @override
  final PlayerPlaybackController playback = _LoadingPlayback();
  @override
  final PlayerSyncPlayController syncplay = _SyncPlay();
  @override
  Future<void> stop() async {}
}

class _RecordingVideo extends VideoPageController {
  _RecordingVideo(HistoryController history)
    : super(history, _DownloadRepository(), _DownloadManager());

  final starts = <({int episode, int road, int offset})>[];
  @override
  final fullscreen = VideoFullscreenController(applyFullscreen: (_) async {});

  @override
  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
    bool fromRecovery = false,
    Duration? expectedDuration,
    VideoSource? preparedSource,
  }) async {
    starts.add((episode: episode, road: currentRoad, offset: offset));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late HistoryRepository repository;
  late OnlineVideoPlaybackArgs args;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra_cold_history_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    await GStorage.putSetting(SettingsKeys.playResume, true);
    await GStorage.putSetting(SettingsKeys.playerDisableAnimations, true);

    final work = BangumiItem.fromJson({
      'id': 900402,
      'type': 2,
      'name': '航海王',
      'name_cn': '航海王',
      'rating': <String, dynamic>{},
      'images': <String, dynamic>{},
    });
    final plugin = Plugin.fromJson({
      'api': '8',
      'type': 'anime',
      'name': 'cold-history-source',
      'sourceId': 'cold-history-source',
      'baseURL': 'https://anime.example/',
    });
    args = OnlineVideoPlaybackArgs(
      bangumiItem: work,
      plugin: plugin,
      title: '航海王',
      src: '/anime/one-piece',
      roads: [
        Road(
          id: '2',
          name: '线路2',
          data: ['/anime/one-piece/1', '/anime/one-piece/2'],
          identifier: ['第1集', '第2集'],
        ),
      ],
    );
    final history = History(
      work,
      2,
      plugin.name,
      DateTime(2026, 10, 15),
      args.src,
      '第2集',
      episodePageUrl: '/anime/one-piece/2',
    )..progresses[2] = Progress(2, 0, 344000);
    await GStorage.histories.put(history.key, history);
    repository = HistoryRepository(historiesBox: GStorage.histories);

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => call.method == 'isFullScreen' ? false : null,
    );
  });

  tearDownAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    );
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('playra_cold_history_'),
    );
    await directory.delete(recursive: true);
  });

  testWidgets(
    'cold playback restores episode URL and progress before history page initialization',
    (tester) async {
      final history = HistoryController(repository);
      final video = _RecordingVideo(history);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        video.dispose();
        await tester.pump();
      });
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 首页直接读仓库可以看到第2集，但冷启动尚未打开历史页，内存列表仍为空。
      expect(repository.getAllHistories().single.lastWatchEpisode, 2);
      expect(
        history.lastWatching(args.bangumiItem, args.plugin.name)?.episode,
        2,
      );
      expect(history.histories, isEmpty);
      expect(verifiedResume(args, repository.getAllHistories())?.offset, 344);

      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackScaffold(
            args: args,
            verifyHistoryIdentity: true,
            playerController: _Player(),
            videoPageController: video,
            historyController: history,
            downloadController: _Downloads(),
            contentBuilder: (_, _) => const SizedBox(),
          ),
        ),
      );
      // 加载占位有循环动画，仅推进初始化回调，不等待媒体解码或所有动画停止。
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(video.starts, [
        (episode: 2, road: 0, offset: 344),
      ], reason: '恢复必须读取持久历史中的唯一剧集 URL，不能因内存列表未初始化而播放首集。');
    },
  );
}
