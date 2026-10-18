import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/source/source_gateway.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

/// 真实网关验收：每条规则只解析官方返回的首条线路，不把接口成功当作出画。
Future<void> main(List<String> args) async {
  String? option(String name) {
    final index = args.indexOf(name);
    return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
  }

  final keyword = option('--keyword') ?? '吞噬星空';
  final ruleName = args.length > 2 && !args[2].startsWith('--')
      ? args[2]
      : null;
  final gateway = SourceGateway(Uri.parse(args.first));
  final service = SourceService(
    engine: RuleEngine(requestExecutor: gateway, logFailures: false),
  );
  final output = File(
    args.length > 1 ? args[1] : '.dart_tool/kazumi-live.json',
  );
  await output.parent.create(recursive: true);
  final files =
      Directory('assets/plugins')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final rows = <Map<String, dynamic>>[];
  void save() => output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'rows': rows})}\n',
    encoding: utf8,
  );
  String errorCode(Object error) => error is SourceException
      ? error.code
      : error is DioException
      ? '${error.type.name}:${error.response?.statusCode ?? ''}'
      : error.runtimeType.toString();
  var next = 0;
  Future<void> worker() async {
    while (next < files.length) {
      final source = SourceDefinition.fromJson(
        jsonDecode(files[next++].readAsStringSync(encoding: utf8)),
      );
      if (ruleName != null && source.manifest.name != ruleName) continue;
      gateway.bindSource(source.execution, source.manifest.id);
      final row = <String, dynamic>{'rule': source.manifest.name};
      rows.add(row);
      try {
        final search = await service.search(
          source,
          keyword,
          pageSize: 100,
          context: SourceContext(timeout: const Duration(seconds: 18)),
        );
        row.addAll({
          'search': 'PASS',
          'keyword': keyword,
          'results': search.items.length,
        });
        final hit =
            search.items.where((item) => item.title == keyword).firstOrNull ??
            (args.contains('--first-result') ? search.items.firstOrNull : null);
        if (hit == null) {
          row['directory'] = 'NO_EXACT_SAMPLE';
          continue;
        }
        row['title'] = hit.title;
        final lines = await service.lines(
          source,
          hit.ref,
          context: SourceContext(timeout: const Duration(seconds: 18)),
        );
        row.addAll({
          'directory': 'PASS',
          'lineCount': lines.length,
          'lineNames': lines.map((line) => line.name).toList(),
          if (args.contains('--directory-only'))
            'samples': [
              for (final line in lines)
                {
                  'line': line.name,
                  'episodes': [
                    for (final e in line.episodes.take(2))
                      {'title': e.title, 'page': e.pageUrl},
                  ],
                },
            ],
        });
        if (lines.isEmpty || lines.first.episodes.isEmpty) {
          row['parse'] = 'EMPTY_DEFAULT_LINE';
          continue;
        }
        final first = lines.first.episodes.first;
        row.addAll({
          'defaultLine': lines.first.name,
          'episode': first.title,
          'episodeCount': lines.first.episodes.length,
          'episodePage': first.pageUrl,
        });
        if (args.contains('--directory-only')) continue;
        final headers = await gateway.playbackHeaders(
          source.manifest.id,
          first.pageUrl,
          referer:
              source.toJson()['referer'] as String? ?? source.execution.baseUrl,
          userAgent: source.toJson()['userAgent'] as String?,
        );
        try {
          final media = await gateway.browser('parse', {
            'url': first.pageUrl,
            'headers': headers,
            'useLegacyParser': source.toJson()['useLegacyParser'] == true,
          });
          row['parse'] = media['url'] is String ? 'PASS' : 'NO_MEDIA';
          if (media['url'] is String) {
            final response = await gateway.client.get<List<int>>(
              gateway.base
                  .resolve('/api/proxy')
                  .replace(
                    queryParameters: {
                      'url': media['url'] as String,
                      'headers': base64Url.encode(
                        utf8.encode(
                          jsonEncode({
                            ...headers,
                            if (media['headers'] is Map)
                              ...Map<String, dynamic>.from(
                                media['headers'] as Map,
                              ),
                          }),
                        ),
                      ),
                    },
                  )
                  .toString(),
              options: Options(
                responseType: ResponseType.bytes,
                headers: {'Range': 'bytes=0-4095'},
              ),
            );
            row['mediaHttp'] = response.statusCode;
            row['mediaType'] = response.headers.value('content-type');
          }
        } catch (error) {
          // 媒体 HTTP 失败不能覆盖已成功的解析结论。
          row[row['parse'] == 'PASS' ? 'mediaError' : 'parse'] = errorCode(
            error,
          );
        }
      } catch (error) {
        row['error'] = errorCode(error);
      } finally {
        save();
        stdout.writeln(jsonEncode(row));
      }
    }
  }

  await Future.wait([worker(), worker()]);
  gateway.dispose();
  stdout.writeln('CHECKED ${rows.length} official rules');
}
