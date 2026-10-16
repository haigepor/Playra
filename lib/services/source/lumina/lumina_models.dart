import '../sdk_playback_models.dart';

String luminaText(Object? value) => value is String ? value : '';
int? luminaInteger(Object? value) => value is int ? value : null;
String luminaImage(Object? value) {
  final text = luminaText(value), uri = Uri.tryParse(luminaText(value));
  return uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? text
      : '';
}

class LuminaChannel {
  LuminaChannel.fromJson(Map raw)
    : id = luminaText(raw['id']),
      name = luminaText(raw['name']),
      types = List.unmodifiable(
        (raw['types'] is List ? raw['types'] as List : const [])
            .whereType<String>(),
      );
  final String id, name;
  final List<String> types;
}

class LuminaBanner {
  LuminaBanner.fromJson(Map raw)
    : videoId = luminaText(raw['videoId']),
      title = luminaText(raw['title']),
      cover = luminaImage(raw['cover']);
  final String videoId, title, cover;
}

/// SDK 原生作品身份独立于 Bangumi；totalEpisodes 只用于资料，不生成可播放目录。
class LuminaVideo extends SdkVideo {
  LuminaVideo.fromJson(Map raw, {List<LuminaPart> parts = const []})
    : id = luminaText(raw['id']),
      title = luminaText(raw['title']).isNotEmpty
          ? luminaText(raw['title'])
          : luminaText(raw['name']),
      cover = luminaImage(raw['cover']),
      description = luminaText(raw['summary']),
      year = luminaText(raw['year']),
      area = luminaText(raw['area']),
      categoryId = luminaText(raw['categoryId']),
      updatedTo = luminaInteger(raw['updatedTo']),
      totalEpisodes = luminaInteger(raw['totalEpisodes']),
      isEnd = raw['isEnd'] == true,
      parts = List.unmodifiable(parts) {
    if (!RegExp(r'^\d{1,64}$').hasMatch(id) || title.trim().isEmpty) {
      throw const FormatException('Invalid Lumina video');
    }
  }
  @override
  final String id, title, cover, description, year, area;
  final String categoryId;
  final int? updatedTo, totalEpisodes;
  final bool isEnd;
  final List<LuminaPart> parts;
  @override
  String get poster => cover;
  @override
  String get categoryName => '动漫';
  @override
  double get score => 0;
  @override
  bool get singleMovie => false;
  @override
  bool get isAnime => true;
  @override
  List<SdkLine> get lines => parts.map((p) => SdkLine(p.play, p.name)).toList();
  String get updateLabel => updatedTo != null && updatedTo! > 0
      ? '更新至 $updatedTo 集'
      : isEnd
      ? '已完结'
      : '';
}

class LuminaPart {
  LuminaPart.fromJson(Map raw)
    : play = luminaText(raw['play']),
      name = luminaText(raw['name']),
      episodes = List.unmodifiable(
        (raw['episodes'] is List ? raw['episodes'] as List : const [])
            .whereType<Map>()
            .map((e) {
              final part = luminaText(e['part']);
              final ordinary = RegExp(
                r'^(?:第\s*)?(\d+)(?:\s*集)?$',
              ).firstMatch(part.trim());
              return SdkEpisode(
                number: ordinary == null ? null : int.tryParse(ordinary[1]!),
                name: luminaText(e['name']).isEmpty
                    ? part
                    : luminaText(e['name']),
                code: luminaText(raw['play']),
                reference: part,
              );
            })
            .where((e) => e.reference!.isNotEmpty),
      );
  final String play, name;
  final List<SdkEpisode> episodes;
}

class LuminaPage {
  LuminaPage.fromJson(Map data, {required int page, required int size})
    : items = _videos(data['videos']),
      hasMore =
          data['videos'] is List &&
          (data['videos'] as List).isNotEmpty &&
          (data['pageInfo'] is Map && (data['pageInfo'] as Map)['total'] is int
              ? page * size < ((data['pageInfo'] as Map)['total'] as int)
              : (data['videos'] as List).length >= size);
  final List<LuminaVideo> items;
  final bool hasMore;
  static List<LuminaVideo> _videos(Object? raw) {
    final items = <LuminaVideo>[];
    for (final item in raw is List ? raw : const []) {
      if (item is! Map) continue;
      try {
        items.add(LuminaVideo.fromJson(item));
      } on FormatException {
        continue;
      }
    }
    return List.unmodifiable(items);
  }
}
