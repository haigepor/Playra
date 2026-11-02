import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/plugins/plugins.dart';
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
    this.pending = const {},
    this.subjects = const {},
    this.algorithm,
    this.source = const HomeRuleCatalog(),
  });
  final List<BangumiItem> chinese, japanese;
  final Map<int, HomeAiring> airing;
  final Set<String> failed;
  final Set<String> pending;
  final Map<int, HomeSubject> subjects;
  final HomeContentAlgorithm? algorithm;
  final HomeRuleCatalog source;
  bool get hasStructuredData =>
      algorithm != null && algorithm!.entries.isNotEmpty;
  List<BangumiItem> select(HomeAnimeBucket bucket, {bool popular = false}) =>
      algorithm?.select(bucket, popular: popular).map((e) => e.item).toList() ??
      [];

  /// 旧资料模型只用于读取本地记录，不再获取远端目录。
  static Future<HomeCatalog> load({
    Iterable<Plugin> rules = const [],
    bool force = false,
    void Function(HomeCatalog)? onUpdate,
  }) async => const HomeCatalog();

  static Future<Map<String, dynamic>> loadDetail(int id) async => const {};
}
