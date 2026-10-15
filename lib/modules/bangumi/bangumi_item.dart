import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/utils/date_time.dart';
import 'bangumi_interest.dart';

part 'bangumi_item.g.dart';

@HiveType(typeId: 0)
class BangumiItem {
  @HiveField(0)
  int id;
  @HiveField(1)
  int type;
  @HiveField(2)
  String name;
  @HiveField(3)
  String nameCn;
  @HiveField(4)
  String summary;
  @HiveField(5)
  String airDate;
  @HiveField(6)
  int airWeekday;
  @HiveField(7)
  int rank;
  @HiveField(8)
  Map<String, String> images;
  @HiveField(9, defaultValue: [])
  List<BangumiTag> tags;
  @HiveField(10, defaultValue: [])
  List<String> alias;
  @HiveField(11, defaultValue: 0.0)
  double ratingScore;
  @HiveField(12, defaultValue: 0)
  int votes;
  @HiveField(13, defaultValue: [])
  List<int> votesCount;
  @HiveField(14, defaultValue: '')
  String info;
  // Calendar metadata is separate from counted user tags and is not persisted.
  final List<String> metaTags;
  BangumiInterest? interest;

  BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.airWeekday,
    required this.rank,
    required this.images,
    required this.tags,
    required this.alias,
    required this.ratingScore,
    required this.votes,
    required this.votesCount,
    required this.info,
    this.metaTags = const [],
    this.interest,
  });

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    List<String> parseBangumiAliases(Map<String, dynamic> jsonData) {
      final aliases = <String>{};
      void addAlias(dynamic value) {
        final text = value is String ? value.trim() : '';
        if (text.isNotEmpty) aliases.add(text);
      }

      if (jsonData.containsKey('infobox') && jsonData['infobox'] is List) {
        final List<dynamic> infobox = jsonData['infobox'];
        for (var item in infobox) {
          if (item is Map && item['key'] == '别名') {
            // api.bgm.tv /v0 uses `value`; next.bgm.tv /p1 uses `values`
            final dynamic raw = item['values'] ?? item['value'];
            if (raw is List) {
              for (final element in raw) {
                addAlias(element is Map ? element['v'] : element);
              }
            } else {
              addAlias(raw);
            }
          }
        }
      }
      // 镜像详情仅返回原始Wiki info；只读明确的别名字段，不从简介/其他条目猜名称。
      final info = jsonData['info'];
      if (info is String) {
        final lines = info.split(RegExp(r'\r?\n'));
        for (var i = 0; i < lines.length; i++) {
          final field = RegExp(r'^\s*\|\s*别名\s*=\s*(.*)$').firstMatch(lines[i]);
          if (field == null) continue;
          final value = field[1]!.trim();
          if (value != '{') {
            if (!value.contains('{') && !value.contains('}')) addAlias(value);
            continue;
          }
          final block = <String>[];
          var closed = false;
          while (++i < lines.length) {
            final line = lines[i].trim();
            if (line == '}') {
              closed = true;
              break;
            }
            if (line.startsWith('|') || line.startsWith('}}')) {
              i--;
              break;
            }
            final entry = RegExp(r'^\[([^\[\]]+)\]$').firstMatch(line);
            if (entry != null) block.add(entry[1]!.split('|').last);
          }
          if (closed) block.forEach(addAlias);
        }
      }
      return aliases.toList();
    }

    List<int> parseBangumiVoteCount(Map<String, dynamic> jsonData) {
      if (!jsonData.containsKey('rating')) {
        return [];
      }
      final json = jsonData['rating']['count'];
      if (json is Map<String, dynamic>) {
        return List<int>.generate(10, (i) => json['${i + 1}'] as int);
      }
      if (json is List<dynamic>) {
        return json.map((e) => e as int).toList();
      }
      return [];
    }

    String resolveAirDateString(Map<String, dynamic> jsonData) {
      String? nonEmpty(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      final fromTop = nonEmpty(jsonData['date']);
      if (fromTop != null) return fromTop;
      final airtime = jsonData['airtime'];
      if (airtime is Map) {
        final fromAir = nonEmpty(airtime['date']);
        if (fromAir != null) return fromAir;
      }
      return '';
    }

    final String airDateStr = resolveAirDateString(json);

    final rawTags = json['tags'] as List? ?? [];
    final tagList = rawTags.map((tag) => BangumiTag.fromJson(tag)).toList();
    final rawMetaTags = json['metaTags'];
    BangumiInterest? interest;
    final interestRaw = json['interest'];
    if (interestRaw is Map<String, dynamic>) {
      interest = BangumiInterest.fromJson(interestRaw);
    } else if (interestRaw is Map) {
      interest = BangumiInterest.fromJson(
        Map<String, dynamic>.from(interestRaw),
      );
    }
    return BangumiItem(
      id: json['id'],
      type: json['type'] ?? 2,
      name: json['name'] ?? '',
      nameCn: (json['name_cn'] ?? '') == ''
          ? (((json['nameCN'] ?? '') == '') ? json['name'] : json['nameCN'])
          : json['name_cn'],
      summary: json['summary'] ?? '',
      airDate: airDateStr,
      airWeekday: dateStringToWeekday(
        airDateStr.isEmpty ? '2000-11-11' : airDateStr,
      ),
      rank: json['rating']['rank'] ?? 0,
      images: Map<String, String>.from(
        json['images'] ??
            {
              "large": json['image'],
              "common": "",
              "medium": "",
              "small": "",
              "grid": "",
            },
      ),
      tags: tagList,
      alias: parseBangumiAliases(json),
      ratingScore: double.parse(
        (json['rating']['score'] ?? 0.0).toDouble().toStringAsFixed(1),
      ),
      votes: json['rating']['total'] ?? 0,
      votesCount: parseBangumiVoteCount(json),
      info: json['info'] ?? '',
      metaTags: rawMetaTags is List
          ? rawMetaTags
                .whereType<String>()
                .map((name) => name.trim())
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList()
          : const [],
      interest: interest,
    );
  }
}
