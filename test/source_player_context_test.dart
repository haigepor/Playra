import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/modules/roads/road_module.dart';

class _History implements HistoryController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements IDownloadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements IDownloadManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'source controls use real source identity and never require a Bangumi record',
    () {
      final controller = VideoPageController(
        _History(),
        _Repository(),
        _Manager(),
      );
      controller.bindSourcePlayer(
        const SourcePlayerContext(
          identity: 'miomedia:123',
          title: '电影',
          sourceName: '备用',
          referer: 'https://example.test/',
        ),
        [
          Road(name: '备用', data: ['miomedia:123:b:71'], identifier: ['HD中字']),
        ],
        const VideoEpisodeSelection(episode: 1, road: 0),
      );
      expect(controller.hasBangumiContext, false);
      expect(controller.currentHistoryIdentity, isNull);
      expect(controller.playbackWorkTitle, '电影');
      expect(controller.playbackMediaId, 'miomedia:123');
      expect(controller.playbackSourceName, '备用');
      expect(controller.playbackArtwork, isNull);
      expect(controller.playbackReferer, 'https://example.test/');
      expect(
        controller.resolveEpisode(controller.playbackEpisode)?.pageUrl,
        'miomedia:123:b:71',
      );
      expect(controller.loading, false);
    },
  );
}
