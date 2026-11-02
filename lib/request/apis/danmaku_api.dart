import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';

/// 保留旧播放器调用边界；弹幕来源及其网络协议已经移除。
class DanmakuApi {
  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(
    int episodeID,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }
}
