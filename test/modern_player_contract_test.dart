import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/pages/video/video_fullscreen_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/presentation/modern/player/player_episodes.dart';
import 'package:kazumi/presentation/modern/player/player_theme.dart';

void main() {
  testWidgets(
    'player touch targets remain 48dp with compact desktop base theme',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(visualDensity: VisualDensity.compact),
          home: ModernPlayerScope(
            child: Scaffold(
              body: Column(
                children: [
                  TextButton(onPressed: () {}, child: const Text('来源')),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(IconButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'presentation remount can enter fullscreen and back exits it first',
    (tester) async {
      final applied = <bool>[];
      final fullscreen = VideoFullscreenController(
        applyFullscreen: (value) async {
          applied.add(value);
        },
      );
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: Text('播放页'));
            },
          ),
        ),
      );
      fullscreen.attach(ModalRoute.of(pageContext)!);
      await fullscreen.setFullscreen(true);
      expect(fullscreen.isFullscreen, isTrue);
      await fullscreen.detach();
      fullscreen.attach(ModalRoute.of(pageContext)!);
      await fullscreen.setFullscreen(true);
      expect(fullscreen.isFullscreen, isTrue);
      await Navigator.of(pageContext).maybePop();
      await tester.pumpAndSettle();
      expect(fullscreen.isFullscreen, isFalse);
      expect(find.text('播放页'), findsOneWidget);
      expect(applied, [true, false, true, false]);
      await fullscreen.close();
      await fullscreen.close();
      expect(applied.length, 5);
    },
  );
  final item = BangumiItem.fromJson({
    'id': 42,
    'name': '测试作品',
    'rating': {},
    'images': {},
  });
  OnlineVideoPlaybackArgs args(List<String> urls, {String source = '站点 A'}) =>
      OnlineVideoPlaybackArgs(
        bangumiItem: item,
        plugin: Plugin.fromJson({'name': source}),
        title: '测试作品',
        src: '/work/42',
        roads: [
          Road(
            name: '正片',
            data: urls,
            identifier: List.generate(urls.length, (i) => '第${i + 1}集'),
          ),
        ],
      );
  History history() => History(
    item,
    2,
    '站点 A',
    DateTime(2026),
    '/work/42',
    '第2集',
    episodePageUrl: '/ep/2',
  )..progresses[2] = Progress(2, 0, 65000);
  test('resume follows URL after reordering, never old list position', () {
    final result = verifiedResume(args(['/ep/2', '/ep/1']), [history()]);
    expect(result?.selection.episode, 1);
    expect(result?.offset, 65);
  });
  test('cross-source, missing and ambiguous URLs require explicit choice', () {
    expect(
      verifiedResume(args(['/ep/1', '/ep/2'], source: '站点 B'), [history()]),
      isNull,
    );
    expect(verifiedResume(args(['/ep/new1', '/ep/new2']), [history()]), isNull);
    expect(verifiedResume(args(['/ep/2', '/ep/2']), [history()]), isNull);
    expect(
      verifiedResume(args(['/ep/1', '/ep/2']), [
        history()..episodePageUrl = '',
      ]),
      isNull,
    );
  });
  final episodes = [
    EpisodeInfo(id: 103, episode: 3, type: 0, name: 'A journey', nameCn: '旅途'),
    EpisodeInfo(id: 901, episode: 1, type: 1, name: 'Special', nameCn: '特别篇'),
  ];
  test('discussion uses true ID and refuses OVA number fallback', () {
    expect(matchDiscussionEpisode('第03集', episodes)?.id, 103);
    expect(matchDiscussionEpisode('旅途', episodes)?.id, 103);
    expect(matchDiscussionEpisode('特别篇', episodes)?.id, 901);
    expect(matchDiscussionEpisode('OVA 03', episodes), isNull);
    expect(matchDiscussionEpisode('预告03', episodes), isNull);
    expect(matchDiscussionEpisode('3.5', episodes), isNull);
    expect(
      matchDiscussionEpisode('第03集', [
        ...episodes,
        EpisodeInfo(id: 999, episode: 3, type: 0, name: '', nameCn: ''),
      ]),
      isNull,
    );
  });
  testWidgets('reverse and segment preserve original episode identity', (
    tester,
  ) async {
    final roads = [
      Road(
        name: '真实线路',
        data: List.generate(125, (i) => '/$i'),
        identifier: List.generate(
          125,
          (i) => '第${(i + 1).toString().padLeft(3, '0')}集',
        ),
      ),
    ];
    VideoEpisodeSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('打开'),
              onPressed: () async {
                result = await showModernPlayerSheet<VideoEpisodeSelection>(
                  context,
                  PlayerEpisodesSheet(
                    roads: roads,
                    selected: const VideoEpisodeSelection(episode: 76, road: 0),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('降序').hitTestable().evaluate().isEmpty
          ? find.text('升序')
          : find.text('降序'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('101–125'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第125集'));
    await tester.pumpAndSettle();
    expect(result, const VideoEpisodeSelection(episode: 125, road: 0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('320px and large text keep sheet controls and lazy grid usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: PlayerEpisodesSheet(
            roads: [
              Road(
                name: '真实线路与特别篇',
                data: List.generate(200, (i) => '/$i'),
                identifier: List.generate(
                  200,
                  (i) => i == 0 ? 'OVA 完整特别篇' : '第$i集',
                ),
              ),
            ],
            selected: const VideoEpisodeSelection(episode: 1, road: 0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('OVA 完整特别篇'), findsOneWidget);
    expect(find.byType(PlayerEpisodeButton).evaluate().length, lessThan(50));
    expect(
      tester.getSize(find.widgetWithText(TextButton, '当前集')).height,
      greaterThanOrEqualTo(48),
    );
  });
}
