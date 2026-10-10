import 'package:html/parser.dart' as html;
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'rule_directory_config.dart';
import 'source_models.dart';
import 'source_service.dart';

class SourceDirectoryResult {
  const SourceDirectoryResult({
    this.name = '',
    this.items = const [],
    this.failures = const [],
    this.elapsedMs = 0,
  });
  final String name;
  final List<SourceContent> items;
  final List<String> failures;
  final int elapsedMs;
}

class SourceDirectoryRegistry {
  SourceDirectoryRegistry({required this.executor, SourceService? service})
    : service = service ?? SourceService.shared;
  final RuleRequestExecutor executor;
  final SourceService service;
  bool supports(SourceDefinition source) =>
      directoryConfig(source.toJson()) != null;
  int priority(SourceDefinition source) => directoryPriority(source.toJson());
  List<Map<String, dynamic>> categories(SourceDefinition source) {
    if (!supports(source)) {
      throw const SourceException('UNSUPPORTED', '来源未配置目录能力');
    }
    return const [
      {'id': 'all', 'name': '全部'},
      {'id': 'chinese', 'name': '国漫'},
      {'id': 'japanese', 'name': '日漫'},
      {'id': 'movies', 'name': '动漫电影'},
    ];
  }

  Future<SourceDirectoryResult> load(
    SourceDefinition source, {
    SourceContext? context,
  }) async {
    final config = directoryConfig(source.toJson());
    if (config == null) throw const SourceException('UNSUPPORTED', '来源未配置目录能力');
    final ctx = context ?? SourceContext(timeout: const Duration(seconds: 40));
    return service.observe(source.manifest.id, 'catalog', ctx, () async {
      final watch = Stopwatch()..start();
      final base = Uri.parse(source.execution.baseUrl);
      Future<String> fetch(Uri uri) {
        final requestContext = SourceContext(
          cancelToken: ctx.cancelToken,
          sessionId: ctx.sessionId,
          providerId: source.manifest.id,
          timeout: const Duration(seconds: 12),
        );
        return executor
            .execute(
              PreparedRuleRequest(
                method: 'GET',
                url: uri.toString(),
                includeCookies: true,
                headers: {
                  if ((source.toJson()['userAgent'] as String? ?? '')
                      .isNotEmpty)
                    'user-agent': source.toJson()['userAgent'],
                  if ((source.toJson()['referer'] as String? ?? '').isNotEmpty)
                    'referer': source.toJson()['referer'],
                },
              ),
              source.execution,
              cancelToken: requestContext.cancelToken,
            )
            .timeout(
              requestContext.timeout,
              onTimeout: () {
                requestContext.cancelToken.cancel('directory deadline');
                throw const SourceException('TIMEOUT', '目录页面请求超时');
              },
            );
      }

      final homepage = await fetch(base);
      final paths = <String, Uri>{};
      for (final link in html.parse(homepage).querySelectorAll('a[href]')) {
        final label = link.text.trim();
        final group = const ['国漫', '国产动漫', '中国动漫'].contains(label)
            ? 'chinese'
            : const ['日漫', '日本动漫'].contains(label)
            ? 'japanese'
            : const ['电影', '动漫电影', '剧场版'].contains(label)
            ? 'movies'
            : null;
        if (group == null) continue;
        final uri = base.resolve(link.attributes['href']!);
        if (uri.host == base.host && ['http', 'https'].contains(uri.scheme)) {
          paths[group] = uri;
        }
      }
      List<SourceContent> parse(String text, String group) {
        final entries = <String, SourceContent>{};
        for (final anchor
            in html
                .parse(text)
                .querySelectorAll(config['entrySelector'] as String)) {
          final image = anchor.querySelector('img');
          final title = (image?.attributes['alt'] ?? anchor.text).trim();
          final href = anchor.attributes['href'];
          if (href == null) continue;
          final uri = base.resolve(href);
          if (title.isEmpty ||
              uri.host != base.host ||
              !['http', 'https'].contains(uri.scheme) ||
              !RegExp(
                config['detailPathPattern'] as String,
              ).hasMatch(uri.path)) {
            continue;
          }
          final rawCover =
              image?.attributes['data-src'] ?? image?.attributes['src'];
          entries[uri.toString()] = SourceContent(
            ref: SourceRef(
              providerId: source.manifest.id,
              rawRef: uri.toString(),
            ),
            title: title,
            coverUrl: rawCover == null
                ? null
                : base.resolve(rawCover).toString(),
            classification: SourceClassification(
              kind: 'anime',
              region: group == 'chinese'
                  ? 'CN'
                  : group == 'japanese'
                  ? 'JP'
                  : null,
              format: group == 'movies' ? 'movie' : null,
              rawCategory: group,
              evidence: 'source_directory',
            ),
          );
        }
        return entries.values.take(40).toList();
      }

      final items = parse(homepage, 'all');
      final failures = <String>[];
      await Future.wait(
        paths.entries.take(3).map((path) async {
          try {
            items.addAll(parse(await fetch(path.value), path.key));
          } catch (_) {
            ctx.checkActive();
            failures.add('${source.manifest.name}:${path.key}');
          }
        }),
      );
      if (items.isEmpty) throw const SourceException('PARSE_ERROR', '目录未识别到条目');
      return SourceDirectoryResult(
        name: source.manifest.name,
        items: items,
        failures: failures,
        elapsedMs: watch.elapsedMilliseconds,
      );
    });
  }
}
