import 'package:kazumi/modules/bangumi/bangumi_item.dart';

DateTime calendarSeason(DateTime date) =>
    DateTime(date.year, ((date.month - 1) ~/ 3) * 3 + 1);

enum ScheduleRegion { all, japanese, chinese, unknown }

class ScheduleEntry {
  const ScheduleEntry({
    required this.item,
    this.weekday,
    this.watchers,
    this.time,
    this.region = ScheduleRegion.unknown,
    this.detailsLoaded = false,
  });
  final BangumiItem item;
  final int? weekday, watchers;

  /// 仅保存可明确换算到北京时间的时刻，未知时区保持 null。
  final String? time;
  final ScheduleRegion region;
  final bool detailsLoaded;
  String get title => item.nameCn.isEmpty ? item.name : item.nameCn;
  String get cover => [
    for (final key in ['common', 'large', 'medium', 'small'])
      item.images[key] ?? '',
  ].firstWhere((url) => url.isNotEmpty, orElse: () => '');

  ScheduleEntry withDetail(Map<String, dynamic> detail) {
    // 已经换算过的条目不能再次按新星期进行时区换算。
    if (detailsLoaded) return this;
    final texts = <String>[];
    for (final field
        in detail['infobox'] is List ? detail['infobox'] as List : []) {
      if (field is! Map ||
          !const ['放送时间', '播放时间', '播出时间', '放送星期'].contains(field['key'])) {
        continue;
      }
      final raw = field['values'] ?? field['value'];
      for (final value in raw is List ? raw : [raw]) {
        texts.add(value is Map ? '${value['v'] ?? ''}' : '${value ?? ''}');
      }
    }
    final text = texts.join(' ');
    final day =
        weekday ?? explicitScheduleWeekday(detail) ?? _weekdayInText(text);
    final matches = RegExp(
      r'(?<!\d)([0-4]?\d)[:：]([0-5]\d)(?!\d)',
    ).allMatches(text);
    final times = matches
        .map((m) => int.parse(m[1]!) * 60 + int.parse(m[2]!))
        .toSet();
    final offsets = <int>{};
    if (RegExp(
      r'日本時間|日本时间|東京|东京|JST|(?:UTC|GMT)\s*\+0?9',
      caseSensitive: false,
    ).hasMatch(text)) {
      offsets.add(9);
    }
    if (RegExp(
      r'北京时间|北京時間|中国时间|中国時間|(?:UTC|GMT)\s*\+0?8',
      caseSensitive: false,
    ).hasMatch(text)) {
      offsets.add(8);
    }
    if (times.length != 1 || offsets.length != 1 || day == null) {
      return ScheduleEntry(
        item: item,
        weekday: day,
        watchers: watchers,
        region: region,
        detailsLoaded: true,
      );
    }
    final minutes = times.single + (8 - offsets.single) * 60;
    final shift = (minutes / 1440).floor();
    final normalized = minutes % 1440;
    return ScheduleEntry(
      item: item,
      weekday: (day - 1 + shift) % 7 + 1,
      watchers: watchers,
      region: region,
      detailsLoaded: true,
      time:
          '${(normalized ~/ 60).toString().padLeft(2, '0')}:${(normalized % 60).toString().padLeft(2, '0')}',
    );
  }
}

int? explicitScheduleWeekday(Map<String, dynamic> raw) {
  final airtime = raw['airtime'];
  final value =
      raw['air_weekday'] ??
      raw['airWeekday'] ??
      (airtime is Map ? airtime['weekday'] : null);
  final day = int.tryParse('$value');
  return day != null && day >= 1 && day <= 7 ? day : null;
}

int? _weekdayInText(String text) {
  final found = <int>{};
  for (var i = 0; i < 7; i++) {
    if (RegExp('(?:周|星期|礼拜)${'一二三四五六日'[i]}|${'月火水木金土日'[i]}曜日').hasMatch(text)) {
      found.add(i + 1);
    }
  }
  if (RegExp(r'(?:星期|礼拜)天').hasMatch(text)) found.add(7);
  return found.length == 1 ? found.single : null;
}

ScheduleEntry parseScheduleEntry(
  Map<String, dynamic> raw, {
  int? weekday,
  int? watchers,
}) {
  final id = int.tryParse('${raw['id']}');
  if (id == null || id <= 0) throw const FormatException('无效番剧 ID');
  final rating = raw['rating'] is Map ? raw['rating'] as Map : const {};
  // 缺图、缺评分属于可展示内容，不能让旧模型的强类型转换静默丢弃条目。
  final images = <String, String>{};
  if (raw['images'] is Map) {
    (raw['images'] as Map).forEach((key, value) {
      if (value is String && value.isNotEmpty) images['$key'] = value;
    });
  }
  final item = BangumiItem.fromJson({
    ...raw,
    'id': id,
    'type': raw['type'] is int ? raw['type'] : 2,
    'images': images,
    'tags': raw['tags'] is List ? raw['tags'] : [],
    'rating': {
      'rank': rating['rank'] is int ? rating['rank'] : 0,
      'score': rating['score'] is num ? rating['score'] : 0,
      'total': rating['total'] is int ? rating['total'] : 0,
      'count': rating['count'] is List ? rating['count'] : [],
    },
  });
  final day = weekday ?? explicitScheduleWeekday(raw);
  item.airWeekday = day ?? 0;
  final tags = {...item.metaTags, ...item.tags.map((tag) => tag.name)};
  final region = tags.any((tag) => const ['中国', '中国大陆', '国漫'].contains(tag))
      ? ScheduleRegion.chinese
      : tags.contains('日本')
      ? ScheduleRegion.japanese
      : ScheduleRegion.unknown;
  return ScheduleEntry(
    item: item,
    weekday: day,
    watchers: watchers,
    region: region,
  );
}

class SeasonScheduleSnapshot {
  const SeasonScheduleSnapshot({
    required this.season,
    required this.entries,
    this.source = 'Bangumi',
    this.partial = false,
    this.notice,
  });
  final DateTime season;
  final List<ScheduleEntry> entries;
  final String source;
  final bool partial;
  final String? notice;
  SeasonScheduleSnapshot withEntries(List<ScheduleEntry> value) =>
      SeasonScheduleSnapshot(
        season: season,
        entries: List.unmodifiable(value),
        source: source,
        partial: partial,
        notice: notice,
      );
}

SeasonScheduleSnapshot parseCalendarSnapshot(
  dynamic raw, {
  required DateTime season,
  String source = 'Bangumi',
}) {
  if (raw is! Map ||
      !raw.keys.any((key) {
        final day = int.tryParse('$key');
        return day != null && day >= 1 && day <= 7;
      })) {
    throw const FormatException('放送日历响应格式异常');
  }
  final entries = <ScheduleEntry>[];
  final seen = <String>{};
  var partial = false;
  for (var day = 1; day <= 7; day++) {
    final list = raw['$day'] ?? [];
    if (list is! List) {
      partial = true;
      continue;
    }
    for (final wrapper in list) {
      try {
        if (wrapper is! Map || wrapper['subject'] is! Map) {
          throw const FormatException();
        }
        final entry = parseScheduleEntry(
          Map<String, dynamic>.from(wrapper['subject']),
          weekday: day,
          watchers: wrapper['watchers'] is int ? wrapper['watchers'] : null,
        );
        if (seen.add('$day:${entry.item.id}')) entries.add(entry);
      } catch (_) {
        partial = true;
      }
    }
  }
  return SeasonScheduleSnapshot(
    season: calendarSeason(season),
    entries: List.unmodifiable(entries),
    source: source,
    partial: partial,
    notice: partial ? '部分条目暂时无法读取，已保留可用内容' : null,
  );
}
