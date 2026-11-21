/// Source-agnostic media models.
///
/// Everything the UI layer needs is expressed here; no CliCli wire fields leak
/// past `features/sources/clicli`. Adding a second source only means writing a
/// new [MediaSource] that maps its payloads onto these types.
library;

/// Stable identity of one work inside one source.
class MediaKey {
  const MediaKey({required this.sourceId, required this.mediaId});

  final String sourceId;
  final String mediaId;

  @override
  bool operator ==(Object other) =>
      other is MediaKey &&
      other.sourceId == sourceId &&
      other.mediaId == mediaId;

  @override
  int get hashCode => Object.hash(sourceId, mediaId);

  @override
  String toString() => '$sourceId:$mediaId';
}

/// A poster card in a feed, grid or search result.
class MediaItem {
  const MediaItem({
    required this.key,
    required this.title,
    this.cover = '',
    this.subtitle = '',
    this.badge = '',
    this.category = '',
    this.area = '',
    this.year,
    this.score,
    this.episodeCount = 0,
    this.updateSchedule = '',
    this.playCount = 0,
  });

  final MediaKey key;
  final String title;
  final String cover;

  /// Short status line, e.g. "更新至 179 集".
  final String subtitle;

  /// Corner badge, e.g. "国产动漫".
  final String badge;
  final String category;
  final String area;
  final int? year;
  final double? score;
  final int episodeCount;
  final String updateSchedule;
  final int playCount;

  String get metaText {
    final parts = <String>[
      if (year != null && year! > 0) '$year',
      if (area.isNotEmpty) area,
      if (category.isNotEmpty) category,
    ];
    return parts.join(' · ');
  }
}

enum MediaSectionLayout { strip, grid, waterfall, list }

/// A promotional banner. [target] is set when the banner opens a work inside
/// the same source; [linkUrl] carries external links for everything else.
class MediaBanner {
  const MediaBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.target,
    this.linkUrl = '',
  });

  final String id;
  final String title;
  final String imageUrl;
  final MediaKey? target;
  final String linkUrl;
}

class MediaSection {
  const MediaSection({
    required this.id,
    required this.title,
    required this.layout,
    this.items = const [],
    this.hasMore = false,
    this.ranked = false,
    this.tabs = const <String>[],
    this.rows = 0,
  });

  final String id;
  final String title;
  final MediaSectionLayout layout;
  final List<MediaItem> items;
  final bool hasMore;

  /// Items are ordered by popularity and should show their position.
  final bool ranked;

  /// Server-side board labels, e.g. `["热播榜"]`.
  final List<String> tabs;

  /// Preferred row count for grid sections; 0 means "let the UI decide".
  final int rows;
}

class HomeFeed {
  const HomeFeed({
    this.banners = const <MediaBanner>[],
    this.sections = const <MediaSection>[],
  });

  final List<MediaBanner> banners;
  final List<MediaSection> sections;

  bool get isEmpty => banners.isEmpty && sections.every((s) => s.items.isEmpty);
}

class MediaCategory {
  const MediaCategory({
    required this.id,
    required this.name,
    this.children = const [],
  });

  final String id;
  final String name;
  final List<MediaCategory> children;
}

class MediaPage {
  const MediaPage({
    required this.items,
    this.pageIndex = 1,
    this.pageSize = 20,
    this.total = 0,
    this.pages = 0,
  });

  final List<MediaItem> items;
  final int pageIndex;
  final int pageSize;
  final int total;
  final int pages;

  bool get hasMore => pageIndex < pages;
}

class MediaEpisode {
  const MediaEpisode({
    required this.number,
    required this.title,
    this.vipOnly = false,
  });

  /// 1-based episode number used by the source protocol.
  final int number;

  /// Display text, e.g. "第01集".
  final String title;
  final bool vipOnly;
}

class MediaRoad {
  const MediaRoad({
    required this.code,
    required this.name,
    this.vipOnly = false,
    this.episodes = const [],
  });

  final String code;
  final String name;
  final bool vipOnly;
  final List<MediaEpisode> episodes;
}

class MediaDetail {
  const MediaDetail({
    required this.key,
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.description = '',
    this.category = '',
    this.area = '',
    this.year,
    this.tags = const [],
    this.score,
    this.episodeCount = 0,
    this.updateSchedule = '',
    this.roads = const [],
    this.related = const [],
  });

  final MediaKey key;
  final String title;
  final String subtitle;
  final String cover;
  final String description;
  final String category;
  final String area;
  final int? year;
  final List<String> tags;
  final double? score;
  final int episodeCount;
  final String updateSchedule;
  final List<MediaRoad> roads;
  final List<MediaItem> related;

  MediaRoad? roadByCode(String code) {
    for (final road in roads) {
      if (road.code == code) return road;
    }
    return null;
  }

  MediaRoad? get defaultRoad => roads.isEmpty ? null : roads.first;
}

class MediaQuality {
  const MediaQuality({
    required this.id,
    required this.label,
    this.vipOnly = false,
  });

  final String id;
  final String label;
  final bool vipOnly;
}

/// A resolved, time-limited playback URL.
class MediaPlaybackSource {
  const MediaPlaybackSource({
    required this.url,
    this.quality = '',
    this.headers = const {},
    this.referer = '',
    this.expiresAt,
    this.p2pEnabled = false,
  });

  final String url;
  final String quality;
  final Map<String, String> headers;
  final String referer;
  final DateTime? expiresAt;
  final bool p2pEnabled;

  bool get isExpired {
    final at = expiresAt;
    return at != null && DateTime.now().isAfter(at);
  }
}
