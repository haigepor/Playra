// Detail probe: calls video/detail for the first N home items and reports
// which ids succeed, so per-title gateway errors are distinguishable from
// client bugs.
//
//   cd tool/clicli/protocol_check && dart run bin/detail_probe.dart
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_api.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_models.dart';

Future<void> main() async {
  final client = CliCliClient();
  final api = CliCliApi(client);
  final modules = await api.modules();
  final feed = homeFeedFromModules(modules);
  final items = feed.sections.first.items.take(5).toList();
  for (final item in items) {
    final watch = Stopwatch()..start();
    try {
      final data = await api.videoDetail(item.key.mediaId);
      final video = data['video'];
      final title = video is Map ? video['title'] : '?';
      final detailMs = watch.elapsedMilliseconds;
      final episodes = await api.episodes(item.key.mediaId);
      stdout.writeln(
        'PASS ${item.title} (${item.key.mediaId}) detail=${detailMs}ms '
        'episodes=${episodes.length} total=${watch.elapsedMilliseconds}ms -> $title',
      );
    } catch (error) {
      stdout.writeln(
        'FAIL ${item.title} (${item.key.mediaId}) ${watch.elapsedMilliseconds}ms $error',
      );
    }
  }
  client.close();
}
