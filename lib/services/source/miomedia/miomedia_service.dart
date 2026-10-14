import 'package:dio/dio.dart';
import '../runtime/source_runtime.dart';
import '../source_models.dart' show SourceException;
import '../sdk_playback_models.dart';

enum MioKind {
  anime('动漫'),
  movie('电影'),
  series('电视剧'),
  variety('综艺'),
  comicDrama('漫剧'),
  shortDrama('短剧'),
  unknown('其他');

  const MioKind(this.label);
  final String label;
}

MioKind mioKind(String category, String types) {
  // 类别证据来自来源元数据，作品标题不能成为分类依据。
  final name = category.isEmpty ? types : category;
  if (const {
    '国产动漫',
    '热门新番',
    '日韩动漫',
    '日本动漫',
    '欧美动漫',
    '动漫大全',
    '动漫电影',
    '动漫',
  }.contains(name)) {
    return MioKind.anime;
  }
  if (const {
    '电影大全',
    '电影',
    '动作片',
    '喜剧片',
    '爱情片',
    '科幻片',
    '恐怖片',
    '剧情片',
    '战争片',
    '纪录片',
  }.contains(name)) {
    return MioKind.movie;
  }
  if (const {
    '剧集大全',
    '国产剧',
    '港剧',
    '香港剧',
    '台剧',
    '台湾剧',
    '日剧',
    '日本剧',
    '韩剧',
    '韩国剧',
    '欧美剧',
    '美剧',
    '英剧',
    '电视剧',
    '泰剧',
    '海外剧',
  }.contains(name)) {
    return MioKind.series;
  }
  if (const {
    '综艺大全',
    '综艺节目',
    '综艺',
    '大陆综艺',
    '日韩综艺',
    '港台综艺',
    '欧美综艺',
  }.contains(name)) {
    return MioKind.variety;
  }
  if (const {'漫剧', '动漫短剧', '动态漫剧'}.contains(name)) return MioKind.comicDrama;
  if (const {'热播短剧', '短剧'}.contains(name)) return MioKind.shortDrama;
  return MioKind.unknown;
}

String _text(Object? value) => value is String ? value : '';
String _categoryId(Object? value) =>
    value is String && RegExp(r'^\d{1,64}$').hasMatch(value) ? value : '';
int _integer(Object? value) =>
    value is num && value.isFinite && value == value.roundToDouble()
    ? value.toInt()
    : 0;
bool _lineCode(String value) =>
    RegExp(r'^[A-Za-z0-9_+.\-]{1,64}$').hasMatch(value);
String mioImage(Object? value) {
  final text = _text(value);
  final uri = Uri.tryParse(text);
  return uri != null &&
          const {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? text
      : '';
}

class MioVideo extends SdkVideo {
  MioVideo.fromJson(Map<String, dynamic> raw)
    : id = _text(raw['id']),
      title = _text(raw['title']),
      categoryId = _categoryId(raw['categoryId']),
      categoryName = _text(raw['categoryName']),
      types = _text(raw['types']),
      tags = _text(raw['tags']),
      cover = mioImage(raw['coverUrl']),
      poster = mioImage(raw['posterUrl']),
      description = _text(raw['description']),
      year = raw['year'] is num ? '${raw['year']}' : _text(raw['year']),
      area = _text(raw['area']),
      score = raw['score'] is num ? (raw['score'] as num).toDouble() : 0,
      episodeCount = _integer(raw['currentEpisodes']),
      recommended = raw['isRecommend'] == true || raw['isRecommend'] == 1,
      lines = (raw['player'] is List ? raw['player'] as List : const [])
          .whereType<Map>()
          .map((r) => MioLine(_text(r['playerCode']), _text(r['playerName'])))
          .where((line) => _lineCode(line.code))
          .toList() {
    if (!RegExp(r'^\d{1,64}$').hasMatch(id) || title.trim().isEmpty) {
      throw const FormatException('Invalid source video');
    }
  }
  final String categoryId, types, tags;
  @override
  final String id, title, categoryName, cover, poster, description, year, area;
  @override
  final double score;
  final int episodeCount;
  final bool recommended;

  /// 题材来自真实标签，不从片名、分类大全名称或播放量推断。
  Set<String> get genres => '$types,$tags'
      .split(RegExp(r'[,，、|/;；]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty && value.length <= 16)
      .toSet();
  @override
  final List<MioLine> lines;
  MioKind get kind => mioKind(categoryName, types);
  @override
  bool get singleMovie => kind == MioKind.movie;
  String get identity => 'miomedia:$id';
  @override
  String get subtitle => [
    year,
    area,
    categoryName,
  ].where((s) => s.isNotEmpty && s != '0').join(' · ');
}

class MioLine extends SdkLine {
  const MioLine(super.code, super.name);
}

class MioEpisode extends SdkEpisode {
  MioEpisode.fromJson(Map<String, dynamic> raw)
    : super(
        number: _integer(raw['episodeNum']),
        name: _text(raw['displayName']).isNotEmpty
            ? _text(raw['displayName'])
            : _text(raw['episodeName']),
        code: _text(raw['code']),
        vip: raw['isVip'] == 1 || raw['isVip'] == true,
      ) {
    if (number < 1 || !_lineCode(code)) {
      throw const FormatException('Invalid episode');
    }
  }
}

class MioPage {
  const MioPage(this.items, this.page, this.hasMore);
  factory MioPage.fromJson(
    Map<String, dynamic> data, {
    required int page,
    required int size,
  }) {
    final items = <MioVideo>[];
    for (final raw
        in data['videos'] is List ? data['videos'] as List : const []) {
      if (raw is! Map) continue;
      try {
        items.add(MioVideo.fromJson(Map<String, dynamic>.from(raw)));
      } on FormatException {
        continue;
      }
    }
    final pageinfo = data['pageinfo'];
    final total = pageinfo is Map && pageinfo['total'] is num
        ? (pageinfo['total'] as num).toInt()
        : null;
    // 现场 search 的 pages 恒为 0，不能用它提前关闭分页。
    final more =
        items.isNotEmpty &&
        (total != null ? page * size < total : items.length >= size);
    return MioPage(items, page, more);
  }
  final List<MioVideo> items;
  final int page;
  final bool hasMore;
}

typedef MioRequest =
    Future<Map<String, dynamic>> Function(
      String operation,
      Map<String, dynamic> payload,
      CancelToken? cancel,
    );

class MioRankEntry {
  const MioRankEntry(this.position, this.video);
  final int position;
  final MioVideo video;
}

class MioRanking {
  MioRanking.fromJson(this.categoryId, Map<String, dynamic> module)
    : name = _text(module['name']),
      kind = _text(module['k']),
      cover = _text(module['cover']),
      layout = _text(module['layout']),
      boardTabs = List.unmodifiable(
        (module['boardTabs'] is List ? module['boardTabs'] as List : const [])
            .whereType<String>(),
      ),
      entries = List.unmodifiable(_rankEntries(module)) {
    if (name.trim().isEmpty) throw const FormatException('Invalid rank title');
  }
  final String categoryId, name, kind, cover, layout;
  final List<String> boardTabs;
  final List<MioRankEntry> entries;
  // 服务端没有统计窗口或热度指标字段，不能把累计播放量当作七天热度。
  Object? get window => null;
  Object? get metric => null;

  static List<MioRankEntry> _rankEntries(Map<String, dynamic> module) {
    if (module['items'] is! List) {
      throw const FormatException('Invalid rank items');
    }
    final items = (module['items'] as List).take(10).toList();
    return [
      for (var i = 0; i < items.length; i++)
        MioRankEntry(
          i + 1,
          MioVideo.fromJson(Map<String, dynamic>.from(items[i] as Map)),
        ),
    ];
  }
}

class MioMediaService {
  MioMediaService({MioRequest? request, SourceRuntimeClient? runtime})
    : _runtime = runtime ?? (request == null ? SourceRuntimeClient() : null),
      _request = request;
  final SourceRuntimeClient? _runtime;
  final MioRequest? _request;
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> payload, {
    CancelToken? cancel,
  }) async {
    final result =
        await (_request?.call(operation, payload, cancel) ??
            _runtime!.callMioMedia(
              operation,
              payload: payload,
              cancelToken: cancel,
            ));
    if (result['data'] is! Map) {
      throw const SourceException('PARSE_ERROR', '来源数据格式异常');
    }
    return Map<String, dynamic>.from(result['data'] as Map);
  }

  Future<MioPage> catalog({
    String? categoryId,
    int page = 1,
    int size = 20,
    CancelToken? cancel,
  }) async => MioPage.fromJson(
    await call('catalog', {
      'pageIndex': page,
      'pageSize': size,
      'categoryId': ?categoryId,
    }, cancel: cancel),
    page: page,
    size: size,
  );
  Future<MioRanking?> hotRank(String categoryId, {CancelToken? cancel}) async {
    if (_categoryId(categoryId).isEmpty) {
      throw const SourceException('INVALID_ARGUMENT', '分类编号无效');
    }
    final data = await call('hotRank', {
      'categoryId': categoryId,
      'pageIndex': 1,
      'pageSize': 20,
    }, cancel: cancel);
    if (data['categoryId'] != categoryId || data['list'] is! List) {
      throw const SourceException('PARSE_ERROR', '榜单分类或结构不匹配');
    }
    for (final module in data['list'] as List) {
      if (module is Map && module['id'] == 'MOD_818368') {
        return MioRanking.fromJson(
          categoryId,
          Map<String, dynamic>.from(module),
        );
      }
    }
    return null;
  }

  Future<MioPage> search(
    String keyword, {
    int page = 1,
    int size = 20,
    CancelToken? cancel,
  }) async => MioPage.fromJson(
    await call('search', {
      'keyword': keyword.trim(),
      'pageIndex': page,
      'pageSize': size,
    }, cancel: cancel),
    page: page,
    size: size,
  );
  Future<MioVideo> detail(String id, {CancelToken? cancel}) async {
    final data = await call('detail', {'videoId': id}, cancel: cancel);
    if (data['video'] is! Map) {
      throw const SourceException('PARSE_ERROR', '作品资料格式异常');
    }
    final result = MioVideo.fromJson(
      Map<String, dynamic>.from(data['video'] as Map),
    );
    if (result.id != id) {
      throw const SourceException('IDENTITY_MISMATCH', '作品资料不匹配');
    }
    return result;
  }

  Future<List<MioEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async {
    final data = await call('episodes', {
      'videoId': id,
      'code': code,
    }, cancel: cancel);
    final items = <MioEpisode>[];
    for (final raw
        in data['episodes'] is List ? data['episodes'] as List : const []) {
      if (raw is! Map) continue;
      try {
        final episode = MioEpisode.fromJson(Map<String, dynamic>.from(raw));
        if (episode.code == code) items.add(episode);
      } on FormatException {
        continue;
      }
    }
    return items;
  }

  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) => call('play', {
    'videoId': id,
    'code': code,
    'episodeNum': episode,
    'quality': ?quality,
    'caps': [],
  }, cancel: cancel);

  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) async {
    final data = await call('qualities', {
      'videoId': id,
      'code': code,
      'episodeNum': episode,
      'caps': [],
    }, cancel: cancel);
    // 只取画质元数据；exchangeToken 等短时材料不进入公共页面状态。
    return [
      for (final raw
          in data['qualities'] is List ? data['qualities'] as List : const [])
        if (raw is Map && SdkQuality.fromJson(raw) != null)
          SdkQuality.fromJson(raw)!,
    ];
  }

  void dispose() => _runtime?.dispose();
}
