// Shape probe for read-only endpoints not yet wrapped by CliCliApi.
// Prints top-level keys / list lengths so home-page regions can be planned
// against real payloads instead of guesses.
//
//   cd tool/clicli/protocol_check && dart run bin/home_probe.dart
import 'dart:convert';
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_config.dart';

const String _vid = '319731354307588097';

Future<void> main() async {
  final client = CliCliClient();

  Future<void> probe(
    String label,
    String path,
    Map<String, dynamic> body,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final data = await client.callData(path, body);
      stdout.writeln('PASS ${label.padRight(18)} ${watch.elapsedMilliseconds}ms '
          '${_summary(data)}');
    } catch (error) {
      stdout.writeln('FAIL ${label.padRight(18)} ${watch.elapsedMilliseconds}ms $error');
    }
  }

  const p = CliCliConfig.apiPrefix;
  await probe('banner/list', '$p/banner/list', {'categoryId': ''});
  await probe('searchConfig', '$p/video/searchConfig', <String, dynamic>{});
  await probe('searchSuggest', '$p/video/searchSuggest', {
    'keyword': '斗罗',
    'pageIndex': 1,
    'pageSize': 5,
  });
  await probe('schedule/calendar', '$p/schedule/calendar', {
    'pageIndex': 1,
    'pageSize': 10,
    'playDate': '2026-11-14',
  });
  await probe('notice/popup/list', '$p/notice/popup/list', <String, dynamic>{});
  await probe('notice/unreadCount', '$p/notice/unreadCount', <String, dynamic>{});
  await probe('guide/listActive', '$p/guide/listActive', <String, dynamic>{});
  await probe('splash/active', '$p/splash/active', <String, dynamic>{});
  await probe('engagement-counts', '$p/video/engagement-counts', {'videoId': _vid});
  await probe('filter/dimensions', '$p/filter/dimensions', {
    'categoryId': '319730681499283456',
  });
  await probe('modules', '$p/video/modules', {
    'categoryId': '',
    'pageIndex': 1,
    'pageSize': 20,
  });

  client.close();
}

String _summary(Object? value, [int depth = 0]) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    if (depth >= 2) return '{${keys.take(8).join(',')}}';
    return '{${keys.map((key) => '$key: ${_summary(value[key], depth + 1)}').join(', ')}}';
  }
  if (value is List) {
    if (value.isEmpty) return '[]';
    if (depth >= 2) return '[${value.length}]';
    return '[${value.length}× ${_summary(value.first, depth + 1)}]';
  }
  if (value is String) {
    final text = value.replaceAll('\n', ' ');
    return text.length <= 30 ? jsonEncode(text) : '"${text.substring(0, 30)}…"';
  }
  return '$value';
}
