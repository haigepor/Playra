import 'dart:async';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'source_policy.dart';
import 'source_sdk_group.dart';

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
      normalizeWorkTitle(title).isNotEmpty &&
      titles(work).map(normalizeWorkTitle).contains(normalizeWorkTitle(title));

  /// 只尝试资料已确认的名称；中文别名优先，不截短季号或放宽为子串匹配。
  List<String> searchTitles(BangumiItem work) {
    final names = [
      work.nameCn,
      ...work.alias.where((s) => RegExp(r'[\u3400-\u9fff]').hasMatch(s)),
      work.name,
      ...work.alias,
    ];
    final seen = <String>{};
    return names
        .where((s) {
          final key = normalizeWorkTitle(s);
          return key.isNotEmpty && seen.add(key);
        })
        .map((s) => s.trim())
        .take(4)
        .toList();
  }

  /// 所有自动入口共用有界别名回退；首个有精确同作品候选的搜索页即可停止。
  Future<List<SearchItem>> searchMatches(
    BangumiItem work,
    Plugin plugin, {
    RuleCancelToken? cancelToken,
  }) async {
    final searchCancel = RuleCancelToken();
    if (cancelToken != null) {
      if (cancelToken.isCancelled) return [];
      unawaited(
        cancelToken.whenCancel.then(
          (_) => searchCancel.cancel('parent cancelled'),
        ),
      );
    }
    final deadline = Timer(
      const Duration(seconds: 25),
      () => searchCancel.cancel('alias search timeout'),
    );
    Object? firstError;
    try {
      for (final keyword in searchTitles(work)) {
        if (searchCancel.isCancelled) break;
        try {
          final response = await plugin.queryBangumi(
            keyword,
            shouldRethrow: true,
            cancelToken: searchCancel,
          );
          if (searchCancel.isCancelled) break;
          final seen = <String>{};
          final matched = response.data
              .where(
                (item) =>
                    matches(work, item.name) &&
                    item.src.trim().isNotEmpty &&
                    seen.add(item.src),
              )
              .toList();
          if (matched.isNotEmpty) return matched;
        } on NoResultException {
          // Plugin以异常表示合法空结果；继续别名，不将它归为网络/目录失败。
          continue;
        } catch (error) {
          firstError ??= error;
        }
      }
      if (cancelToken?.isCancelled == true) return [];
      // 部分别名查询失败不能宣称已确认无作品。
      if (firstError != null) throw firstError;
      if (searchCancel.isCancelled)
        throw TimeoutException('alias search timeout');
      return [];
    } finally {
      deadline.cancel();
      searchCancel.cancel('alias search finished');
    }
  }

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
                  e.value.candidate.plugin.version &&
              matches(work, e.value.candidate.item.name),
        )
        .map((e) {
          final candidate = e.value.candidate;
          return candidate.matched
              ? candidate
              : PlaybackCandidate(
                  plugin: candidate.plugin,
                  item: candidate.item,
                  roads: candidate.roads,
                  matched: true,
                );
        })
        .toList();
    result.sort((a, b) {
      final priority = (automaticPlaybackPriority(a.plugin) ?? 100).compareTo(
        automaticPlaybackPriority(b.plugin) ?? 100,
      );
      if (priority != 0) return priority;
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
    void Function(PlaybackCandidate)? onPrepared,
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
            roads.add(
              Road(id: road.id, name: road.name, data: data, identifier: names),
            );
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
      onPrepared?.call(candidates.last);
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
          final results = await searchMatches(
            work,
            plugin,
            cancelToken: cancelToken,
          );
          final candidates = await prepare(
            work,
            plugin,
            results,
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

  /// Kazumi 按固定主备顺序准备，其他分组继续按历史首帧表现优先调度。
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

    final sources = automaticPlaybackSources(eligible(plugins, work));
    if (sources.any((p) => playbackSdkId(p) == 'kazumi')) {
      // Kazumi 先查主来源再查备用，缓存命中或响应速度不能让备用抢先。
      // 每站准备最多八秒，使三个来源仍落在页面三十秒的总准备预算内。
      for (final plugin in sources) {
        if (cancelToken.isCancelled) return null;
        if (SourcePolicy.shared.coolingDown(plugin.providerId, plugin.version))
          continue;
        final cachedChoice = choose(cached(work, [plugin]));
        if (cachedChoice != null) return cachedChoice;
        final sourceCancel = RuleCancelToken();
        unawaited(
          cancelToken.whenCancel.then(
            (_) => sourceCancel.cancel('selection cancelled'),
          ),
        );
        Future<AutomaticEpisodeChoice?> prepareSource() async {
          final results = await searchMatches(
            work,
            plugin,
            cancelToken: sourceCancel,
          );
          if (sourceCancel.isCancelled) return null;
          final candidates = await prepare(
            work,
            plugin,
            results,
            cancelToken: sourceCancel,
          );
          return sourceCancel.isCancelled ? null : choose(candidates);
        }

        try {
          final choice = await Future.any([
            prepareSource(),
            cancelToken.whenCancel.then<AutomaticEpisodeChoice?>((_) => null),
          ]).timeout(const Duration(seconds: 8), onTimeout: () => null);
          if (cancelToken.isCancelled) return null;
          if (choice != null) return choice;
        } catch (_) {
          // 单站搜索/目录失败继续下一个优先来源，实际出画仍由播放器确认。
        } finally {
          sourceCancel.cancel('source preparation finished');
        }
      }
      return null;
    }

    final cachedChoice = choose(cached(work, sources));
    if (cachedChoice != null || cancelToken.isCancelled) return cachedChoice;
    final ready = Completer<AutomaticEpisodeChoice?>();
    final discovery = discover(
      work,
      sources,
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
