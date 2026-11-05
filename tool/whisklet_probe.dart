// 纯 Dart 探针：复现 Whisklet 播放解析全链路（search → detail → 直链/解析），
// 不依赖 Flutter。运行：dart run tool/whisklet_probe.dart [关键词]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kazumi/services/source/whisklet/whisklet_codec.dart';

const familyFull = {
  'BBA': 800,
  'co': 88,
  'NBY': 288,
  'zijianm3u8': 172,
  'rose': 232,
  'youku': 144,
  'qq': 144,
};

final client = http.Client();
final codec = WhiskletCodec();

Future<Map<String, dynamic>> call(
  String method,
  Map<String, dynamic> data,
) async {
  final payload = codec.encrypt({
    'method': method,
    'data': data,
    'csrf': DateTime.now().millisecondsSinceEpoch,
  });
  final response = await client
      .post(WhiskletProfile.endpoint, body: payload, headers: WhiskletProfile.headers)
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw 'HTTP ${response.statusCode}';
  }
  final result = codec.decode(utf8.decode(response.bodyBytes), method);
  if (result['code'] != 1) {
    throw 'BUSINESS_REJECTED code=${result['code']} msg=${result['msg']}';
  }
  return result;
}

Future<void> main(List<String> args) async {
  final keyword = args.isNotEmpty ? args.join(' ') : '天降福星';
  stdout.writeln('== search "$keyword"');
  final searched = await call('search', {'text': keyword, 'pg': 1, 'token': ''});
  final works = [
    for (final row in (searched['data'] as List? ?? []))
      if (row is Map &&
          '${row['vod_name']}'.contains(keyword) &&
          (row['vod_id'] is int)) row,
  ];
  if (works.isEmpty) {
    stdout.writeln('search rows=${(searched['data'] as List?)?.length} 无匹配');
    return;
  }
  final work = works.first;
  stdout.writeln(
    'work id=${work['vod_id']} name=${work['vod_name']} remarks=${work['vod_remarks']}',
  );
  final id = work['vod_id'] as int;

  stdout.writeln('== detail $id');
  final detail = await call('detail', {'id': id});
  final info = (detail['data'] as Map)['vod_info'] as Map;
  final rows = info['vod_url_with_player'];
  if (rows is! List) {
    stdout.writeln('vod_url_with_player 缺失: ${info.keys.toList()}');
    return;
  }
  for (final row in rows.whereType<Map>()) {
    final code = '${row['code']}';
    final name = '${row['name']}';
    final parseApi = '${row['parse_api'] ?? ''}';
    final table = '${row['url'] ?? ''}';
    final episodes = <String, String>{};
    for (final entry in table.split('#')) {
      final split = entry.indexOf(r'$');
      if (split <= 0 || split == entry.length - 1) continue;
      episodes[entry.substring(0, split)] = entry.substring(split + 1);
    }
    if (episodes.isEmpty) continue;
    stdout.writeln(
      '-- line code=$code name=$name parseApi='
      '${parseApi.isEmpty ? '(直链)' : parseApi} episodes=${episodes.length}',
    );
    final matches = episodes.entries
        .where((e) => e.key.contains('08'))
        .toList();
    final pick = matches.isNotEmpty ? matches.first : episodes.entries.first;
    stdout.writeln(
      '   probe ${pick.key} token=${pick.value.length}字符 '
      'head=${pick.value.substring(0, pick.value.length > 60 ? 60 : pick.value.length)}',
    );
    await resolveAndTest(code, parseApi, pick.value);
  }
  client.close();
}

Future<void> resolveAndTest(
  String code,
  String parseApi,
  String token,
) async {
  try {
    final url = parseApi.isEmpty
        ? token
        : await viaParser(code, parseApi, token);
    if (url == null) {
      stdout.writeln('   resolve=UPSTREAM_LIMIT（解析后端配额打满，无直链）');
      return;
    }
    stdout.writeln('   resolve=OK url=$url');
    final head = Uri.tryParse(url);
    if (head == null) return;
    final response = await http
        .get(head)
        .timeout(const Duration(seconds: 15));
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    stdout.writeln(
      '   open code=${response.statusCode} len=${response.contentLength ?? body.length} '
      'head=${body.substring(0, body.length > 80 ? 80 : body.length).replaceAll('\n', ' ')}',
    );
  } catch (error) {
    stdout.writeln('   resolve/open FAILED: $error');
  }
}

Future<String?> viaParser(String code, String parseApi, String token) async {
  if (parseApi.contains('/ajiami/')) {
    final full = familyFull[code];
    if (full == null) throw '未知播放源代号 $code';
    var best = '';
    for (var attempt = 1; attempt <= 25; attempt++) {
      final result = await call('secret_parse_api_url', {
        'url': token,
        'player_code': code,
        'token': '',
      });
      final value = result['data'];
      if (value is String && value.length > best.length) best = value;
      if (best.length >= full) break;
      if (attempt < 25) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    stdout.writeln(
      '   param rounds done len=${best.length}/$full head='
      '${best.substring(0, best.length > 60 ? 60 : best.length)}',
    );
    if (best.length < full) throw 'PARAM_INCOMPLETE ${best.length}/$full';
    return await viaGet(parseApi.split('?url=')[0], '?url=', best);
  }
  return await viaGet(parseApi, '', token);
}

Future<String?> viaGet(String base, String joiner, String value) async {
  final endpoint = Uri.parse('$base$joiner$value');
  stdout.writeln('   parse GET $endpoint');
  final response = await client.get(endpoint).timeout(const Duration(seconds: 15));
  stdout.writeln('   parse code=${response.statusCode} body=${response.body.length}字符');
  if (response.statusCode != 200) {
    throw 'PARSER HTTP ${response.statusCode}';
  }
  final payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
  final status = payload['code'];
  if (status == 403) return null;
  if (status != 200 || payload['url'] is! String) {
    throw 'PARSER code=$status body=${response.body.substring(0, response.body.length > 120 ? 120 : response.body.length)}';
  }
  return payload['url'] as String;
}
