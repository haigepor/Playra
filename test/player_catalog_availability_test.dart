import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/presentation/modern/player/player_episodes.dart';

void main() {
  testWidgets('metadata count is replaced by the active source count', (
    tester,
  ) async {
    var opens = 0;
    Widget header({required int count, required bool verified}) => MaterialApp(
      home: Scaffold(
        body: PlayerEpisodesHeader(
          count: count,
          sourceVerified: verified,
          onShowAll: () => opens++,
        ),
      ),
    );
    await tester.pumpWidget(header(count: 12, verified: false));
    expect(find.text('资料目录'), findsOneWidget);
    expect(find.text('目录 12 集 ›'), findsOneWidget);
    expect(find.textContaining('当前线路'), findsNothing);
    await tester.tap(find.text('目录 12 集 ›'));
    expect(opens, 1);

    await tester.pumpWidget(header(count: 2, verified: true));
    expect(find.text('选集'), findsOneWidget);
    expect(find.text('当前线路 2 集 · 全部 ›'), findsOneWidget);
    expect(find.textContaining('12'), findsNothing);
    expect(find.text('实际可播放集数以匹配来源为准'), findsNothing);
    await tester.tap(find.text('当前线路 2 集 · 全部 ›'));
    expect(opens, 2);
  });

  testWidgets('catalog and source labels fit narrow screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final verified in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: PlayerEpisodesHeader(
                count: 1180,
                sourceVerified: verified,
                onShowAll: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('metadata catalog never claims that all episodes are playable', (
    tester,
  ) async {
    final episodes = List.generate(
      12,
      (i) =>
          EpisodeInfo(id: i + 1, episode: i + 1, type: 0, name: '', nameCn: ''),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayerCatalogEpisodesSheet(episodes: episodes)),
      ),
    );
    expect(find.text('资料目录'), findsOneWidget);
    expect(find.text('实际可播放集数以匹配来源为准'), findsOneWidget);
    expect(find.text('全部剧集'), findsNothing);
    expect(find.text('第12集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
