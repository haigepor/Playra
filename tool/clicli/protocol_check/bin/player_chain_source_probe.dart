// Source-level resolve timing: measures what the player page actually waits
// for (CliCliSource.resolvePlayback), including the options cache, the
// device-pass shortcut and the next-episode prefetch.
//
//   cd tool/clicli/protocol_check && dart run bin/player_chain_source_probe.dart
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_models.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_source.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_api.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';

Future<void> main() async {
  final client = CliCliClient();
  final api = CliCliApi(client);
  final source = CliCliSource(client: client, api: api);

  final modules = await api.modules(page: 1);
  final feed = homeFeedFromModules(modules);
  final first = feed.sections.first.items.first;
  final episodes = await api.episodes(first.key.mediaId);
  final videos = await api.videoDetail(first.key.mediaId);
  final detail = mediaDetailFromVideo(
    Map<String, dynamic>.from(videos['video'] as Map),
    episodes: episodes,
  );
  final road = detail.defaultRoad!;
  final episode = road.episodes.first.number;
  stdout.writeln(
    'target: ${detail.title} id=${detail.key.mediaId} road=${road.code} ep=$episode',
  );

  // Cold: what the first tap on 播放 waits for (session already warm from
  // the home page in the real app, so this includes request cost only).
  var watch = Stopwatch()..start();
  final firstResolve = await source.resolvePlayback(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: episode,
  );
  stdout.writeln(
    'resolve #1 (cold): ${watch.elapsedMilliseconds}ms url=${firstResolve.url.isEmpty ? "EMPTY" : "ok"}',
  );

  // Warm: same episode again -> options cached, device-pass shortcut.
  watch = Stopwatch()..start();
  final secondResolve = await source.resolvePlayback(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: episode,
  );
  stdout.writeln(
    'resolve #2 (cached options): ${watch.elapsedMilliseconds}ms url=${secondResolve.url.isEmpty ? "EMPTY" : "ok"}',
  );

  // Next episode: prefetch, then resolve like an episode switch does.
  final next = road.episodes.length > 1 ? road.episodes[1].number : episode;
  watch = Stopwatch()..start();
  await source.prefetchPlayback(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: next,
  );
  final prefetchMs = watch.elapsedMilliseconds;
  watch = Stopwatch()..start();
  final nextResolve = await source.resolvePlayback(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: next,
  );
  stdout.writeln(
    'episode switch: prefetch=${prefetchMs}ms resolve=${watch.elapsedMilliseconds}ms '
    'url=${nextResolve.url.isEmpty ? "EMPTY" : "ok"}',
  );

  // Cache effect on the quality list itself (fresh source => cold cache).
  final fresh = CliCliSource(client: client, api: api);
  watch = Stopwatch()..start();
  await fresh.loadQualities(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: next,
  );
  final coldQualities = watch.elapsedMilliseconds;
  watch = Stopwatch()..start();
  await fresh.loadQualities(
    mediaId: detail.key.mediaId,
    roadCode: road.code,
    episode: next,
  );
  stdout.writeln(
    'qualities: cold=${coldQualities}ms cached=${watch.elapsedMilliseconds}ms',
  );

  await source.dispose();
}
