import 'dart:math' as math;
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

enum HomeAnimeBucket { all, season, japanese, chinese, movies }

/// 首页资料独立于 Hive 持久化模型；分类不能依赖标题或搜索词猜测。
class HomeSubject {
  const HomeSubject({
    required this.item,
    required this.platform,
    required this.countries,
    required this.releaseDate,
    this.nsfw = false,
    this.sourceListed = false,
    this.collections = 0,
  });
  final BangumiItem item;
  final String platform;
  final Set<String> countries;
  final DateTime? releaseDate;
  final bool nsfw, sourceListed;
  final int collections;

  bool get isMovie => const ['剧场版', 'Movie', '电影'].contains(platform);
  bool get isSeries => const ['TV', 'WEB', 'Web', 'OVA'].contains(platform);

  static DateTime? parseDate(Object? value) {
    final text = value?.toString() ?? '';
    final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match[1]!),
        month = int.parse(match[2]!),
        day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  factory HomeSubject.fromJson(
    Map<String, dynamic> raw, {
    bool sourceListed = false,
  }) {
    final json = Map<String, dynamic>.from(raw);
    final meta = (raw['meta_tags'] ?? raw['metaTags'] ?? const []) as List;
    final tags = meta.whereType<String>().toSet();
    var platform = raw['platform']?.toString() ?? '';
    if (platform.isEmpty) {
      platform =
          const [
            '剧场版',
            'Movie',
            'TV',
            'WEB',
            'OVA',
          ].where(tags.contains).firstOrNull ??
          '';
    }
    var date = parseDate(
      raw['date'] ?? (raw['airtime'] is Map ? raw['airtime']['date'] : null),
    );
    // Next 日历在 info 中提供首播日期；仅解析完整年月日，不推导放送星期。
    if (date == null) {
      final match = RegExp(
        r'(?:^|/)\s*(\d{4})年(\d{1,2})月(\d{1,2})日',
      ).firstMatch(raw['info']?.toString() ?? '');
      if (match != null)
        date = parseDate('${match[1]}-${match[2]}-${match[3]}');
    }
    if (date != null) {
      json['date'] =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    json['metaTags'] = tags.toList();
    json['rating'] ??= {'score': 0.0, 'rank': 0, 'total': 0};
    json['images'] ??= <String, String>{};
    json['info'] ??= [
      platform,
      json['date'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final collection = raw['collection'];
    final collections = collection is Map
        ? collection.values.whereType<num>().fold<int>(
            0,
            (sum, n) => sum + n.toInt(),
          )
        : (raw['collection_total'] as num?)?.toInt() ?? 0;
    return HomeSubject(
      item: BangumiItem.fromJson(json),
      platform: platform,
      countries: tags.intersection({'中国', '日本'}),
      releaseDate: date,
      nsfw: raw['nsfw'] == true,
      sourceListed: sourceListed,
      collections: collections,
    );
  }

  HomeSubject withSource() => HomeSubject(
    item: item,
    platform: platform,
    countries: countries,
    releaseDate: releaseDate,
    nsfw: nsfw,
    sourceListed: true,
    collections: collections,
  );
}

class HomeChannel {
  const HomeChannel(this.id, this.title, this.allItems);
  final String id, title;
  final List<BangumiItem> allItems;
  List<BangumiItem> get items => allItems.take(20).toList();
}

class HomeContentAlgorithm {
  HomeContentAlgorithm(Iterable<HomeSubject> candidates, {DateTime? today})
    : today = _dateOnly(today ?? DateTime.now()) {
    final unique = <int, HomeSubject>{};
    for (final entry in candidates) {
      final item = entry.item;
      final hasCover = item.images.values.any((url) {
        final uri = Uri.tryParse(url);
        return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty;
      });
      if (item.id <= 0 ||
          item.type != 2 ||
          entry.nsfw ||
          (item.nameCn.isEmpty && item.name.isEmpty) ||
          !hasCover ||
          (entry.releaseDate?.isAfter(this.today) ?? false))
        continue;
      unique[item.id] = entry;
    }
    entries = unique.values.toList();
    maxHeat = entries.fold<double>(
      1,
      (value, e) =>
          math.max(value, math.log(1 + math.max(e.collections, e.item.votes))),
    );
  }
  final DateTime today;
  late final List<HomeSubject> entries;
  late final double maxHeat;

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool isSeason(HomeSubject e) {
    final start = DateTime(today.year, ((today.month - 1) ~/ 3) * 3 + 1);
    return const ['TV', 'WEB', 'Web'].contains(e.platform) &&
        e.releaseDate != null &&
        !e.releaseDate!.isBefore(start) &&
        !e.releaseDate!.isAfter(today);
  }

  bool matches(HomeSubject e, HomeAnimeBucket bucket) => switch (bucket) {
    HomeAnimeBucket.all => e.isSeries || e.isMovie,
    HomeAnimeBucket.season => isSeason(e),
    // 剧场版集中进入电影；国家标签冲突时不强行分到单一地区。
    HomeAnimeBucket.japanese =>
      e.isSeries && e.countries.length == 1 && e.countries.contains('日本'),
    HomeAnimeBucket.chinese =>
      e.isSeries && e.countries.length == 1 && e.countries.contains('中国'),
    HomeAnimeBucket.movies => e.isMovie,
  };

  double heat(HomeSubject e) =>
      math.log(1 + math.max(e.collections, e.item.votes)) / maxHeat;

  double recommendation(HomeSubject e) {
    final votes = math.max(0, e.item.votes);
    final score = e.item.ratingScore.clamp(0, 10);
    // 250 票、6.8 分为先验，避免个位数评分人数把条目推到榜首。
    final quality = (votes * score + 250 * 6.8) / (votes + 250) / 10;
    final age = e.releaseDate == null
        ? 730
        : today.difference(e.releaseDate!).inDays;
    final freshness = math.exp(-math.max(0, age) / 180);
    return .35 * quality +
        .20 * heat(e) +
        .10 * freshness +
        .35 * (e.sourceListed ? 1 : 0);
  }

  List<HomeSubject> select(HomeAnimeBucket bucket, {bool popular = false}) {
    final result = entries.where((e) => matches(e, bucket)).toList();
    result.sort((a, b) {
      final order = (popular ? heat(b) : recommendation(b)).compareTo(
        popular ? heat(a) : recommendation(a),
      );
      return order != 0 ? order : a.item.id.compareTo(b.item.id);
    });
    return result;
  }

  /// 分组轮询保证“全部”有地区和形式的覆盖，每个 ID 只分配一次。
  List<BangumiItem> balanced({bool popular = false}) {
    final ranked = select(HomeAnimeBucket.all, popular: popular);
    final groups = <List<HomeSubject>>[
      ranked.where(isSeason).toList(),
      ranked
          .where((e) => matches(e, HomeAnimeBucket.chinese) && !isSeason(e))
          .toList(),
      ranked
          .where((e) => matches(e, HomeAnimeBucket.japanese) && !isSeason(e))
          .toList(),
      ranked.where((e) => e.isMovie).toList(),
    ];
    final offsets = List.filled(groups.length, 0);
    final result = <BangumiItem>[];
    final used = <int>{};
    while (groups.asMap().entries.any((g) => offsets[g.key] < g.value.length)) {
      for (var group = 0; group < groups.length; group++) {
        final quota = group == 3 ? 1 : 2;
        for (
          var count = 0;
          count < quota && offsets[group] < groups[group].length;
          count++
        ) {
          final item = groups[group][offsets[group]++].item;
          if (used.add(item.id)) result.add(item);
        }
      }
    }
    for (final e in ranked) {
      if (used.add(e.item.id)) result.add(e.item);
    }
    return result;
  }

  List<HomeChannel> channels(HomeAnimeBucket bucket, {String mode = 'anime'}) {
    final pool = select(bucket, popular: mode == 'popular');
    final used = <int>{};
    final channels = <HomeChannel>[];
    void add(
      String id,
      String title,
      Iterable<HomeSubject> source, {
      int? take,
    }) {
      final available = source.where((e) => !used.contains(e.item.id)).toList();
      if (available.isEmpty) return;
      final displayed = take == null
          ? available
          : available.take(take).toList();
      used.addAll(displayed.map((e) => e.item.id));
      channels.add(
        HomeChannel(id, title, displayed.map((e) => e.item).toList()),
      );
    }

    if (mode == 'recommended' || mode == 'popular') {
      final ids = balanced(
        popular: mode == 'popular',
      ).take(12).map((i) => i.id).toSet();
      final byId = {for (final e in pool) e.item.id: e};
      add(
        'main',
        mode == 'popular' ? '人气热播' : '今日推荐',
        ids.map((id) => byId[id]).whereType<HomeSubject>(),
      );
    }
    switch (bucket) {
      case HomeAnimeBucket.all:
        add('season', '当季新番', pool.where(isSeason));
        add(
          'chinese',
          '国漫剧场',
          pool.where((e) => matches(e, HomeAnimeBucket.chinese)),
        );
        add(
          'japanese',
          '日漫精选',
          pool.where((e) => matches(e, HomeAnimeBucket.japanese)),
        );
        add('anime-movies', '动漫电影', pool.where((e) => e.isMovie));
        add('other', '更多动画', pool);
      case HomeAnimeBucket.season:
        add('season', '当季新番', pool, take: 12);
        add('season-more', '更多新番', pool);
      case HomeAnimeBucket.chinese:
      case HomeAnimeBucket.japanese:
        final prefix = bucket == HomeAnimeBucket.chinese ? '国漫' : '日漫';
        add('region-new', '$prefix新番', pool.where(isSeason), take: 12);
        add('region-hot', '$prefix精选', pool, take: 12);
        add('region-more', '更多$prefix', pool);
      case HomeAnimeBucket.movies:
        final recent =
            pool
                .where(
                  (e) =>
                      e.releaseDate != null &&
                      !e.releaseDate!.isBefore(
                        DateTime(today.year - 2, today.month, today.day),
                      ),
                )
                .toList()
              ..sort((a, b) => b.releaseDate!.compareTo(a.releaseDate!));
        add('movie-new', '近年动画电影', recent, take: 12);
        add('movie-classic', '动画电影精选', pool, take: 12);
        add('movie-more', '更多动画电影', pool);
    }
    return channels;
  }
}
