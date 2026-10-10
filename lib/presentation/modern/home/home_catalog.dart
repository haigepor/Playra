import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:dio/dio.dart' show Options;
import 'package:kazumi/utils/constants.dart' show bangumiHTTPHeader;
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'home_content_algorithm.dart';
import 'home_rule_catalog.dart';

class HomeAiring {
  const HomeAiring(this.weekday, [this.time]);
  final int weekday;
  final String? time;

  String get label => weekday < 1 || weekday > 7
      ? '时间待定'
      : '周${'一二三四五六日'[weekday - 1]} | ${time ?? '待定'}';

  /// 日历分组提供星期；首播日期不能代替每周放送安排。
  HomeAiring withDetail(Map<String, dynamic> json) {
    final times = <String>{};
    for (final entry in (json['infobox'] as List? ?? const [])) {
      if (entry is! Map ||
          !const ['放送时间', '播放时间', '播出时间', '放送星期'].contains(entry['key'])) {
        continue;
      }
      final raw = entry['values'] ?? entry['value'];
      final values = raw is List ? raw : [raw];
      for (final value in values) {
        final text = value is Map ? value['v']?.toString() : value?.toString();
        for (final match in RegExp(
          r'(?<!\d)([0-2]?\d)[:：]([0-5]\d)(?!\d)',
        ).allMatches(text ?? '')) {
          if (int.parse(match[1]!) < 24) {
            times.add('${match[1]!.padLeft(2, '0')}:${match[2]}');
          }
        }
      }
    }
    // 多平台存在多个时刻或跨日的 24+ 小时表示时，不猜测唯一更新时间。
    return HomeAiring(weekday, times.length == 1 ? times.single : null);
  }
}

class HomeCatalog {
  const HomeCatalog({
    this.chinese = const [],
    this.japanese = const [],
    this.airing = const {},
    this.failed = const {},
    this.subjects = const {},
    this.algorithm,
    this.source = const HomeRuleCatalog(),
  });
  final List<BangumiItem> chinese, japanese;
  final Map<int, HomeAiring> airing;
  final Set<String> failed;
  final Map<int, HomeSubject> subjects;
  final HomeContentAlgorithm? algorithm;
  final HomeRuleCatalog source;
  bool get hasStructuredData =>
      algorithm != null && algorithm!.entries.isNotEmpty;
  List<BangumiItem> select(HomeAnimeBucket bucket, {bool popular = false}) =>
      algorithm?.select(bucket, popular: popular).map((e) => e.item).toList() ??
      [];

  static HomeCatalog? _lastGood;
  static DateTime? _cachedAt;
  static String _cacheKey = '';
  static Future<HomeCatalog>? _pending;
  static String _pendingKey = '';

  static Future<List<BangumiItem>> loadCategory(
    String tag, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (BangumiAcceleration.current == BangumiAcceleration.mirror) {
      final cached = await BangumiApi.getBangumiMirrorPopularSubjects(
        tag: tag,
        limit: limit,
        offset: offset,
      );
      if (cached.isNotEmpty) return cached;
    }
    // 部分镜像榜单尚无分类缓存，回退原有标签搜索，不将空缓存当成空分类。
    return (await BangumiApi.bangumiSearch(
          '',
          tags: [tag],
          limit: limit,
          offset: offset,
        ))?.items ??
        [];
  }

  static Future<HomeCatalog> load({
    Iterable<Plugin> rules = const [],
    bool force = false,
  }) {
    final installed = rules.toList();
    final key = installed.map((p) => '${p.name}@${p.baseUrl}').join('|');
    if (!force &&
        _lastGood != null &&
        _cacheKey == key &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 5)) {
      return Future.value(_lastGood);
    }
    if (_pending != null && _pendingKey == key) return _pending!;
    _pendingKey = key;
    return _pending = _loadStructured(installed)
        .then((result) {
          if (result.hasStructuredData && key == _pendingKey) {
            _lastGood = result;
            _cachedAt = DateTime.now();
            _cacheKey = key;
          }
          return result;
        })
        .whenComplete(() {
          if (_pendingKey == key) _pending = null;
        });
  }

  static Future<HomeCatalog> _loadStructured(List<Plugin> rules) async {
    final failed = <String>{};
    final subjects = <int, HomeSubject>{};
    final priorities = <int, int>{};
    final airing = <int, HomeAiring>{};
    final sourceFuture = HomeRuleCatalog.load(
      rules,
    ).catchError((_) => const HomeRuleCatalog(failures: ['catalog']));
    void ingest(Object? raw, {int priority = 1}) {
      if (raw is! Map) return;
      try {
        final subject = HomeSubject.fromJson(Map<String, dynamic>.from(raw));
        // v0 的完整资料优先于 Next 摘要，避免并发完成顺序改变分类。
        if (priority >= (priorities[subject.item.id] ?? 0)) {
          subjects[subject.item.id] = subject;
          priorities[subject.item.id] = priority;
        }
      } catch (_) {
        // 单个脏记录不能使整栏消失，未知格式后续由分类器保守排除。
      }
    }

    Future<void> tag(String tag) async {
      final json = await BangumiClient.instance.post(
        '${ApiEndpoints.bangumiAPIDomain}/v0/search/subjects?limit=40&offset=0',
        data: BangumiApi.buildBangumiSearchParams('', tags: [tag]),
      );
      for (final raw in json['data'] as List? ?? const [])
        ingest(raw, priority: 2);
    }

    Future<void> movies(String sort, {int? year}) async {
      // 官方定义 type=2 + cat=3 为动画 Movie，不能与真人电影分类混用。
      // https://github.com/bangumi/api/blob/master/open-api/v0.yaml
      // 当前加速镜像的 /v0/subjects 返回 404，目录单独直连官方；保留网络代理。
      final response = await DioFactory.apiDio.get(
        '${ApiEndpoints.bangumiAPIDomain}/v0/subjects',
        options: Options(headers: bangumiHTTPHeader),
        queryParameters: {
          'type': 2,
          'cat': 3,
          'sort': sort,
          'limit': 40,
          'offset': 0,
          if (year != null) 'year': year,
        },
      );
      final json = response.data;
      for (final raw in json['data'] as List? ?? const [])
        ingest(raw, priority: 2);
    }

    Future<void> calendar() async {
      final json = await BangumiClient.instance.get(
        ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiCalendar,
      );
      for (var day = 1; day <= 7; day++) {
        for (final entry in (json['$day'] as List? ?? const [])) {
          if (entry is! Map) continue;
          final raw = entry['subject'];
          ingest(raw);
          if (raw is Map && raw['id'] is int)
            airing[raw['id']] = HomeAiring(day);
        }
      }
    }

    Future<void> trending() async {
      // 加速镜像没有 Next 趋势路由；本新增候选入口读取官方公开资料。
      final response = await DioFactory.apiDio.get(
        '${ApiEndpoints.bangumiAPINextDomain}/p1/trending/subjects',
        options: Options(headers: bangumiHTTPHeader),
        queryParameters: {'type': 2, 'limit': 40, 'offset': 0},
      );
      final json = response.data;
      for (final raw in json['data'] as List? ?? const []) {
        if (raw is Map) ingest(raw['subject']);
      }
    }

    final jobs = <(String, Future<void> Function())>[
      ('trending', trending),
      ('schedule', calendar),
      ('chinese', () => tag('中国')),
      ('japanese', () => tag('日本')),
      ('movies-rank', () => movies('rank')),
      // 无年份的日期榜前排是未来作品；按近三年补齐，再统一过滤未来日期。
      (
        'movies-date',
        () async {
          final year = DateTime.now().year;
          for (final candidateYear in [year, year - 1, year - 2]) {
            try {
              await movies(
                'date',
                year: candidateYear,
              ).timeout(const Duration(seconds: 8));
            } catch (_) {
              failed.add('movies-date-$candidateYear');
            }
          }
        },
      ),
    ];
    for (var start = 0; start < jobs.length; start += 3) {
      await Future.wait(
        jobs.skip(start).take(3).map((job) async {
          try {
            await job.$2().timeout(
              Duration(seconds: job.$1 == 'movies-date' ? 26 : 16),
            );
          } catch (_) {
            failed.add(job.$1);
          }
        }),
      );
    }
    final source = await sourceFuture;
    if (source.entries.isEmpty) failed.add('source');
    final sourceKeys = source.entries
        .map((e) => HomeRuleCatalog.titleKey(e.title))
        .toSet();
    bool named(HomeSubject e, Set<String> keys) =>
        [e.item.nameCn, e.item.name, ...e.item.alias].any(
          (name) =>
              name.isNotEmpty && keys.contains(HomeRuleCatalog.titleKey(name)),
        );

    // 从各源栏目均匀补齐候选；严格匹配名称或官方别名，保留不同季/篇身份。
    final seeds = <String, HomeRuleEntry>{};
    for (final group in const ['chinese', 'japanese', 'movies', 'all']) {
      for (final entry
          in source.entries.where((e) => e.group == group).take(3)) {
        final key = HomeRuleCatalog.titleKey(entry.title);
        if (!subjects.values.any((e) => named(e, {key}))) seeds[key] = entry;
      }
    }
    final tasks = seeds.entries.toList();
    for (var start = 0; start < tasks.length; start += 3) {
      await Future.wait(
        tasks.skip(start).take(3).map((task) async {
          try {
            final json = await BangumiClient.instance
                .post(
                  '${ApiEndpoints.bangumiAPIDomain}/v0/search/subjects?limit=5&offset=0',
                  data: {
                    'keyword': task.value.title,
                    'sort': 'match',
                    'filter': {
                      'type': [2],
                      'nsfw': false,
                    },
                  },
                )
                .timeout(const Duration(seconds: 10));
            final matches = <HomeSubject>[];
            for (final raw in json['data'] as List? ?? const []) {
              if (raw is! Map) continue;
              final entry = HomeSubject.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (named(entry, {task.key}) &&
                  !entry.nsfw &&
                  entry.item.type == 2)
                matches.add(entry);
            }
            // 同名多个条目可能是重制版，资料不够时不自动选第一个。
            if (matches.length == 1)
              subjects[matches.single.item.id] = matches.single;
          } catch (_) {
            failed.add('source-metadata');
          }
        }),
      );
    }
    for (final id in subjects.keys.toList()) {
      if (named(subjects[id]!, sourceKeys))
        subjects[id] = subjects[id]!.withSource();
    }
    final algorithm = HomeContentAlgorithm(subjects.values);
    final accepted = {for (final e in algorithm.entries) e.item.id: e};
    airing.removeWhere((id, _) => accepted[id]?.isSeries != true);
    KazumiLogger().i(
      'Home catalog: source=${source.name}, sourceEntries=${source.entries.length}, candidates=${subjects.length}, accepted=${accepted.length}, season=${algorithm.select(HomeAnimeBucket.season).length}, chinese=${algorithm.select(HomeAnimeBucket.chinese).length}, japanese=${algorithm.select(HomeAnimeBucket.japanese).length}, movies=${algorithm.select(HomeAnimeBucket.movies).length}, sourceMatched=${accepted.values.where((e) => e.sourceListed).length}, failed=${failed.join(',')}',
    );
    return HomeCatalog(
      chinese: algorithm
          .select(HomeAnimeBucket.chinese)
          .map((e) => e.item)
          .toList(),
      japanese: algorithm
          .select(HomeAnimeBucket.japanese)
          .map((e) => e.item)
          .toList(),
      airing: airing,
      failed: failed,
      subjects: accepted,
      algorithm: algorithm,
      source: source,
    );
  }

  static Future<Map<String, dynamic>> loadDetail(int id) async =>
      Map<String, dynamic>.from(
        await BangumiClient.instance.get(
          '${ApiEndpoints.bangumiAPINextDomain}/p1/subjects/$id',
        ),
      );
}
