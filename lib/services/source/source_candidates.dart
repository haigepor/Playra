import 'dart:async';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'source_policy.dart';

String normalizeWorkTitle(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]', unicode: true),
  '',
);

/// 保留季号和特别篇；跨来源只用明确正片集号，不用列表位置。
int? regularEpisodeNumber(String title) {
  final match = RegExp(
    r'^(?:第\s*|ep\s*)?(\d+)(?:\s*[集话話])?$',
    caseSensitive: false,
  ).firstMatch(title.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}

String workDomain(BangumiItem item) => item.type == 2
    ? 'anime'
    : item.type == 6
    ? 'screen'
    : 'unknown';

class PlaybackCandidate {
  const PlaybackCandidate({
    required this.plugin,
    required this.item,
    required this.roads,
    required this.matched,
  });
  final Plugin plugin;
  final SearchItem item;
  final List<Road> roads;
  final bool matched;
  bool confirmsMissingEpisode(int number) {
    final numbers = roads
        .expand((r) => r.identifier)
        .map(regularEpisodeNumber)
        .toList();
    return numbers.isNotEmpty &&
        numbers.every((n) => n != null) &&
        !numbers.contains(number);
  }

  OnlineVideoPlaybackArgs args(BangumiItem work, {bool automatic = false}) =>
      OnlineVideoPlaybackArgs(
        bangumiItem: work,
        plugin: plugin,
        title: item.name,
        src: item.src,
        roads: roads,
        automatic: automatic,
      );
  ({int road, int episode})? matchEpisode(int number) {
    final matches = episodeMatches(number);
    return matches.isEmpty ? null : matches.first;
  }

  List<({int road, int episode})> episodeMatches(int number) {
    final result = <({int road, int episode})>[];
    for (var r = 0; r < roads.length; r++) {
      final matches = <int>[];
      for (var i = 0; i < roads[r].identifier.length; i++) {
        if (regularEpisodeNumber(roads[r].identifier[i]) == number) {
          matches.add(i + 1);
        }
      }
      if (matches.length == 1) result.add((road: r, episode: matches.single));
    }
    return result;
  }
}

typedef AutomaticEpisodeChoice = ({
  PlaybackCandidate candidate,
  int road,
  int episode,
});

class SourceCandidates {
  SourceCandidates();
  static final shared = SourceCandidates();
  final Map<String, ({DateTime at, PlaybackCandidate candidate})> _cache = {};
  String _key(BangumiItem work, Plugin plugin, String src) =>
      '${work.id}|${plugin.providerId}|${plugin.version}|$src';
  List<String> titles(BangumiItem work) => [
    work.name,
    work.nameCn,
    ...work.alias,
  ].where((s) => s.trim().isNotEmpty).toList();
  bool matches(BangumiItem work, String title) =>
      titles(work).map(normalizeWorkTitle).contains(normalizeWorkTitle(title));
  List<Plugin> eligible(Iterable<Plugin> plugins, BangumiItem work) => plugins
      .where((p) => p.enabled && p.profile.supports(workDomain(work)))
      .toList();
  List<PlaybackCandidate> cached(BangumiItem work, Iterable<Plugin> plugins) {
    final allowed = eligible(plugins, work);
    final versions = {for (final p in allowed) p.providerId: p.version};
    final order = {
      for (var i = 0; i < allowed.length; i++) allowed[i].providerId: i,
    };
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _cache.removeWhere((_, entry) => entry.at.isBefore(cutoff));
    final result = _cache.entries
        .where(
          (e) =>
              e.key.startsWith('${work.id}|') &&
              versions[e.value.candidate.plugin.providerId] ==
                  e.value.candidate.plugin.version,
        )
        .map((e) => e.value.candidate)
        .toList();
    result.sort((a, b) {
      final score = SourcePolicy.shared
          .score(a.plugin.providerId, a.plugin.version)
          .compareTo(
            SourcePolicy.shared.score(b.plugin.providerId, b.plugin.version),
          );
      return score != 0
          ? score
          : order[a.plugin.providerId]!.compareTo(order[b.plugin.providerId]!);
    });
    return result;
  }

  PlaybackCandidate? find(BangumiItem work, Plugin plugin, String src) {
    final key = _key(work, plugin, src);
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) >= const Duration(minutes: 5)) {
      _cache.remove(key);
      return null;
    }
    return entry.candidate;
  }

  void invalidate(BangumiItem work, Plugin plugin) => _cache.removeWhere(
    (key, _) => key.startsWith('${work.id}|${plugin.providerId}|'),
  );

  Future<List<PlaybackCandidate>> prepare(
    BangumiItem work,
    Plugin plugin,
    List<SearchItem> results, {
    RuleCancelToken? cancelToken,
    bool allowUnmatched = false,
  }) async {
    final candidates = <PlaybackCandidate>[];
    Object? firstError;
    for (final item in results) {
      final matched = matches(work, item.name);
      if (!matched && !allowUnmatched) continue;
      if (cancelToken?.isCancelled == true) break;
      final key = _key(work, plugin, item.src);
      var candidate = find(work, plugin, item.src);
      if (candidate == null) {
        final List<Road> raw;
        try {
          raw = await plugin.queryChapterRoads(
            item.src,
            cancelToken: cancelToken,
          );
        } catch (error) {
          if (cancelToken?.isCancelled == true) break;
          firstError ??= error;
          continue;
        }
        if (cancelToken?.isCancelled == true) break;
        final roads = <Road>[];
        for (final road in raw) {
          final data = <String>[], names = <String>[];
          for (
            var i = 0;
            i < road.data.length && i < road.identifier.length;
            i++
          ) {
            if (road.data[i].trim().isEmpty ||
                road.identifier[i].trim().isEmpty) {
              continue;
            }
            data.add(road.data[i]);
            names.add(road.identifier[i]);
          }
          if (data.isNotEmpty) {
            roads.add(Road(name: road.name, data: data, identifier: names));
          }
        }
        if (roads.isEmpty) continue;
        candidate = PlaybackCandidate(
          plugin: plugin,
          item: item,
          roads: roads,
          matched: matched,
        );
        _cache[key] = (at: DateTime.now(), candidate: candidate);
        // 缓存只保留有限条目，不携带解析后的媒体地址或鉴权信息。
        if (_cache.length > 128) _cache.remove(_cache.keys.first);
      }
      // 人工关键词检索与自动检索可能共享目录，但匹配结论按当前作品重新计算。
      candidates.add(
        PlaybackCandidate(
          plugin: plugin,
          item: item,
          roads: candidate.roads,
          matched: matched,
        ),
      );
    }
    // 只有确认无剧集才隐藏；目录请求失败必须保留重试入口。
    if (candidates.isEmpty && firstError != null) throw firstError;
    return candidates;
  }

  Future<List<PlaybackCandidate>> discover(
    BangumiItem work,
    List<Plugin> plugins,
    RuleCancelToken cancelToken, {
    void Function(List<PlaybackCandidate>)? onPrepared,
  }) async {
    final sources = eligible(plugins, work)
      ..sort(
        (a, b) => SourcePolicy.shared
            .score(a.providerId, a.version)
            .compareTo(SourcePolicy.shared.score(b.providerId, b.version)),
      );
    var next = 0;
    Future<void> worker() async {
      while (!cancelToken.isCancelled && next < sources.length) {
        final plugin = sources[next++];
        try {
          final response = await plugin.queryBangumi(
            work.nameCn.isEmpty ? work.name : work.nameCn,
            shouldRethrow: true,
            cancelToken: cancelToken,
          );
          final candidates = await prepare(
            work,
            plugin,
            response.data,
            cancelToken: cancelToken,
          );
          if (!cancelToken.isCancelled) onPrepared?.call(candidates);
        } catch (_) {
          /* 单个来源故障不阻断其他候选；取消由会话判断。 */
        }
      }
    }

    await Future.wait(
      List.generate(sources.length.clamp(0, 4), (_) => worker()),
    );
    return cached(work, plugins);
  }

  /// 按历史首帧表现优先调度；首个确认同作品同集的候选即可交给播放会话。
  /// 不等待全部规则超时，也不将源列表位置当成资料接口的集号。
  Future<AutomaticEpisodeChoice?> selectEpisode(
    BangumiItem work,
    List<Plugin> plugins,
    int number,
    RuleCancelToken cancelToken,
  ) async {
    AutomaticEpisodeChoice? choose(List<PlaybackCandidate> candidates) {
      for (final candidate in candidates) {
        if (!candidate.matched ||
            SourcePolicy.shared.coolingDown(
              candidate.plugin.providerId,
              candidate.plugin.version,
            ) ||
            candidates
                    .where(
                      (c) => c.plugin.providerId == candidate.plugin.providerId,
                    )
                    .length !=
                1) {
          continue;
        }
        final target = candidate.matchEpisode(number);
        if (target != null) {
          return (
            candidate: candidate,
            road: target.road,
            episode: target.episode,
          );
        }
      }
      return null;
    }

    final cachedChoice = choose(cached(work, plugins));
    if (cachedChoice != null || cancelToken.isCancelled) return cachedChoice;
    final ready = Completer<AutomaticEpisodeChoice?>();
    final discovery = discover(
      work,
      plugins,
      cancelToken,
      onPrepared: (items) {
        final choice = choose(items);
        if (choice != null && !ready.isCompleted) ready.complete(choice);
      },
    );
    return Future.any([
      ready.future,
      discovery.then((items) => cancelToken.isCancelled ? null : choose(items)),
      cancelToken.whenCancel.then((_) => null),
    ]);
  }
}
