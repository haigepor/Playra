import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'content_search.dart';
import 'source_service.dart';
import 'source_models.dart';
import 'source_playback_service.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'source_resolve_config.dart';
import 'lumina/lumina_content_provider.dart';
import 'lumina/lumina_service.dart';
import 'package:kazumi/services/platform/lumina_support.dart';

/// 维护者接入新来源只需登记 Adapter；没有实现的来源不加入执行集合。
List<ContentSearchProvider> contentProviders(
  Iterable<Plugin> rules, {
  LuminaService? lumina,
  bool includeMetadata = true,
}) => [
  if (luminaSupported) LuminaContentProvider(lumina ?? LuminaService()),
  if (includeMetadata) BangumiContentProvider(),
];

/// 搜索入口只登记 Lumina 与 Bangumi；已安装规则保留给原有播放流程。
Future<List<ContentSearchProvider>> loadContentProviders(
  Iterable<Plugin> rules,
) async {
  return contentProviders(rules);
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
