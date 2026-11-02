import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'content_search.dart';
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

/// 旧规则播放入口已退役；保留签名供历史调用者安全结束。
Future<PlaybackCandidate?> prepareSearchPlayback(
  BangumiItem item,
  ContentWork work,
  ContentSearchSession session,
  RuleCancelToken cancel,
) async => null;
