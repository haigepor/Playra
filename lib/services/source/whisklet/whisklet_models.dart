import 'dart:convert';

/// 上游片目：保持来源身份 `whisklet:<vod_id>`，标题/封面临近字段只做展示。
class WhiskletWork {
  const WhiskletWork({
    required this.id,
    required this.title,
    required this.categoryId,
    this.cover = '',
    this.remarks = '',
    this.className = '',
    this.area = '',
    this.year = '',
    this.episodes = 0,
  });

  final int id;
  final String title;
  final int categoryId;
  final String cover, remarks, className, area, year;

  /// 目录给出的集数；0 表示上游没有写可解析的集数。
  final int episodes;

  String get identity => 'whisklet:$id';

  static final _tags = RegExp(r'<[^>]*>');
  static final _amp = RegExp(r'&(?:amp;)+');
  static String plain(Object? value) => (value?.toString() ?? '')
      .replaceAll(_tags, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(_amp, '&')
      .trim();

  static int count(Object? value, [int fallback = 0]) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  /// 封面地址只做协议补全：`//host/path` → `https://host/path`。
  static String image(Object? value) {
    final text = plain(value);
    if (text.isEmpty) return '';
    if (text.startsWith('//')) return 'https:$text';
    final uri = Uri.tryParse(text);
    return uri != null && {'http', 'https'}.contains(uri.scheme) ? text : '';
  }

  static WhiskletWork? fromRow(Map row) {
    final id = count(row['vod_id']);
    final title = plain(row['vod_name']);
    if (id <= 0 || title.isEmpty) return null;
    final remarks = plain(row['vod_remarks']);
    final episodes = RegExp(r'(\d+)\s*集').firstMatch(remarks)?.group(1);
    final category = count(row['type_id_1']) > 0
        ? count(row['type_id_1'])
        : count(row['type_id']);
    return WhiskletWork(
      id: id,
      title: title,
      categoryId: category,
      cover: image(row['vod_pic']),
      remarks: remarks,
      className: plain(row['vod_class']),
      area: plain(row['vod_area']),
      year: plain(row['vod_year']),
      episodes: int.tryParse(episodes ?? '') ?? 0,
    );
  }

  static List<WhiskletWork> list(Object? rows) {
    final items = <int, WhiskletWork>{};
    for (final row in rows is List ? rows : const []) {
      if (row is! Map) continue;
      final work = fromRow(row);
      if (work != null) items.putIfAbsent(work.id, () => work);
    }
    return items.values.toList();
  }

  /// 详情接口的 `vod_info` 字段比列表更全，缺失字段回落到列表值。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'categoryId': categoryId,
    'cover': cover,
    'remarks': remarks,
  };

  @override
  String toString() => jsonEncode(toJson());
}

class WhiskletShelf {
  const WhiskletShelf(this.title, this.items);
  final String title;
  final List<WhiskletWork> items;
}

class WhiskletPage {
  const WhiskletPage({
    required this.items,
    required this.page,
    required this.pages,
  });
  final List<WhiskletWork> items;
  final int page, pages;
  bool get hasMore => items.isNotEmpty && page < pages;
}

/// 详情里的播放线路：`code` 是上游线路标识，`parseApi` 非空表示该线需要解析。
class WhiskletLine {
  const WhiskletLine({
    required this.code,
    required this.name,
    required this.parseApi,
    required this.episodes,
  });
  final String code, name, parseApi;
  final List<WhiskletEpisode> episodes;
}

class WhiskletEpisode {
  const WhiskletEpisode(this.name, this.token, this.number);
  final String name, token;
  final int? number;
}
