/// 红果匿名协议的数据模型（对标 openhongguo sdk/model）。
/// 只保留 Playra 消费的字段；字段名与 wire 一致。
library;

/// 书城无限流翻页句柄（对齐 Go 的 FeedContinuation）。
/// offset 是上一页 cell/change 响应的 next_offset；丢失它会永远拉回第一页。
typedef HongguoFeedContinuation = ({
  String cellId,
  String sessionId,
  String clientTemplate,
  String showType,
  String tabType,
  String offset,
});

/// 书城/搜索返回的一部短剧摘要。
class HongguoSeriesSummary {
  const HongguoSeriesSummary({
    required this.id,
    required this.title,
    this.description = '',
    this.coverUrl = '',
    this.episodeCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final int episodeCount;
}

/// 短剧详情（video_detail）。
class HongguoSeries {
  const HongguoSeries({
    required this.id,
    required this.title,
    this.description = '',
    this.coverUrl = '',
    this.episodeCount = 0,
    this.heat = 0,
    this.playCount = 0,
    this.status = 0,
    this.isMultiSeason = false,
    this.seasonIndex = 0,
    this.rightText = '',
  });

  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final int episodeCount;
  final int heat;
  final int playCount;
  final int status;
  final bool isMultiSeason;
  final int seasonIndex;
  final String rightText;
}

/// 一集分集。集数从 1 开始。
class HongguoEpisode {
  const HongguoEpisode({
    required this.id,
    required this.seriesId,
    required this.number,
    required this.title,
    this.playable = true,
    this.vertical = false,
    this.coverUrl = '',
    this.durationSeconds = 0,
  });

  final String id;
  final String seriesId;
  final int number;
  final String title;
  final bool playable;
  final bool vertical;
  final String coverUrl;
  final int durationSeconds;
}

/// 一个媒体表示形式（清晰度流）。
class HongguoStream {
  const HongguoStream({
    required this.definition,
    required this.quality,
    required this.codec,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.size,
    required this.url,
    required this.backupUrl,
    required this.hls,
    required this.dash,
    required this.protected,
    required this.encryption,
  });

  final String definition;
  final String quality;
  final String codec;
  final int width;
  final int height;
  final int bitrate;
  final int size;
  final String url;
  final String backupUrl;
  final bool hls;
  final bool dash;
  final bool protected;
  final String encryption;
}

/// 一集的匿名播放模型（video_model）。
class HongguoPlayback {
  const HongguoPlayback({
    required this.episodeId,
    required this.videoId,
    required this.mediaType,
    required this.durationSeconds,
    required this.expiresAt,
    required this.protected,
    required this.streams,
    required this.keyMaterial,
    this.audioUrl = '',
  });

  final String episodeId;
  final String videoId;
  final String mediaType;
  final int durationSeconds;

  /// 流 URL 的失效时间（unix 秒）。
  final int expiresAt;
  final bool protected;
  final List<HongguoStream> streams;

  /// 加密分集的包装密钥材料（spade_a），由 [deriveHongguoContentKey] 解包。
  /// 不包含内容密钥本身。
  final String keyMaterial;
  final String audioUrl;
}

/// 由包装密钥材料还原出的 CENC 内容密钥。
class HongguoContentKey {
  const HongguoContentKey({required this.hex, this.version = ''});

  /// 16 字节 AES 密钥的小写十六进制（ClearKey / mpv decryption_key 格式）。
  final String hex;
  final String version;
}

/// 目录页（书城/搜索/翻页共用）。
class HongguoCatalogPage {
  const HongguoCatalogPage({
    required this.items,
    this.hasMore = false,
    this.nextOffset = 0,
    this.sessionId = '',
  });

  final List<HongguoSeriesSummary> items;
  final bool hasMore;
  final int nextOffset;
  final String sessionId;
}

/// 榜单行。
class HongguoRankItem {
  const HongguoRankItem({
    required this.position,
    this.rank = 0,
    required this.title,
    this.seriesId = '',
    this.coverUrl = '',
    this.score = '',
    this.episodeCount = 0,
    this.promoted = false,
  });

  final int position;
  final int rank;
  final String title;
  final String seriesId;
  final String coverUrl;
  final String score;
  final int episodeCount;
  final bool promoted;
}

/// 短剧榜单页：内容/榜单选择行 + 榜单条目。
class HongguoShortRanking {
  const HongguoShortRanking({
    required this.items,
    this.contents = const [],
    this.boards = const [],
    this.hasMore = false,
    this.nextOffset = 0,
    this.sessionId = '',
  });

  final List<HongguoRankItem> items;

  /// 筛选行：（内容 id, 内容名, 选中）与（榜单 id, 榜单名, 选中）。
  final List<(String, String, bool)> contents;
  final List<(String, String, bool)> boards;
  final bool hasMore;
  final int nextOffset;
  final String sessionId;
}

/// 热搜条目。
class HongguoHotItem {
  const HongguoHotItem({
    required this.position,
    required this.seriesId,
    required this.title,
    this.coverUrl = '',
    this.episodeCount = 0,
    this.heat = '',
    this.tag = '',
  });

  final int position;
  final String seriesId;
  final String title;
  final String coverUrl;
  final int episodeCount;
  final String heat;
  final String tag;
}

/// 一块热搜榜。
class HongguoHotBoard {
  const HongguoHotBoard({required this.name, required this.items});

  final String name;
  final List<HongguoHotItem> items;
}

/// 搜索页热搜聚合（猜你想搜 + 各榜）。
class HongguoHotSearch {
  const HongguoHotSearch({
    this.guesses = const [],
    this.boards = const [],
  });

  final List<HongguoHotItem> guesses;
  final List<HongguoHotBoard> boards;
}
