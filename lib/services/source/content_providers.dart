import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'content_search.dart';
import 'miomedia/miomedia_service.dart';
import 'miomedia/miomedia_playback_provider.dart';
import 'sdk_playback_provider.dart';
import 'source_service.dart';
import 'source_models.dart';
import 'source_playback_service.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'source_resolve_config.dart';

/// 维护者接入新来源只需登记 Adapter；没有实现的来源不加入执行集合。
List<ContentSearchProvider> contentProviders(
  Iterable<Plugin> rules, {
  MioMediaService? mio,
  bool includeMetadata = true,
}) => [
  if (includeMetadata) BangumiContentProvider(),
  MioContentProvider(mio ?? MioMediaService()),
  for (final rule in rules)
    if (rule.enabled && RuleContentProvider(rule).groups.isNotEmpty)
      RuleContentProvider(rule),
];

/// 首次启动/开发预览尚未安装规则时只读内置规则，不覆盖禁用或自定义列表。
Future<List<ContentSearchProvider>> loadContentProviders(
  Iterable<Plugin> rules,
) async {
  final selected = rules.toList();
  if (selected.isEmpty) {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in manifest.listAssets().where(
      (p) => p.startsWith('assets/plugins/') && p.endsWith('.json'),
    )) {
      selected.add(
        Plugin.fromJson(jsonDecode(await rootBundle.loadString(path))),
      );
    }
  }
  return contentProviders(selected);
}

class RuleContentProvider extends ContentSearchProvider {
  RuleContentProvider(this.plugin);
  final Plugin plugin;
  @override
  String get id => plugin.providerId;
  @override
  String get name => plugin.name;
  @override
  String get origin {
    final uri = Uri.tryParse(plugin.baseUrl);
    return uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? uri.origin
        : id;
  }

  @override
  bool get canPlay => true;
  @override
  Set<ContentGroup> get groups {
    return ContentGroup.values
        .where((g) => plugin.profile.contentGroups.contains(g.name))
        .toSet();
  }

  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async {
    final definition = SourceDefinition.fromJson(plugin.toJson());
    final result = await SourceService.shared.search(
      definition,
      query.keyword,
      page: page,
      context: SourceContext(providerId: id, cancelToken: cancel),
    );
    return ContentSearchPage([
      for (final item in result.items)
        ContentHit(
          providerId: id,
          contentId: item.ref.rawRef,
          title: item.title,
          cover: item.coverUrl ?? '',
          group: groups.length == 1
              ? groups.single
              : ContentGroup.fromKind(item.classification.kind),
        ),
    ], hasMore: result.pagination.hasMore ?? false);
  }

  @override
  Future<List<ContentLine>> lines(ContentHit hit, CancelToken cancel) async {
    final result = await SourceService.shared.lines(
      SourceDefinition.fromJson(plugin.toJson()),
      SourceRef(providerId: id, rawRef: hit.contentId),
      context: SourceContext(providerId: id, cancelToken: cancel),
    );
    return [
      for (final line in result)
        ContentLine(line.id, line.name, [
          for (final e in line.episodes) ContentEpisode(e.pageUrl, e.title),
        ]),
    ];
  }

  @override
  Future<SourceResolvedMedia> resolve(
    ContentHit hit,
    ContentLine line,
    ContentEpisode episode,
    CancelToken cancel,
  ) async {
    final resolver = SourcePlaybackService(providerId: id);
    try {
      final media = await resolver.resolve(
        episode.id,
        useLegacyParser: plugin.useLegacyParser,
        definition: SourceDefinition.fromJson(plugin.toJson()),
        context: SourceContext(
          providerId: id,
          cancelToken: cancel,
          timeout: const Duration(seconds: 55),
        ),
      );
      final cookies = await PluginCookieManager.instance.loadForRequest(
        plugin.name,
        Uri.parse(media.url),
      );
      return SourceResolvedMedia(
        url: media.url,
        expiresAt: media.expiresAt,
        format: media.format == VideoSourceFormat.hls ? 'hls' : 'auto',
        inheritHeaders: media.inheritHeaders,
        headers: {
          if (media.inheritHeaders) ...plugin.buildHttpHeaders(),
          ...media.headers,
          if (media.inheritHeaders && cookies.isNotEmpty)
            'cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
          if (media.inheritHeaders &&
              cookies.isNotEmpty &&
              PluginCookieManager.instance.userAgentFor(plugin.name) != null)
            'user-agent': PluginCookieManager.instance.userAgentFor(
              plugin.name,
            )!,
        },
      );
    } finally {
      await resolver.dispose();
    }
  }
}

class MioContentProvider extends ContentSearchProvider {
  MioContentProvider(this.service);
  final MioMediaService service;
  final _entries = <String, MioVideo>{};
  MioVideo? entry(ContentHit hit) =>
      hit.providerId == id ? _entries[hit.contentId] : null;
  @override
  String get id => 'miomedia';
  @override
  String get name => 'miomedia';
  late final _sdkPlayback = MioSdkPlaybackProvider(service);
  @override
  SdkPlaybackProvider get sdkPlayback => _sdkPlayback;
  // 保留 SDK 已有内容；后续专属来源通过登记加入，不复制 SDK。
  @override
  Set<ContentGroup> get groups => {
    ContentGroup.screen,
    ContentGroup.comicDrama,
    ContentGroup.series,
  };
  @override
  bool get canPlay => true;
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async {
    final result = await service.search(
      query.keyword,
      page: page,
      cancel: cancel,
    );
    final items = <ContentHit>[];
    for (final video in result.items) {
      final group = ContentGroup.fromKind(video.kind.name);
      if (group == ContentGroup.anime ||
          query.group != null && query.group != group) {
        continue;
      }
      items.add(
        ContentHit(
          providerId: id,
          contentId: video.id,
          title: video.title,
          cover: video.cover,
          group: group,
          year: int.tryParse(video.year),
          region: video.area,
        ),
      );
      _entries[video.id] = video;
    }
    return ContentSearchPage(items, hasMore: result.hasMore);
  }

  @override
  Future<List<ContentLine>> lines(ContentHit hit, CancelToken cancel) async {
    final video = await service.detail(hit.contentId, cancel: cancel);
    return [
      for (final line in video.lines)
        ContentLine(line.code, line.label, const []),
    ];
  }

  @override
  Future<List<ContentEpisode>> episodes(
    ContentHit hit,
    ContentLine line,
    CancelToken cancel,
  ) async => [
    for (final e in await service.episodes(
      hit.contentId,
      line.id,
      cancel: cancel,
    ))
      ContentEpisode('${e.number}', e.label, number: e.number),
  ];
  @override
  Future<SourceResolvedMedia> resolve(
    ContentHit hit,
    ContentLine line,
    ContentEpisode episode,
    CancelToken cancel,
  ) async {
    final number = episode.number;
    if (number == null) {
      throw const SourceException('INVALID_REFERENCE', '缺少来源剧集编号');
    }
    final data = await service.play(
      hit.contentId,
      line.id,
      number,
      cancel: cancel,
    );
    if (data['status'] == 'ad_required') {
      throw const SourceException('AD_REQUIRED', '来源要求广告验证，请重试或选择其他来源');
    }
    if (data['status'] != 'ready') {
      throw const SourceException('PLAYBACK_UNAVAILABLE', '来源暂未提供播放材料');
    }
    final selected = data['selection'], media = data['media'];
    if (selected is! Map ||
        selected['videoId'] != hit.contentId ||
        selected['code'] != line.id ||
        selected['episodeNum'] != number) {
      throw const SourceException('IDENTITY_MISMATCH', '播放材料与所选作品或剧集不符');
    }
    final uri = media is Map && media['url'] is String
        ? Uri.tryParse(media['url'])
        : null;
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const SourceException('PARSE_ERROR', '来源媒体地址无效');
    }
    return SourceResolvedMedia(
      url: uri.toString(),
      headers: {
        if (media is Map && media['headers'] is Map)
          for (final entry in (media['headers'] as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
    );
  }

  @override
  void dispose() => service.dispose();
}

class BangumiContentProvider extends ContentSearchProvider {
  final _entries = <String, BangumiItem>{};
  BangumiItem? entry(ContentHit hit) =>
      hit.providerId == id ? _entries[hit.contentId] : null;
  @override
  String get id => 'bangumi-metadata';
  @override
  String get name => 'Bangumi 资料';
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async {
    final result = await BangumiApi.bangumiSearch(
      query.keyword,
      limit: 20,
      offset: (page - 1) * 20,
    );
    if (cancel.isCancelled) throw const SourceException('CANCELLED', '搜索已取消');
    if (result == null) {
      throw const SourceException('SOURCE_ERROR', 'Bangumi 资料查询失败');
    }
    for (final item in result.items) {
      _entries['${item.id}'] = item;
    }
    return ContentSearchPage([
      for (final item in result.items)
        ContentHit(
          providerId: id,
          contentId: '${item.id}',
          metadataId: 'bangumi:${item.id}',
          title: item.nameCn.isEmpty ? item.name : item.nameCn,
          aliases: [item.name, ...item.alias],
          cover: item.images['large'] ?? item.images['common'] ?? '',
          year: DateTime.tryParse(item.airDate)?.year,
          group: ContentGroup.anime,
        ),
    ], hasMore: result.rawCount == 20);
  }
}
