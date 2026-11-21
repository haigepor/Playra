/// CliCli JSON -> normalized model mapping.
///
/// This is the only file that knows CliCli's field names.
library;

import '../core/media_models.dart';
import 'clicli_config.dart';

MediaItem mediaItemFromVideo(Map<String, dynamic> video) {
  final current = _asInt(video['currentEpisodes']) ?? 0;
  final total = _asInt(video['totalEpisodes']) ?? 0;
  final finished = _asInt(video['isFinished']) == 1;
  final schedule = _asString(video['updateSchedule']);
  return MediaItem(
    key: MediaKey(
      sourceId: CliCliConfig.sourceId,
      mediaId: _asString(video['id']),
    ),
    title: _asString(video['title']).isEmpty
        ? _asString(video['name'])
        : _asString(video['title']),
    cover: _firstNonEmpty(<String>[
      _asString(video['coverUrl']),
      _asString(video['posterUrl']),
    ]),
    subtitle: _episodeLine(current, total, finished, schedule),
    badge: _firstNonEmpty(<String>[
      _asString(video['coverTag']),
      _asString(video['categoryName']),
      _asString(video['types']),
    ]),
    category: _asString(video['categoryName']),
    area: _asString(video['area']),
    year: _asInt(video['year']),
    score: _asDouble(video['score']),
    episodeCount: current > 0 ? current : total,
    updateSchedule: schedule,
    playCount: _asInt(video['playCount']) ?? 0,
  );
}

MediaSection mediaSectionFromModule(Map<String, dynamic> module) {
  final items = _mapList(
    module['items'],
  ).map(mediaItemFromVideo).toList(growable: false);
  final displayFields = module['displayFields'];
  return MediaSection(
    id: _asString(module['id']),
    title: _asString(module['name']),
    layout: _layoutFrom(_asString(module['layout'])),
    items: items,
    ranked: displayFields is Map && displayFields['rank'] == true,
    tabs: _stringList(module['boardTabs']),
    rows: _asInt(module['displayRows']) ?? 0,
  );
}

HomeFeed homeFeedFromModules(Map<String, dynamic> data) {
  final modules = _mapList(data['list'])
      .map(mediaSectionFromModule)
      .where((section) => section.items.isNotEmpty)
      .toList(growable: false);
  return HomeFeed(sections: modules);
}

List<MediaBanner> bannersFromData(Map<String, dynamic> data) {
  final result = <MediaBanner>[];
  for (final banner in _mapList(data['banners'])) {
    final image = _firstNonEmpty(<String>[
      _asString(banner['imageUrl']),
      _asString(banner['image']),
    ]);
    if (image.isEmpty) continue;
    final linkId = _asString(banner['linkId']);
    final linkType = _asInt(banner['linkType']);
    result.add(
      MediaBanner(
        id: _asString(banner['id']),
        title: _asString(banner['title']),
        imageUrl: image,
        // linkType 1 = opens a work; other types carry linkUrl instead.
        target: linkType == 1 && linkId.isNotEmpty
            ? MediaKey(sourceId: CliCliConfig.sourceId, mediaId: linkId)
            : null,
        linkUrl: _asString(banner['linkUrl']),
      ),
    );
  }
  return result;
}

HomeFeed homeFeedFromRecommend(Map<String, dynamic> data) {
  final sections = <MediaSection>[];
  final guess = data['guessYouLike'];
  if (guess is Map) {
    final map = Map<String, dynamic>.from(guess);
    final items = _mapList(
      map['videos'],
    ).map(mediaItemFromVideo).toList(growable: false);
    if (items.isNotEmpty) {
      sections.add(
        MediaSection(
          id: 'guess',
          title: _asString(map['title']).isEmpty
              ? '猜你喜欢'
              : _asString(map['title']),
          layout: MediaSectionLayout.waterfall,
          items: items,
          hasMore: map['hasMore'] == true,
        ),
      );
    }
  }
  return HomeFeed(sections: sections);
}

List<MediaCategory> categoriesFromTypes(Map<String, dynamic> data) {
  final types = _mapList(data['types']);
  final roots = <MediaCategory>[];
  for (final type in types) {
    if (_asString(type['parentId']) != '0') continue;
    final id = _asString(type['id']);
    if (id.isEmpty) continue;
    final children = <MediaCategory>[
      for (final child in types)
        if (_asString(child['parentId']) == id)
          MediaCategory(
            id: _asString(child['id']),
            name: _asString(child['name']),
          ),
    ];
    roots.add(
      MediaCategory(
        id: id,
        name: _asString(type['name']),
        children: children,
      ),
    );
  }
  return roots;
}

MediaPage mediaPageFromVideos(Map<String, dynamic> data) {
  final videos = _mapList(data['videos']);
  final info = data['pageinfo'];
  final pageInfo = info is Map ? Map<String, dynamic>.from(info) : const <String, dynamic>{};
  return MediaPage(
    items: videos.map(mediaItemFromVideo).toList(growable: false),
    pageIndex: _asInt(pageInfo['pageIndex']) ?? 1,
    pageSize: _asInt(pageInfo['pageSize']) ?? videos.length,
    total: _asInt(pageInfo['total']) ?? videos.length,
    pages: _asInt(pageInfo['pages']) ?? 1,
  );
}

MediaDetail mediaDetailFromVideo(
  Map<String, dynamic> video, {
  List<Map<String, dynamic>> episodes = const [],
  List<MediaItem> related = const [],
}) {
  return MediaDetail(
    key: MediaKey(
      sourceId: CliCliConfig.sourceId,
      mediaId: _asString(video['id']),
    ),
    title: _asString(video['title']),
    subtitle: _firstNonEmpty(<String>[
      _asString(video['subTitle']),
      _asString(video['alias']),
    ]),
    cover: _firstNonEmpty(<String>[
      _asString(video['coverUrl']),
      _asString(video['posterUrl']),
    ]),
    description: _asString(video['description']),
    category: _asString(video['categoryName']),
    area: _asString(video['area']),
    year: _asInt(video['year']),
    tags: _splitTags(
      _firstNonEmpty(<String>[
        _asString(video['tags']),
        _asString(video['types']),
      ]),
    ),
    score: _asDouble(video['score']),
    episodeCount: _asInt(video['currentEpisodes']) ?? 0,
    updateSchedule: _asString(video['updateSchedule']),
    roads: roadsFromVideo(video, episodes),
    related: related,
  );
}

List<MediaRoad> roadsFromVideo(
  Map<String, dynamic> video,
  List<Map<String, dynamic>> episodes,
) {
  final byCode = <String, List<Map<String, dynamic>>>{};
  for (final episode in episodes) {
    final code = _asString(episode['code']);
    if (code.isEmpty) continue;
    byCode.putIfAbsent(code, () => <Map<String, dynamic>>[]).add(episode);
  }

  final roads = <MediaRoad>[];
  final seen = <String>{};
  for (final player in _mapList(video['player'])) {
    final code = _asString(player['playerCode']);
    if (code.isEmpty || !seen.add(code)) continue;
    roads.add(
      MediaRoad(
        code: code,
        name: _firstNonEmpty(<String>[
          _asString(player['playerName']),
          code,
        ]),
        vipOnly: _asInt(player['isVip']) == 1,
        episodes: _episodesOf(byCode[code] ?? const []),
      ),
    );
  }
  for (final entry in byCode.entries) {
    if (!seen.add(entry.key)) continue;
    roads.add(
      MediaRoad(
        code: entry.key,
        name: entry.key,
        episodes: _episodesOf(entry.value),
      ),
    );
  }
  return roads.where((road) => road.episodes.isNotEmpty).toList(growable: false);
}

List<MediaQuality> qualitiesFromData(Map<String, dynamic> data) {
  return <MediaQuality>[
    for (final quality in _mapList(data['qualities']))
      MediaQuality(
        id: _asString(quality['quality']),
        label: _firstNonEmpty(<String>[
          _asString(quality['label']),
          _asString(quality['quality']),
        ]),
        vipOnly: quality['isVipOnly'] == true || _asInt(quality['isVipOnly']) == 1,
      ),
  ].where((quality) => quality.id.isNotEmpty).toList(growable: false);
}

MediaPlaybackSource playbackSourceFromExchange(Map<String, dynamic> data) {
  final expiresIn = _asInt(data['expiresIn']);
  return MediaPlaybackSource(
    url: _asString(data['playUrl']),
    quality: _asString(data['quality']),
    expiresAt: expiresIn == null || expiresIn <= 0
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn)),
    p2pEnabled: data['p2pEnabled'] == true,
  );
}

List<MediaEpisode> _episodesOf(List<Map<String, dynamic>> raw) {
  final episodes = <MediaEpisode>[
    for (var i = 0; i < raw.length; i++)
      MediaEpisode(
        number: _asInt(raw[i]['episodeNum']) ?? i + 1,
        title: _firstNonEmpty(<String>[
          _asString(raw[i]['displayName']),
          '第${i + 1}集',
        ]),
      ),
  ];
  episodes.sort((a, b) => a.number.compareTo(b.number));
  return episodes;
}

String _episodeLine(int current, int total, bool finished, String schedule) {
  if (finished && current > 0) return '全 $current 集';
  if (current > 0) return '更新至 $current 集';
  if (total > 0) return '共 $total 集';
  if (schedule.isNotEmpty) return schedule;
  return '';
}

MediaSectionLayout _layoutFrom(String layout) {
  return switch (layout) {
    'strip' => MediaSectionLayout.strip,
    'grid' => MediaSectionLayout.grid,
    'waterfall' => MediaSectionLayout.waterfall,
    _ => MediaSectionLayout.list,
  };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

List<String> _splitTags(String text) {
  if (text.isEmpty) return const <String>[];
  return text
      .split(RegExp(r'[\s,，/]+'))
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return <String>[
    for (final item in value)
      if (_asString(item).isNotEmpty) _asString(item),
  ];
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _asString(Object? value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
