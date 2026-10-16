import 'home_anime_card.dart';

/// 一次浏览只补齐空位或追加内容；换批/刷新才采纳新的推荐顺序。
class HomeDisplaySession {
  final _pools = <String, List<HomeAnimeCard>>{};
  final _seen = <String, Set<String>>{};
  final _snapshots = <String, List<HomeAnimeCard>>{};
  final _primary = <String, bool>{};

  List<HomeAnimeCard> append(String key, List<HomeAnimeCard> incoming) {
    final pool = _pools.putIfAbsent(key, () => []);
    final seen = _seen.putIfAbsent(key, () => {});
    final before = pool.length;
    pool.addAll(incoming.where((item) => seen.add(item.id)));
    if (pool.length != before || !_snapshots.containsKey(key)) {
      _snapshots[key] = List.unmodifiable(pool);
    }
    return _snapshots[key]!;
  }

  List<HomeAnimeCard> anime(
    String key,
    List<HomeAnimeCard> preferred,
    List<HomeAnimeCard> fallback, {
    required bool waitingForPrimary,
  }) {
    if (!_primary.containsKey(key)) {
      if (preferred.isNotEmpty) {
        _primary[key] = true;
      } else if (!waitingForPrimary && fallback.isNotEmpty) {
        _primary[key] = false;
      }
    }
    return append(key, switch (_primary[key]) {
      true => preferred,
      false => fallback,
      null => const [],
    });
  }

  static List<HomeAnimeCard?> featured(
    List<HomeAnimeCard> anime,
    List<HomeAnimeCard> movies,
    List<HomeAnimeCard> series, {
    required bool mixed,
  }) {
    HomeAnimeCard? at(List<HomeAnimeCard> items, int index) =>
        index < items.length ? items[index] : null;
    // 预留影视位置，异步结果不能把已经可读的动漫卡片挤到下一行。
    return mixed
        ? [at(anime, 0), at(movies, 0), at(anime, 1), at(series, 0)]
        : List.generate(4, (index) => at(anime, index));
  }
}
