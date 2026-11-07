/// 红果匿名协议的响应解析（对标 openhongguo internal/protocol/parse.go）。
/// 服务端字段类型不稳定（数字/字符串混用），用 flex 辅助函数兜底。
library;

import 'dart:convert';

import 'hongguo_models.dart';

export 'hongguo_models.dart' show HongguoFeedContinuation;

// ---------------------------------------------------------------------------
// flex 辅助
// ---------------------------------------------------------------------------

String flexString(Object? v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  if (v is num) return _trimNum(v);
  return '';
}

String _trimNum(num v) {
  if (v is int) return v.toString();
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

int flexInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
  }
  return 0;
}

bool flexBool(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0' || s.isEmpty) return false;
    return true;
  }
  return true;
}

/// video_data / book_data / post_data 既可能是对象也可能是数组。
List<Map<String, dynamic>> flexList(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return v.whereType<Map<String, dynamic>>().toList();
  }
  if (v is Map<String, dynamic>) return [v];
  return const [];
}

// ---------------------------------------------------------------------------
// 业务错误分类（codes.go）
// ---------------------------------------------------------------------------

class HongguoErrorKind {
  const HongguoErrorKind._(this.name);
  final String name;
  @override
  String toString() => name;

  static const unknown = HongguoErrorKind._('unknown');
  static const auth = HongguoErrorKind._('auth');
  static const rateLimited = HongguoErrorKind._('rate_limited');
  static const contentGone = HongguoErrorKind._('content_gone');
  static const param = HongguoErrorKind._('param');
  static const challenge = HongguoErrorKind._('challenge');
  static const clientRejected = HongguoErrorKind._('client_rejected');
  static const deviceRejected = HongguoErrorKind._('device_rejected');
  static const endOfList = HongguoErrorKind._('end_of_list');
}

/// 把业务码（与 message）归类到 ErrorKind；顺序与 Go Classify 一致。
HongguoErrorKind classifyCode(int code, String message) {
  switch (code) {
    case 0:
      return HongguoErrorKind.unknown;
    case 101:
      return HongguoErrorKind.endOfList;
    case 100 || 101143 || 101144 || 1000003:
      return HongguoErrorKind.rateLimited;
    case 101108 || 101123 || 4001 || 101009:
      return HongguoErrorKind.auth;
    case 101104 || 101109 || 101121 || 101137 || 101145 || 101115:
      return HongguoErrorKind.contentGone;
    case 100103 || 4000 || 101142 || 110:
      return HongguoErrorKind.param;
    case 111:
      return HongguoErrorKind.challenge;
    case 112:
      return HongguoErrorKind.clientRejected;
  }
  const contentGoneSet = {
    101101, 101102, 101103, 101105, 101106, 101107, 101110, 101111, 101112,
    101113, 101114, 101116, 101117, 101118, 101119, 101120, 101122, 101124,
    101130, 101131, 101132, 101133, 101134, 101135, 101136, 101138, 101139,
    101140, 101141, 101146, 101147, 101148, 101149,
  };
  if (contentGoneSet.contains(code)) return HongguoErrorKind.contentGone;
  if (code >= 101000 && code < 101200) return HongguoErrorKind.contentGone;
  final lower = message.toLowerCase().trim();
  if (lower.isEmpty || lower == 'success') return HongguoErrorKind.unknown;
  for (final kw in ['登录', 'login', 'sign in']) {
    if (lower.contains(kw)) return HongguoErrorKind.auth;
  }
  for (final kw in ['频繁', '限流', 'too many', 'frequent', 'rate limit']) {
    if (lower.contains(kw)) return HongguoErrorKind.rateLimited;
  }
  for (final kw in ['下架', '不存在', '已删除', 'removed', 'not exist', 'unavailable']) {
    if (lower.contains(kw)) return HongguoErrorKind.contentGone;
  }
  return HongguoErrorKind.unknown;
}

/// 读信封里的 (code, message)；body 不是 JSON 信封时返回 null。
(String, String)? businessCode(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final codeRaw = root['code'];
  if (codeRaw == null) return null;
  return (flexString(codeRaw), root['message']?.toString() ?? '');
}

/// BaseResp.StatusCode（263175/263176 = 设备被拒）。
int baseStatus(Object? root) {
  if (root is! Map<String, dynamic>) return 0;
  final base = root['BaseResp'];
  if (base is! Map<String, dynamic>) return 0;
  return flexInt(base['StatusCode']);
}

bool deviceRejectedStatus(int status) => status == 263175 || status == 263176;

/// FAST_REJECT 消息里的封禁窗口（秒）。
(int, int)? banWindow(String message) {
  final m = message.trim();
  if (!m.startsWith('{')) return null;
  try {
    final v = jsonDecode(m);
    if (v is! Map<String, dynamic>) return null;
    final minBan = flexInt(v['minBanTime']);
    final maxBan = flexInt(v['maxBanTime']);
    if (minBan <= 0 && maxBan <= 0) return null;
    return (minBan, maxBan);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// 书城 / 翻页
// ---------------------------------------------------------------------------

void _appendCatalogCell(List<HongguoSeriesSummary> items, Map<String, dynamic> cell) {
  for (final v in flexList(cell['video_data'])) {
    final seriesId = flexString(v['series_id']);
    final detail = v['video_detail'];
    final d = detail is Map<String, dynamic> ? detail : const <String, dynamic>{};
    var title = flexString(d['series_title']);
    if (title.isEmpty) title = flexString(v['title']);
    if (seriesId.isEmpty || title.isEmpty) continue;
    var count = flexInt(d['episode_cnt']);
    if (count == 0) {
      count = (d['video_list'] as List?)?.length ?? 0;
    }
    items.add(HongguoSeriesSummary(
      id: seriesId,
      title: title,
      description: flexString(d['series_intro']),
      coverUrl: flexString(d['series_cover']),
      episodeCount: count,
    ));
  }
  // video_detail 里的卡片（嵌套剧集列表）。
  final detail = cell['video_detail'];
  if (detail is Map<String, dynamic>) {
    for (final card in flexList(detail['video_detail_list'])) {
      var id = flexString(card['series_id_str']);
      if (id.isEmpty) id = flexString(card['series_id']);
      final title = flexString(card['series_title']);
      if (id.isEmpty || title.isEmpty) continue;
      items.add(HongguoSeriesSummary(
        id: id,
        title: title,
        description: flexString(card['series_intro']),
        coverUrl: flexString(card['series_cover']),
        episodeCount: flexInt(card['episode_cnt']),
      ));
    }
  }
  for (final book in flexList(cell['book_data'])) {
    final id = flexString(book['book_id']);
    final title = flexString(book['name']);
    if (id.isEmpty || title.isEmpty) continue;
    items.add(HongguoSeriesSummary(
      id: id,
      title: title,
      description: flexString(book['abstract']),
      coverUrl: flexString(book['thumb_url']),
      episodeCount: flexInt(book['serial_count']),
    ));
  }
  for (final nested in flexList(cell['cell_data'])) {
    _appendCatalogCell(items, nested);
  }
}

void _appendBooks(List<HongguoSeriesSummary> items, List<Map<String, dynamic>> rows) {
  for (final book in rows) {
    final id = flexString(book['book_id']);
    final title = flexString(book['name']).trim();
    if (id.isEmpty || title.isEmpty) continue;
    items.add(HongguoSeriesSummary(
      id: id,
      title: title,
      description: flexString(book['abstract']).trim(),
      coverUrl: flexString(book['thumb_url']),
      episodeCount: flexInt(book['serial_count']),
    ));
  }
}

/// 书城 tab（bookmall/tab/v）。[tabType] 16 = 推荐 video_feed。
HongguoCatalogPage? parseDiscoverTab(Object? root, int tabType) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  final items = <HongguoSeriesSummary>[];
  var hasMore = false;
  for (final tab in flexList(data['tab_item'])) {
    if (flexInt(tab['tab_type']) != tabType) continue;
    hasMore = flexBool(tab['has_more']);
    for (final cell in flexList(tab['cell_data'])) {
      _appendCatalogCell(items, cell);
    }
  }
  return HongguoCatalogPage(items: items, hasMore: hasMore);
}

/// 无限流句柄（cell_id + session + show_type + offset），供 cell/change 翻页。
HongguoFeedContinuation? discoverContinuation(Object? root, int tabType) {
  if (root is! Map<String, dynamic>) return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  HongguoFeedContinuation? fallback;
  for (final tab in flexList(data['tab_item'])) {
    if (flexInt(tab['tab_type']) != tabType) continue;
    final session = flexString(tab['session_id']);
    if (session.isEmpty) continue;
    final template = flexInt(tab['client_template']);
    for (final cell in flexList(tab['cell_data'])) {
      final id = flexString(cell['cell_id_str']);
      final showType = flexInt(cell['show_type']);
      if (id.isEmpty || showType == 0) continue;
      final next = (
        cellId: id,
        sessionId: session,
        clientTemplate: template > 0 ? '$template' : '',
        showType: '$showType',
        tabType: '${flexInt(tab['tab_type'])}',
        // 书城首屏之后的 cell/change 从 offset 0 起翻。
        offset: '0',
      );
      if (flexList(cell['cell_data']).isNotEmpty) return next;
      fallback ??= next;
    }
  }
  return fallback;
}

/// cell/change 无限流页。
HongguoCatalogPage? parseCellChange(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  final items = <HongguoSeriesSummary>[];
  final view = data['cell_view'];
  if (view is Map<String, dynamic>) {
    _appendCatalogCell(items, view);
  }
  return HongguoCatalogPage(
    items: items,
    hasMore: flexBool(data['has_more']),
    nextOffset: flexInt(data['next_offset']),
    sessionId: flexString(data['session_id']),
  );
}

// ---------------------------------------------------------------------------
// 搜索
// ---------------------------------------------------------------------------

/// 搜索 tab（search/tab/v）。[tabType] 11 = 短剧综合。
HongguoCatalogPage? parseSearchTab(Object? root, int tabType) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final items = <HongguoSeriesSummary>[];
  var hasMore = false;
  var nextOffset = 0;
  for (final tab in flexList(root['search_tabs'])) {
    if (flexInt(tab['tab_type']) != tabType) continue;
    hasMore = flexBool(tab['has_more']);
    nextOffset = flexInt(tab['next_offset']);
    for (final row in flexList(tab['data'])) {
      for (final v in flexList(row['video_data'])) {
        final seriesId = flexString(v['series_id']);
        final detail = v['video_detail'];
        final d = detail is Map<String, dynamic> ? detail : const <String, dynamic>{};
        final title = flexString(d['series_title']).trim();
        if (seriesId.isNotEmpty && title.isNotEmpty) {
          items.add(HongguoSeriesSummary(
            id: seriesId,
            title: title,
            description: flexString(d['series_intro']),
            episodeCount: flexInt(d['episode_cnt']),
          ));
          continue;
        }
        for (final card in flexList(d['video_detail_list'])) {
          var cid = flexString(card['series_id_str']);
          if (cid.isEmpty) cid = flexString(card['series_id']);
          final ctitle = flexString(card['series_title']).trim();
          if (cid.isEmpty || ctitle.isEmpty) continue;
          items.add(HongguoSeriesSummary(
            id: cid,
            title: ctitle,
            description: flexString(card['series_intro']),
            coverUrl: flexString(card['series_cover']),
            episodeCount: flexInt(card['episode_cnt']),
          ));
        }
      }
      _appendBooks(items, flexList(row['book_data']));
    }
  }
  return HongguoCatalogPage(items: items, hasMore: hasMore, nextOffset: nextOffset);
}

// ---------------------------------------------------------------------------
// 详情与分集（video_detail）
// ---------------------------------------------------------------------------

/// 读 video_detail：返回 (series, episodes)。分集集数从 1 开始。
(HongguoSeries, List<HongguoEpisode>)? parseSeries(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  final v = data['video_data'];
  if (v is! Map<String, dynamic>) return null;
  var id = flexString(v['series_id_str']);
  if (id.isEmpty) id = flexString(v['series_id']);
  final title = flexString(v['series_title']);
  if (id.isEmpty || title.isEmpty) return null;
  final cover = flexString(v['series_cover']);
  final series = HongguoSeries(
    id: id,
    title: title,
    description: flexString(v['series_intro']),
    coverUrl: cover,
    episodeCount: flexInt(v['episode_cnt']),
    heat: flexInt(v['hot_score']),
    playCount: flexInt(v['series_play_cnt']),
    status: flexInt(v['series_status']),
    isMultiSeason: flexBool(v['is_multi_season']),
    seasonIndex: flexInt(v['season_index']),
    rightText: flexString(v['episode_right_text']),
  );

  final list = flexList(v['video_list']);
  var episodeCount = series.episodeCount;
  if (episodeCount == 0) episodeCount = list.length;

  // wire 的 vid_index 可能从 0 开始；整体 +1 平移。
  var shift = 0;
  if (list.isNotEmpty) {
    var min = flexInt(list.first['vid_index']);
    for (final e in list.skip(1)) {
      final n = flexInt(e['vid_index']);
      if (n < min) min = n;
    }
    if (min == 0) shift = 1;
  }
  // 详情响应会把简介复制进每集标题；此时按集数命名。
  final intro = flexString(v['series_intro']).trim();
  var sharedTitle = list.length > 1;
  var shared = '';
  for (var i = 0; i < list.length; i++) {
    final t = flexString(list[i]['title']).trim();
    if (i == 0) {
      shared = t;
      continue;
    }
    if (t != shared) {
      sharedTitle = false;
      break;
    }
  }
  final episodes = <HongguoEpisode>[];
  for (final e in list) {
    final eid = flexString(e['vid']);
    if (eid.isEmpty) return null;
    final number = flexInt(e['vid_index']) + shift;
    if (number < 1) return null;
    var seriesId = flexString(e['series_id']);
    if (seriesId.isEmpty) seriesId = id;
    var title = flexString(e['title']).trim();
    if (title.isEmpty || title == intro || (sharedTitle && title == shared)) {
      title = '第$number集';
    }
    final coverUrl = () {
      final ec = flexString(e['episode_cover']);
      if (ec.isNotEmpty) return ec;
      return flexString(e['cover']);
    }();
    episodes.add(HongguoEpisode(
      id: eid,
      seriesId: seriesId,
      number: number,
      title: title,
      playable: !flexBool(e['disable_play']),
      vertical: flexBool(e['vertical']),
      coverUrl: coverUrl,
      durationSeconds: flexInt(e['duration']),
    ));
  }
  return (
    HongguoSeries(
      id: series.id,
      title: series.title,
      description: series.description,
      coverUrl: series.coverUrl,
      episodeCount: episodeCount,
      heat: series.heat,
      playCount: series.playCount,
      status: series.status,
      isMultiSeason: series.isMultiSeason,
      seasonIndex: series.seasonIndex,
      rightText: series.rightText,
    ),
    episodes,
  );
}

// ---------------------------------------------------------------------------
// 播放模型（video_model）
// ---------------------------------------------------------------------------

/// TTVideoEngine 模型里的一个表示形式（清晰度）。
Map<String, dynamic>? _streamOf(Object? item) {
  if (item is! Map<String, dynamic>) return null;
  return item;
}

Object? _nonEmptyJson(Object? v) {
  if (v == null) return null;
  if (v is Map && v.isEmpty) return null;
  if (v is List && v.isEmpty) return null;
  if (v is String && (v.trim().isEmpty || v.trim() == 'null')) return null;
  return v;
}

bool _jsonTruthy(Object? v) {
  final b = _nonEmptyJson(v);
  if (b == null) return false;
  if (b is bool) return b;
  if (b is num) return b != 0;
  if (b is String) {
    final s = b.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0' || s.isEmpty) return false;
    return true;
  }
  return true;
}

String _firstNonEmpty(List<String> values) {
  for (final v in values) {
    final s = v.trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// 读 video_model 响应；找不到可用表示形式时返回 null。
HongguoPlayback? parsePlayback(Object? root, String episodeId) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  var modelRaw = data['video_model'];
  if (modelRaw is String) {
    final s = modelRaw.trim();
    if (s.isEmpty) return null;
    try {
      modelRaw = jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  if (modelRaw is! Map<String, dynamic>) return null;
  final videoId = flexString(modelRaw['video_id']);
  final mediaType = flexString(modelRaw['media_type']).trim();
  final duration = flexInt(modelRaw['video_duration']);
  final urlExpire = flexInt(modelRaw['url_expire']);

  List<Map<String, dynamic>> items = [];
  final videoList = modelRaw['video_list'];
  if (videoList is List) {
    items = flexList(videoList);
  } else if (videoList is Map<String, dynamic>) {
    // 对象按 definition 键组织；键序排序保证输出稳定。
    final keys = videoList.keys.toList()..sort();
    items = [
      for (final k in keys)
        {
          ...(videoList[k] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
          '__definition_key': k,
        }
    ];
  }
  var audioUrl = '';
  if (items.isEmpty) {
    final dynamicRaw = modelRaw['dynamic_video'];
    if (dynamicRaw is Map<String, dynamic>) {
      items = flexList(dynamicRaw['dynamic_video_list']);
      final audios = flexList(dynamicRaw['dynamic_audio_list']);
      if (audios.isNotEmpty) {
        audioUrl = flexString(audios.first['main_url']).trim();
      }
    }
  }

  final streams = <HongguoStream>[];
  var protectedCount = 0;
  var keyMaterial = '';
  for (final item in items) {
    final meta = _streamOf(item['video_meta']) ?? const <String, dynamic>{};
    final url = flexString(item['main_url']).trim();
    if (url.isEmpty) continue;
    var definition = _firstNonEmpty(
      [flexString(meta['definition']), flexString(item['definition'])],
    );
    if (definition.isEmpty) {
      definition = flexString(item['__definition_key']);
    }
    var quality = _firstNonEmpty(
      [flexString(meta['quality']), flexString(item['quality'])],
    );
    final qualityDesc = _firstNonEmpty([
      flexString(meta['quality_desc']),
      flexString(item['quality_desc']),
    ]);
    if (quality.isEmpty && qualityDesc.isNotEmpty) quality = qualityDesc;
    final codec = _firstNonEmpty(
      [flexString(meta['codec_type']), flexString(item['codec_type'])],
    );
    final width = flexInt(meta['vwidth']) != 0
        ? flexInt(meta['vwidth'])
        : flexInt(item['vwidth']);
    final height = flexInt(meta['vheight']) != 0
        ? flexInt(meta['vheight'])
        : flexInt(item['vheight']);
    final bitrate = flexInt(meta['bitrate']) != 0
        ? flexInt(meta['bitrate'])
        : flexInt(item['bitrate']);
    final size = flexInt(meta['size']) != 0
        ? flexInt(meta['size'])
        : flexInt(item['size']);
    final hls = _jsonTruthy(item['hls']) ||
        flexString(item['m3u8']).trim().isNotEmpty ||
        flexString(meta['vtype']).toLowerCase() == 'm3u8' ||
        flexString(item['vtype']).toLowerCase() == 'm3u8';
    final dash =
        flexString(meta['vtype']).toLowerCase() == 'dash' ||
            flexString(item['vtype']).toLowerCase() == 'dash';

    // 加密标记：encrypt_info 对象 / spade_a / kid / gear_des_key / encryption_method。
    final encryptInfo = _nonEmptyJson(item['encrypt_info']);
    final info =
        encryptInfo is Map<String, dynamic> ? encryptInfo : null;
    var method = flexString(item['encryption_method']).trim();
    var protected = false;
    if (info != null) {
      if (method.isEmpty) {
        method = flexString(info['encryption_method']).trim();
      }
      if (flexBool(info['encrypt']) ||
          method.isNotEmpty ||
          flexString(info['kid']).isNotEmpty ||
          flexString(info['spade_a']).isNotEmpty) {
        protected = true;
      }
    } else if (encryptInfo != null) {
      protected = true;
    }
    if (!protected) {
      if (flexString(item['gear_des_key']).isNotEmpty ||
          flexString(item['spade_a']).isNotEmpty ||
          flexString(item['kid']).isNotEmpty ||
          method.isNotEmpty ||
          _jsonTruthy(item['encrypt']) ||
          _nonEmptyJson(item['check_info']) != null) {
        protected = true;
      }
    }
    if (protected) protectedCount++;

    if (keyMaterial.isEmpty) {
      final spadeFromInfo = info == null ? '' : flexString(info['spade_a']).trim();
      final spade = spadeFromInfo.isNotEmpty
          ? spadeFromInfo
          : flexString(item['spade_a']).trim();
      if (spade.isNotEmpty) keyMaterial = spade;
    }
    streams.add(HongguoStream(
      definition: definition,
      quality: quality,
      codec: codec,
      width: width,
      height: height,
      bitrate: bitrate,
      size: size,
      url: url,
      backupUrl: _firstNonEmpty([
        flexString(item['backup_url']),
        flexString(item['backup_url_1']),
      ]),
      hls: hls,
      dash: dash,
      protected: protected,
      encryption: method,
    ));
  }
  if (streams.isEmpty) return null;
  return HongguoPlayback(
    episodeId: episodeId,
    videoId: videoId,
    mediaType: mediaType,
    durationSeconds: duration,
    expiresAt: urlExpire,
    protected: protectedCount == streams.length,
    streams: streams,
    keyMaterial: keyMaterial,
    audioUrl: audioUrl,
  );
}

// ---------------------------------------------------------------------------
// 短剧榜单（cell/change on ShortRankCell）
// ---------------------------------------------------------------------------

int _recommendRank(Object? rec) {
  var b = _nonEmptyJson(rec);
  if (b == null) return 0;
  if (b is String) {
    try {
      b = jsonDecode(b);
    } catch (_) {
      return 0;
    }
  }
  if (b is! Map<String, dynamic>) return 0;
  return flexInt(b['rank']);
}

const String promotedText = '广告';

HongguoShortRanking? parseShortRank(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final data = root['data'];
  if (data is! Map<String, dynamic>) return null;
  final items = <HongguoRankItem>[];
  final contents = <(String, String, bool)>[];
  final boards = <(String, String, bool)>[];
  final cellView = data['cell_view'];
  if (cellView is Map<String, dynamic>) {
    final selector = cellView['cell_selector'];
    if (selector is Map<String, dynamic>) {
      final outer = selector['outer_row'];
      if (outer is Map<String, dynamic>) {
        for (final opt in flexList(outer['items'])) {
          final id = flexString(opt['selector_item_id']);
          if (id.isNotEmpty) {
            contents.add((
              id,
              flexString(opt['show_name']),
              flexBool(opt['is_selected']),
            ));
          }
          final sub = opt['sub_cell_selector'];
          if (sub is Map<String, dynamic>) {
            final subRow = sub['outer_row'];
            if (subRow is Map<String, dynamic>) {
              for (final b in flexList(subRow['items'])) {
                final bid = flexString(b['selector_item_id']);
                if (bid.isNotEmpty) {
                  boards.add((
                    bid,
                    flexString(b['show_name']),
                    flexBool(b['is_selected']),
                  ));
                }
              }
            }
          }
        }
      }
    }
    for (final cell in flexList(cellView['cell_data'])) {
      for (final v in flexList(cell['video_data'])) {
        final id = flexString(v['series_id']);
        final title = flexString(v['title']).trim();
        if (id.isEmpty || title.isEmpty) continue;
        final score = flexString(
          (v['rec_text_item'] is Map<String, dynamic>)
              ? (v['rec_text_item'] as Map<String, dynamic>)['RecommendText']
              : null,
        );
        items.add(HongguoRankItem(
          position: items.length + 1,
          rank: _recommendRank(v['recommend_info']),
          title: title,
          seriesId: id,
          coverUrl: flexString(v['cover']),
          score: score,
          episodeCount: flexInt(v['episode_cnt']),
          promoted: score == promotedText,
        ));
      }
    }
  }
  return HongguoShortRanking(
    items: items,
    contents: contents,
    boards: boards,
    hasMore: flexBool(data['has_more']),
    nextOffset: flexInt(data['next_offset']),
    sessionId: flexString(data['session_id']),
  );
}

// ---------------------------------------------------------------------------
// 热搜（plan feed 的 lynx_data）
// ---------------------------------------------------------------------------

List<HongguoHotItem> _hotItems(List<Map<String, dynamic>> rows) {
  final out = <HongguoHotItem>[];
  for (final r in rows) {
    final id = flexString(r['series_id']);
    if (id.isEmpty) continue;
    final tag = r['tag_info'];
    out.add(HongguoHotItem(
      position: out.length + 1,
      seriesId: id,
      title: flexString(r['title']),
      coverUrl: flexString(r['cover']),
      episodeCount: flexInt(r['episode_cnt']),
      heat: flexString(r['rec_text']),
      tag: tag is Map<String, dynamic> ? flexString(tag['text']) : '',
    ));
  }
  return out;
}

HongguoHotSearch? parseHotSearch(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final (code, _) = businessCode(root) ?? ('', '');
  if (code.isNotEmpty && code != '0') return null;
  final guesses = <HongguoHotItem>[];
  final boards = <HongguoHotBoard>[];
  final data = root['data'];
  final cells = data is List ? data : const [];
  for (final c in cells) {
    if (c is! Map<String, dynamic>) continue;
    var lynx = c['lynx_data'];
    final raw = _nonEmptyJson(lynx);
    if (raw == null) continue;
    if (raw is String) {
      try {
        lynx = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (lynx is! List) continue;
    for (final cell in flexList(lynx)) {
      guesses.addAll(_hotItems(flexList(cell['video_data'])));
      for (final boardRaw in flexList(cell['cell_data'])) {
        final board = HongguoHotBoard(
          name: flexString(boardRaw['cell_name']),
          items: _hotItems(flexList(boardRaw['video_data'])),
        );
        if (board.items.isNotEmpty) boards.add(board);
      }
    }
  }
  return HongguoHotSearch(guesses: guesses, boards: boards);
}

// ---------------------------------------------------------------------------
// 注册响应
// ---------------------------------------------------------------------------

/// 读 device_register 响应；缺 id 视为失败返回 null。
({String deviceId, String installId, int newUser})? parseRegister(Object? root) {
  if (root is! Map<String, dynamic>) return null;
  final deviceId = flexString(root['device_id_str'] ?? root['device_id']);
  final installId = flexString(root['install_id_str'] ?? root['install_id']);
  if (deviceId.isEmpty || deviceId == '0') return null;
  if (installId.isEmpty || installId == '0') return null;
  return (deviceId: deviceId, installId: installId, newUser: flexInt(root['new_user']));
}
