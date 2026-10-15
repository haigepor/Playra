import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';
import 'package:kazumi/utils/episode_url.dart';

/// 新版恢复只接受同作品、同站点、同详情 URL 与唯一剧集 URL。
/// 历史位置可能因站点补番/重排变化，不能直接使用旧列表索引。
({VideoEpisodeSelection selection, int offset})? verifiedResume(
  OnlineVideoPlaybackArgs args,
  Iterable<History> histories,
) {
  for (final history in histories) {
    if (history.bangumiItem.id != args.bangumiItem.id ||
        !matchesAnimeHistorySource(
          args.plugin,
          history.adapterName,
          history.lastSrc,
        ) ||
        history.entryKind != HistoryEntryKind.online ||
        normalizeEpisodeUrl(args.plugin.baseUrl, history.lastSrc) !=
            normalizeEpisodeUrl(args.plugin.baseUrl, args.src) ||
        history.episodePageUrl.isEmpty) {
      continue;
    }
    final matches = <VideoEpisodeSelection>[];
    for (var road = 0; road < args.roads.length; road++) {
      final data = args.roads[road];
      for (var i = 0; i < data.data.length && i < data.identifier.length; i++) {
        if (normalizeEpisodeUrl(args.plugin.baseUrl, data.data[i]) ==
            normalizeEpisodeUrl(args.plugin.baseUrl, history.episodePageUrl)) {
          matches.add(VideoEpisodeSelection(episode: i + 1, road: road));
        }
      }
    }
    if (matches.length != 1) return null;
    return (
      selection: matches.single,
      offset:
          history.progresses[history.lastWatchEpisode]?.progress.inSeconds ?? 0,
    );
  }
  return null;
}

/// 只用明确标题或正片集号映射到真实 Bangumi ID，拒绝 OVA 的数字回退。
EpisodeInfo? matchDiscussionEpisode(String title, List<EpisodeInfo> episodes) {
  final normalized = title.trim();
  if (normalized.isEmpty) return null;
  final named = episodes
      .where(
        (e) => e.id > 0 && (e.name == normalized || e.nameCn == normalized),
      )
      .toList();
  if (named.length == 1) return named.single;
  final match = RegExp(
    r'^(?:第\s*)?(\d+)(?:\s*[话話集])?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (match == null) return null;
  final number = int.parse(match.group(1)!);
  final candidates = episodes
      .where((e) => e.id > 0 && e.type == 0 && e.episode == number)
      .toList();
  return candidates.length == 1 ? candidates.single : null;
}
