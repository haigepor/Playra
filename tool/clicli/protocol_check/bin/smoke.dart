// Live smoke test for the pure-Dart CliCli SDK.
//
//   cd tool/clicli/protocol_check && dart run bin/smoke.dart
//
// Exercises the real service: handshake, modules, categories, search, detail,
// qualities and the full ad-gated resolve chain.
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_source.dart';

const String _videoId = '319731354307588097'; // 斗罗大陆II 绝世唐门

Future<void> main() async {
  final source = CliCliSource();
  final total = Stopwatch()..start();
  var failures = 0;

  Future<void> step<T>(String name, Future<T> Function() run) async {
    final watch = Stopwatch()..start();
    try {
      final value = await run();
      stdout.writeln('PASS ${name.padRight(16)} ${watch.elapsedMilliseconds}ms');
      if (value != null) stdout.writeln('     $value');
    } catch (error, stack) {
      failures++;
      stdout.writeln('FAIL ${name.padRight(16)} ${watch.elapsedMilliseconds}ms $error');
      if (failures <= 2) stdout.writeln(stack);
    }
  }

  await step('warmUp', () async {
    final watch = Stopwatch()..start();
    await source.warmUp();
    return 'warm ${watch.elapsedMilliseconds}ms';
  });

  await step('home', () async {
    final feed = await source.loadHome();
    final first = feed.sections.first.items.first;
    final lines = <String>[
      'sections=${feed.sections.length}',
      for (final section in feed.sections)
        '${section.title}/${section.layout.name}:${section.items.length}'
            '${section.ranked ? '(ranked)' : ''}'
            '${section.tabs.isEmpty ? '' : '(tabs:${section.tabs.join('|')})'}'
            '${section.rows == 0 ? '' : '(rows:${section.rows})'}',
    ];
    return 'banners=${feed.banners.length} '
        'firstBanner=${feed.banners.isEmpty ? '-' : feed.banners.first.title} '
        '${lines.join(' | ')}; first=${first.title} cover=${first.cover}';
  });

  await step('categories', () async {
    final categories = await source.loadCategories();
    return categories
        .take(8)
        .map((category) => '${category.name}(${category.id})')
        .join(', ');
  });

  await step('browse', () async {
    final page = await source.browse(categoryId: '319730681499283456');
    return 'total=${page.total} pages=${page.pages} got=${page.items.length} '
        'first=${page.items.isEmpty ? '-' : page.items.first.title}';
  });

  await step('search', () async {
    final page = await source.search('斗罗');
    return 'total=${page.total} got=${page.items.length} '
        'first=${page.items.isEmpty ? '-' : page.items.first.title}';
  });

  await step('detail', () async {
    final detail = await source.loadDetail(_videoId);
    final roads = detail.roads
        .map((road) => '${road.code}/${road.name}:${road.episodes.length}')
        .join(', ');
    return '${detail.title} | ${detail.year} ${detail.area} ${detail.category} '
        'score=${detail.score} roads=[$roads]';
  });

  late String roadCode;
  await step('qualities', () async {
    final detail = await source.loadDetail(_videoId);
    roadCode = detail.defaultRoad?.code ?? 'mao';
    final qualities = await source.loadQualities(
      mediaId: _videoId,
      roadCode: roadCode,
      episode: 1,
    );
    return 'road=$roadCode '
        '${qualities.map((q) => '${q.id}/${q.label}${q.vipOnly ? '(vip)' : ''}').join(', ')}';
  });

  await step('resolve', () async {
    final watch = Stopwatch()..start();
    final playback = await source.resolvePlayback(
      mediaId: _videoId,
      roadCode: roadCode.isEmpty ? 'mao' : roadCode,
      episode: 1,
    );
    final uri = Uri.tryParse(playback.url);
    return '${watch.elapsedMilliseconds}ms quality=${playback.quality} '
        'expires=${playback.expiresAt} host=${uri?.host} path=${uri?.path} '
        'p2p=${playback.p2pEnabled}';
  });

  await source.dispose();
  stdout.writeln('total ${total.elapsedMilliseconds}ms failures=$failures');
  if (failures > 0) exitCode = 1;
}
