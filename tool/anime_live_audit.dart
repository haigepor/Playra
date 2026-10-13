import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/source/source_gateway.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

/// 使用现有规则引擎和同源网关；不改规则，不自动完成验证码。
Future<void> main() async {
  final gateway = SourceGateway(Uri.parse('http://127.0.0.1:8940'));
  final service = SourceService(
    engine: RuleEngine(requestExecutor: gateway, logFailures: false),
  );
  final rows = <Map<String, dynamic>>[];
  final files = Directory('assets/plugins').listSync().whereType<File>()
      .where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final report = File('.dart_tool/interface-playback-audit-20261012/anime-live.json');
  void save() => report.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'keyword': '吞噬星空', 'rows': rows})}\n',
    encoding: utf8,
  );
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < files.length) {
      final file = files[cursor++];
      final source = SourceDefinition.fromJson(
        jsonDecode(file.readAsStringSync(encoding: utf8)) as Map<String, dynamic>,
        origin: 'bundled',
      );
      gateway.bindSource(source.execution, source.manifest.id);
      final row = <String, dynamic>{'rule': source.manifest.name, 'lines': []};
      rows.add(row);
      final watch = Stopwatch()..start();
      try {
        final result = await service.search(source, '吞噬星空',
          context: SourceContext(timeout: const Duration(seconds: 22)));
        row.addAll({'search': 'PASS', 'searchMs': watch.elapsedMilliseconds, 'results': result.items.length});
        final matches = result.items.where((v) => v.title.contains('吞噬星空')).toList();
        if (matches.isEmpty) {
          row['episodes'] = 'NO_MATCH';
          save();
          continue;
        }
        watch.reset();
        final lines = await service.lines(source, matches.first.ref,
          context: SourceContext(timeout: const Duration(seconds: 22)));
        row.addAll({'episodes': 'PASS', 'episodesMs': watch.elapsedMilliseconds});
        for (final line in lines) {
          final item = <String, dynamic>{'name': line.name, 'episodes': line.episodes.length};
          (row['lines'] as List).add(item);
          if (line.episodes.isEmpty) { item['resolve'] = 'EMPTY'; continue; }
          watch.reset();
          try {
            final episode = line.episodes.first;
            final headers = await gateway.playbackHeaders(source.manifest.id, episode.pageUrl,
              referer: source.execution.baseUrl);
            final media = await gateway.browser('parse', {'url': episode.pageUrl,
              'headers': headers, 'legacy': source.toJson()['useLegacyParser'] == true});
            item.addAll({'resolve': media['url'] is String ? 'PASS' : 'NO_MEDIA',
              'resolveMs': watch.elapsedMilliseconds});
            if (media['url'] is String) {
              final response = await gateway.client.get<List<int>>(
                gateway.base.resolve('/api/proxy').replace(queryParameters: {
                  'url': media['url'] as String,
                  'headers': base64Url.encode(utf8.encode(jsonEncode(headers))),
                }).toString(),
                options: Options(responseType: ResponseType.bytes, headers: {'Range': 'bytes=0-4095'}),
              );
              final data = response.data ?? [];
              item['media'] = {'http': response.statusCode,
                'mime': response.headers.value('content-type'),
                'isHls': utf8.decode(data.take(8).toList(), allowMalformed: true).startsWith('#EXTM3U'),
                'isMp4': data.length >= 8 && ascii.decode(data.sublist(4, 8), allowInvalid: true) == 'ftyp'};
            }
          } catch (error) {
            item.addAll({'resolve': 'FAIL', 'error': error is SourceException ? error.code : error.runtimeType.toString(),
              'resolveMs': watch.elapsedMilliseconds});
          }
          save();
        }
      } catch (error) {
        row.addAll({'error': error is SourceException ? error.code : error.runtimeType.toString(),
          'elapsedMs': watch.elapsedMilliseconds});
      }
      save();
      stdout.writeln(jsonEncode(row));
    }
  }
  await Future.wait([worker(), worker()]);
  gateway.client.close(force: true);
  stdout.writeln('CHECKED ${rows.length} rules');
}
