import 'dart:async';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'content_search.dart';
import 'content_providers.dart';
import 'source_candidates.dart';

/// 精确片名优先于别名；已知年份冲突和同名多身份不能随机取第一条。
BangumiItem? uniqueAnimeMetadata(ContentHit hit, Iterable<BangumiItem> items) {
  final names = [
    hit.title,
    ...hit.aliases,
  ].map(contentTitleKey).where((n) => n.isNotEmpty).toSet();
  final candidates = <int, BangumiItem>{
    for (final item in items)
      if (item.type == 2 &&
          (hit.year == null ||
              DateTime.tryParse(item.airDate)?.year == hit.year) &&
          [
            item.nameCn,
            item.name,
            ...item.alias,
          ].map(contentTitleKey).any(names.contains))
        item.id: item,
  }.values.toList();
  final exact = candidates
      .where(
        (item) =>
            contentTitleKey(item.nameCn.isEmpty ? item.name : item.nameCn) ==
            contentTitleKey(hit.title),
      )
      .toList();
  if (exact.length == 1) return exact.single;
  return candidates.length == 1 ? candidates.single : null;
}

/// 优先复用搜索命中引用；首个有效目录即可入场，其余请求由调用者取消。
Future<PlaybackCandidate?> prepareSearchPlayback(
  BangumiItem item,
  ContentWork work,
  ContentSearchSession session,
  RuleCancelToken cancel,
) async {
  final providers = session.providers
      .whereType<RuleContentProvider>()
      .where((p) => p.plugin.enabled && p.groups.contains(ContentGroup.anime))
      .toList();
  final explicit = work.hits
      .where((h) => providers.any((p) => p.id == h.providerId))
      .toList();
  final hits = explicit.isNotEmpty
      ? explicit
      : session.works
            .expand((w) => w.hits)
            .where(
              (h) =>
                  work.suggests(h) &&
                  providers.any((p) => p.id == h.providerId),
            )
            .toList();
  final active = explicit.isEmpty
      ? providers
      : providers
            .where((p) => explicit.any((h) => h.providerId == p.id))
            .toList();
  final ready = Completer<PlaybackCandidate?>();
  final pending = <Future<void>>[];
  for (final provider in active) {
    pending.add(() async {
      try {
        final known = hits.where((h) => h.providerId == provider.id).toList();
        final results = known.isNotEmpty
            ? known
                  .map((h) => SearchItem(name: h.title, src: h.contentId))
                  .toList()
            : (await provider.plugin.queryBangumi(
                item.nameCn.isEmpty ? item.name : item.nameCn,
                shouldRethrow: true,
                cancelToken: cancel,
              )).data;
        final matched = results
            .where((r) => SourceCandidates.shared.matches(item, r.name))
            .toList();
        // 非显式点选来源时，同一来源的多条同名引用不能自动猜选。
        if (matched.length != 1 || cancel.isCancelled) return;
        await SourceCandidates.shared.prepare(
          item,
          provider.plugin,
          matched,
          cancelToken: cancel,
          onPrepared: (candidate) {
            if (!cancel.isCancelled &&
                candidate.matched &&
                candidate.roads.isNotEmpty &&
                !ready.isCompleted) {
              ready.complete(candidate);
            }
          },
        );
      } catch (_) {
        /* 单源失败不阻断其他来源，整体失败由调用者展示。 */
      }
    }());
  }
  // 成功和全部失败共用一个结果，避免最后一个来源完成时空结果抢先返回。
  unawaited(
    Future.wait(pending).then((_) {
      if (!ready.isCompleted) ready.complete(null);
    }),
  );
  return Future.any<PlaybackCandidate?>([
    ready.future,
    cancel.whenCancel.then((_) => null),
  ]).timeout(
    const Duration(seconds: 25),
    onTimeout: () {
      cancel.cancel('preload timeout');
      return null;
    },
  );
}
