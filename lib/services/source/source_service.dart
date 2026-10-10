import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'source_models.dart';
import 'rule_directory_config.dart';

class SourceDefinition {
  SourceDefinition._(this._json, this.manifest, this.execution);
  final Map<String, dynamic> _json;
  final SourceManifest manifest;
  final RuleExecutionConfig execution;
  Map<String, dynamic> get options =>
      Map<String, dynamic>.from(_json['sourceConfig'] as Map? ?? const {});
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
  factory SourceDefinition.fromJson(
    Map<String, dynamic> json, {
    String origin = 'imported',
  }) {
    final data = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    final name = data['name'] as String? ?? '';
    final api = int.tryParse(data['api']?.toString() ?? '1');
    if (name.trim().isEmpty || api == null || api < 1 || api > 8) {
      throw const SourceException('INVALID_RULE', '规则名称或协议级别无效');
    }
    Map<String, dynamic> map(String key) =>
        Map<String, dynamic>.from(data[key] as Map? ?? const {});
    final legacyName = name.toLowerCase();
    final id =
        data['sourceId'] as String? ??
        (RegExp(r'^[a-zA-Z0-9_\-.:\u3400-\u9fff]{1,100}$').hasMatch(legacyName)
            ? legacyName
            : 'legacy-${SourceRef(providerId: 'legacy', rawRef: legacyName).id.substring(0, 24)}');
    if (!RegExp(r'^[a-zA-Z0-9_\-.:\u3400-\u9fff]{1,100}$').hasMatch(id)) {
      throw const SourceException('INVALID_RULE', '来源标识无效');
    }
    return SourceDefinition._(
      data,
      SourceManifest(
        id: id,
        name: name,
        version: data['version']?.toString() ?? '',
        apiLevel: api,
        origin: origin,
        capabilities: [
          'search',
          'episodes',
          'resolve',
          if (directoryConfig(data) != null) ...['catalog', 'categories'],
        ],
      ),
      RuleExecutionConfig(
        pluginName: name,
        baseUrl: data['baseURL'] as String? ?? '',
        usePost: data['usePost'] == true,
        searchMode: RuleMode.normalize(data['searchMode']),
        chapterMode: RuleMode.normalize(data['chapterMode']),
        searchUrl: data['searchURL'] as String? ?? '',
        searchList: data['searchList'] as String? ?? '',
        searchName: data['searchName'] as String? ?? '',
        searchResult: data['searchResult'] as String? ?? '',
        chapterRoads: data['chapterRoads'] as String? ?? '',
        chapterResult: data['chapterResult'] as String? ?? '',
        searchApiConfig: ApiSearchConfig.fromJson(map('searchApiConfig')),
        chapterApiConfig: ApiChapterConfig.fromJson(map('chapterApiConfig')),
        antiCrawlerConfig: AntiCrawlerConfig.fromJson(map('antiCrawlerConfig')),
      ),
    );
  }
}

class SourceService {
  SourceService({RuleEngine? engine}) : engine = engine ?? RuleEngine();
  static final shared = SourceService();
  final RuleEngine engine;
  final Map<String, Map<String, SourceHealth>> _health = {};
  SourceHealth? health(String id, String operation) => _health[id]?[operation];
  Map<String, dynamic> healthJson(String id) => {
    for (final entry in (_health[id] ?? <String, SourceHealth>{}).entries)
      entry.key: entry.value.toJson(),
  };

  Future<T> observe<T>(
    String id,
    String operation,
    SourceContext context,
    Future<T> Function() action,
  ) async {
    context.checkActive();
    final watch = Stopwatch()..start();
    try {
      final result = await action().timeout(
        context.timeout,
        onTimeout: () {
          context.cancelToken.cancel('deadline');
          throw const SourceException('TIMEOUT', '来源请求超时');
        },
      );
      context.checkActive();
      (_health[id] ??= {})[operation] = SourceHealth(
        operation: operation,
        status: 'success',
        checkedAt: DateTime.now(),
        elapsedMs: watch.elapsedMilliseconds,
      );
      return result;
    } catch (error) {
      final mapped =
          context.cancelToken.isCancelled &&
              !(error is SourceException && error.code == 'TIMEOUT')
          ? SourceException('CANCELLED', '请求已取消', providerId: id)
          : mapError(error, id);
      if (mapped.code != 'CANCELLED') {
        (_health[id] ??= {})[operation] = SourceHealth(
          operation: operation,
          status: mapped.code == 'CHALLENGE_REQUIRED'
              ? 'challenge_required'
              : 'failed',
          checkedAt: DateTime.now(),
          elapsedMs: watch.elapsedMilliseconds,
          errorCode: mapped.code,
        );
      }
      throw mapped;
    }
  }

  static SourceException mapError(Object error, String id) {
    if (error is SourceException) return error;
    if (error is CaptchaRequiredException) {
      return SourceException('CHALLENGE_REQUIRED', '需要完成来源验证', providerId: id);
    }
    if ((error is NetworkException &&
            error.type == NetworkExceptionType.cancel) ||
        (error is DioException && error.type == DioExceptionType.cancel)) {
      return SourceException('CANCELLED', '请求已取消', providerId: id);
    }
    if (error is TimeoutException) {
      return SourceException('TIMEOUT', '来源请求超时', providerId: id);
    }
    return SourceException('SOURCE_ERROR', '来源请求或解析失败', providerId: id);
  }

  Future<RuleSearchTrace> traceSearch(
    SourceDefinition source,
    String keyword, {
    SourceContext? context,
  }) => engine.search(
    source.execution,
    keyword,
    cancelToken: context?.cancelToken,
  );
  Future<RuleChapterTrace> traceChapters(
    SourceDefinition source,
    String rawRef, {
    SourceContext? context,
  }) => engine.queryChapters(
    source.execution,
    rawRef,
    cancelToken: context?.cancelToken,
  );

  Future<SourcePage<SourceContent>> search(
    SourceDefinition source,
    String keyword, {
    SourceContext? context,
    int page = 1,
    int pageSize = 20,
    bool paginate = true,
  }) async {
    SourcePage.validate(page, pageSize);
    if (keyword.trim().isEmpty || keyword.length > 300) {
      throw const SourceException('INVALID_ARGUMENT', '搜索词不能为空且不得超过 300 字符');
    }
    final ctx = context ?? SourceContext();
    return observe(source.manifest.id, 'search', ctx, () async {
      final paging = Map<String, dynamic>.from(
        source.options['searchPagination'] as Map? ?? const {},
      );
      final upstream =
          paging['enabled'] == true &&
          source.execution.searchMode == RuleMode.api;
      if (upstream &&
          !RegExp(r'@page(?![A-Za-z0-9_])').hasMatch(
            jsonEncode(source.execution.searchApiConfig.request.toJson()),
          )) {
        throw const SourceException('INVALID_RULE', '上游分页需要规则声明 @page 参数');
      }
      RuleSearchTrace? trace;
      try {
        trace = await engine.search(
          source.execution,
          keyword,
          cancelToken: ctx.cancelToken,
          variables: upstream ? {'page': page, 'pageSize': pageSize} : const {},
        );
      } on NoResultException {
        // 无匹配属于成功的空集合，不作为来源故障。
      }
      final type = source.toJson()['type'];
      final kind =
          const [
            'anime',
            'movie',
            'tv',
            'variety',
            'comic',
            'documentary',
          ].contains(type)
          ? type as String
          : 'unknown';
      final items = (trace?.response.data ?? [])
          .map(
            (e) => SourceContent(
              ref: SourceRef(providerId: source.manifest.id, rawRef: e.src),
              title: e.name,
              classification: SourceClassification(
                kind: kind,
                evidence: kind == 'unknown' ? 'unknown' : 'rule',
              ),
            ),
          )
          .toList();
      if (!upstream) {
        if (!paginate) {
          return SourcePage(
            items,
            SourcePagination(
              page: 1,
              pageSize: items.length,
              mode: 'local',
              total: items.length,
              hasMore: false,
            ),
          );
        }
        return SourcePage.local(items, page: page, pageSize: pageSize);
      }
      final document = trace == null ? null : jsonDecode(trace.rawResponse);
      Object? read(String name) => document == null || paging[name] is! String
          ? null
          : RestrictedJsonPath.readFirst(document, paging[name] as String);
      final total = read('totalPath');
      final hasMore = read('hasMorePath');
      return SourcePage(
        items,
        SourcePagination(
          page: page,
          pageSize: pageSize,
          mode: 'upstream',
          total: total is int && total >= 0 ? total : null,
          hasMore: hasMore is bool ? hasMore : null,
        ),
      );
    });
  }

  Future<List<SourceLine>> lines(
    SourceDefinition source,
    SourceRef ref, {
    SourceContext? context,
  }) async {
    if (ref.providerId != source.manifest.id || ref.rawRef.isEmpty) {
      throw const SourceException('INVALID_REFERENCE', '条目不属于当前来源');
    }
    final ctx = context ?? SourceContext();
    return observe(source.manifest.id, 'episodes', ctx, () async {
      final trace = await traceChapters(source, ref.rawRef, context: ctx);
      return [
        for (var i = 0; i < trace.roads.length; i++)
          SourceLine(
            id: '${ref.id}:$i',
            name: trace.roads[i].name,
            episodes: [
              for (var j = 0; j < trace.roads[i].data.length; j++)
                SourceEpisode(
                  id: SourceRef(
                    providerId: source.manifest.id,
                    rawRef: trace.roads[i].data[j],
                  ).id,
                  title: j < trace.roads[i].identifier.length
                      ? trace.roads[i].identifier[j]
                      : '${j + 1}',
                  pageUrl: trace.roads[i].data[j],
                  index: j,
                ),
            ],
          ),
      ];
    });
  }

  Future<List<Map<String, dynamic>>> searchAll(
    List<SourceDefinition> sources,
    String keyword, {
    SourceContext? context,
    int concurrency = 4,
  }) async {
    final ctx = context ?? SourceContext();
    final result = List<Map<String, dynamic>?>.filled(sources.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        ctx.checkActive();
        final index = next++;
        final source = sources[index];
        try {
          final page = await search(
            source,
            keyword,
            context: SourceContext(
              cancelToken: ctx.cancelToken,
              sessionId: ctx.sessionId,
              timeout: ctx.timeout,
            ),
          );
          result[index] = {
            'providerId': source.manifest.id,
            'data': page.items.map((e) => e.toJson()).toList(),
            'pagination': page.pagination.toJson(),
          };
        } on SourceException catch (error) {
          if (error.code == 'CANCELLED') rethrow;
          result[index] = {
            'providerId': source.manifest.id,
            'error': error.toJson(),
          };
        }
      }
    }

    await Future.wait(List.generate(concurrency.clamp(1, 8), (_) => worker()));
    return result.whereType<Map<String, dynamic>>().toList();
  }
}
