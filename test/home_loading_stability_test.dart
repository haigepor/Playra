import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/presentation/modern/player/sdk_rank_section.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';
import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'modern_home_controller_test.dart' show item;
import 'sdk_rank_controller_test.dart' as ranks;

Map<String, dynamic> page(String category, String title, String kind) => {
  'data': {
    'videos': List.generate(
      6,
      (i) => {
        'id': '$category$i',
        'title': '$title $i',
        'categoryId': category,
        'categoryName': kind,
        'year': '2025',
      },
    ),
    'pageInfo': {'total': 6},
  },
};

Future<void> paint(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets(
    'a failed late source keeps existing rank coordinates and offers retry',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final lumina = LuminaService(request: (_, _, _) => pending.future);
      final mio = MioMediaService(
        request: (_, _, _) async => ranks.media('42', ['201']),
      );
      final rank = SdkRankController(lumina: lumina, mio: mio);
      addTearDown(rank.dispose);
      addTearDown(lumina.dispose);
      addTearDown(mio.dispose);
      final load = rank.load(luminaChannelId: '1', mioCategoryIds: ['42']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SdkRankSection(controller: rank, onDetails: (_) {}),
          ),
        ),
      );
      await paint(tester);
      final movie = find.byKey(const ValueKey('sdk-rank-miomedia:201'));
      final before = tester.getTopLeft(movie);
      pending.completeError(Exception('offline'));
      await load;
      await paint(tester);
      expect(tester.getTopLeft(movie), before);
      expect(find.byTooltip('部分来源暂不可用，显示已有推荐；点击重试'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'primary waits for actual SDK timeout, fallback stays stable, explicit refresh adopts Lumina',
    (tester) async {
      final catalog = Completer<Map<String, dynamic>>();
      var retry = false;
      final service = LuminaService(
        request: (op, _, _) async => switch (op) {
          'channels' => {
            'data': {
              'channels': [
                {'id': '1', 'name': '日漫'},
              ],
            },
          },
          'banners' => {
            'data': {'banners': []},
          },
          _ => retry ? Future.value(page('1', 'Lumina', '日漫')) : catalog.future,
        },
      );
      final anime = LuminaHomeController(service);
      final home = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => List.generate(8, item),
      );
      addTearDown(home.dispose);
      addTearDown(anime.dispose);
      addTearDown(service.dispose);
      await home.refresh();
      final pending = anime.bootstrap();
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeView(
            controller: home,
            anime: anime,
            onAnimeDetails: (_) {},
            onSearch: () {},
            onCalendar: () {},
            onBrowse: (_) {},
            onHistory: () {},
            onToggleTheme: () {},
            onDetails: (_) {},
            onResume: (_) {},
          ),
        ),
      );
      await paint(tester);
      final main = find.byKey(const ValueKey('home-primary-recommendations'));
      Finder title(String text) =>
          find.descendant(of: main, matching: find.text(text));
      expect(title('番剧 0'), findsNothing);
      await tester.pump(const Duration(seconds: 8));
      expect(title('番剧 0'), findsNothing);
      catalog.completeError(const SourceException('TIMEOUT', 'test timeout'));
      await pending;
      await paint(tester);
      expect(title('番剧 0'), findsOneWidget);
      retry = true;
      await anime.bootstrap(force: true);
      await paint(tester);
      expect(title('番剧 0'), findsOneWidget);
      expect(title('Lumina 0'), findsNothing);
      await home.refresh();
      await paint(tester);
      expect(title('Lumina 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Lumina first page supplies rank head, force refresh still requests fresh data',
    () async {
      var calls = 0;
      final service = LuminaService(
        request: (_, _, _) async {
          calls++;
          return page('1', 'Lumina', '日漫');
        },
      );
      addTearDown(service.dispose);
      final home = await service.catalog('1');
      final rank = await service.catalog('1', size: 10);
      expect(
        rank.items.map((item) => item.id),
        home.items.map((item) => item.id),
      );
      expect(calls, 1);
      await service.catalog('1', size: 10, refresh: true);
      expect(calls, 2);
    },
  );

  testWidgets(
    'late movie and series fill reserved slots without moving visible anime',
    (tester) async {
      final movie = Completer<Map<String, dynamic>>();
      final series = Completer<Map<String, dynamic>>();
      final source = MioMediaService(
        request: (_, data, _) =>
            data['categoryId'] == '42' ? movie.future : series.future,
      );
      final media = MioHomeController(source);
      media.categoryIds.addAll({MioKind.movie: '42', MioKind.series: '43'});
      final home = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => List.generate(8, item),
      );
      addTearDown(home.dispose);
      addTearDown(media.dispose);
      addTearDown(source.dispose);
      await home.refresh();
      final mp = media.load(MioKind.movie, reset: true);
      final sp = media.load(MioKind.series, reset: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeView(
            controller: home,
            media: media,
            onMediaDetails: (_) {},
            onSearch: () {},
            onCalendar: () {},
            onBrowse: (_) {},
            onHistory: () {},
            onToggleTheme: () {},
            onDetails: (_) {},
            onResume: (_) {},
          ),
        ),
      );
      await paint(tester);
      final main = find.byKey(const ValueKey('home-primary-recommendations'));
      Finder title(String name) =>
          find.descendant(of: main, matching: find.text(name));
      final before = tester.getTopLeft(title('番剧 1'));
      final height = tester.getSize(main).height;
      movie.complete(page('42', '电影', '电影大全'));
      await mp;
      await paint(tester);
      expect(tester.getTopLeft(title('番剧 1')), before);
      expect(tester.getSize(main).height, height);
      series.complete(page('43', '剧集', '剧集大全'));
      await sp;
      await paint(tester);
      expect(tester.getTopLeft(title('番剧 1')), before);
      expect(title('电影 0'), findsOneWidget);
      expect(title('剧集 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Lumina background channel cannot replace current recommendations',
    (tester) async {
      final background = Completer<Map<String, dynamic>>();
      final source = LuminaService(
        request: (op, data, _) async {
          if (op == 'channels')
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '日漫'},
                  {'id': '2', 'name': '国漫'},
                ],
              },
            };
          if (op == 'banners')
            return {
              'data': {'banners': []},
            };
          return data['channelId'] == '1'
              ? page('1', '日漫', '日漫')
              : background.future;
        },
      );
      final anime = LuminaHomeController(source);
      final home = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => List.generate(8, item),
      );
      addTearDown(home.dispose);
      addTearDown(anime.dispose);
      addTearDown(source.dispose);
      await home.refresh();
      await anime.bootstrap();
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeView(
            controller: home,
            anime: anime,
            onAnimeDetails: (_) {},
            onSearch: () {},
            onCalendar: () {},
            onBrowse: (_) {},
            onHistory: () {},
            onToggleTheme: () {},
            onDetails: (_) {},
            onResume: (_) {},
          ),
        ),
      );
      await paint(tester);
      final main = find.byKey(const ValueKey('home-primary-recommendations'));
      List<String?> titles() => tester
          .widgetList<Text>(
            find.descendant(of: main, matching: find.byType(Text)),
          )
          .map((v) => v.data)
          .where(
            (v) => v?.startsWith('日漫') == true || v?.startsWith('国漫') == true,
          )
          .toList();
      final before = titles();
      background.complete(page('2', '国漫', '国漫'));
      await paint(tester);
      expect(titles(), before);
      await tester.tap(find.byKey(const ValueKey('home-shuffle-featured')));
      await paint(tester);
      expect(titles(), isNot(before));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('late primary rank cannot move an already visible movie poster', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final lumina = LuminaService(request: (_, _, _) => pending.future);
    final mio = MioMediaService(
      request: (_, _, _) async => ranks.media('42', ['201']),
    );
    final rank = SdkRankController(lumina: lumina, mio: mio);
    addTearDown(rank.dispose);
    addTearDown(lumina.dispose);
    addTearDown(mio.dispose);
    final load = rank.load(luminaChannelId: '1', mioCategoryIds: ['42']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SdkRankSection(controller: rank, onDetails: (_) {}),
        ),
      ),
    );
    await paint(tester);
    final movie = find.byKey(const ValueKey('sdk-rank-miomedia:201'));
    final before = tester.getTopLeft(movie);
    pending.complete(ranks.anime(['101']));
    await load;
    await paint(tester);
    expect(tester.getTopLeft(movie), before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('movie catalog starts before a slow searchConfig finishes', () async {
    final config = Completer<Map<String, dynamic>>();
    var movieRequested = false;
    final source = MioMediaService(
      request: (op, data, _) async {
        if (op == 'searchConfig') return config.future;
        if (op == 'catalog' && data['categoryId'] == null)
          return page('42', '电影', '电影大全');
        if (op == 'catalog') {
          movieRequested = true;
          return page('42', '电影', '电影大全');
        }
        return {
          'data': {'videos': []},
        };
      },
    );
    final media = MioHomeController(source);
    addTearDown(media.dispose);
    addTearDown(source.dispose);
    final load = media.bootstrap();
    await Future<void>.delayed(Duration.zero);
    final startedBeforeConfig = movieRequested;
    config.complete({'data': {}});
    await load;
    expect(startedBeforeConfig, isTrue);
  });
}
