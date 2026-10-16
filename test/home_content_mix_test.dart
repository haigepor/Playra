import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/presentation/modern/widgets/modern_feature_carousel.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'modern_home_controller_test.dart' show item;

Map<String, dynamic> _video(
  String id,
  String category,
  String categoryName,
  String title,
) => {
  'id': id,
  'title': title,
  'categoryId': category,
  'categoryName': categoryName,
  'year': '2025',
};

Future<void> _mount(
  WidgetTester tester,
  ModernHomeController home,
  MioHomeController media, {
  ValueChanged<MioVideo>? onDetails,
}) => tester.pumpWidget(
  MaterialApp(
    home: ModernHomeView(
      controller: home,
      media: media,
      onMediaDetails: onDetails ?? (_) {},
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

void main() {
  for (final feed in [HomeFeed.recommended, HomeFeed.popular]) {
    testWidgets(
      '${feed.name} main recommendations retain anime and verified movie/series slots',
      (tester) async {
        final source = MioMediaService(
          request: (operation, payload, cancel) async => {
            'data': {
              'videos': [
                if (payload['categoryId'] == '42')
                  _video('420', '42', '电影大全', '真实电影'),
                if (payload['categoryId'] == '43')
                  _video('430', '43', '剧集大全', '真实剧集'),
              ],
              'pageinfo': {'total': 1},
            },
          },
        );
        final media = MioHomeController(source);
        media.categoryIds.addAll({MioKind.movie: '42', MioKind.series: '43'});
        await media.load(MioKind.movie, reset: true);
        await media.load(MioKind.series, reset: true);
        final home = ModernHomeController(
          readHistory: () => [],
          loadFeed: (_, _) async => List.generate(8, item),
        );
        addTearDown(home.dispose);
        addTearDown(media.dispose);
        addTearDown(source.dispose);
        await home.refresh();
        if (feed != HomeFeed.recommended) await home.selectFeed(feed);
        String? opened;
        await _mount(
          tester,
          home,
          media,
          onDetails: (video) => opened = video.id,
        );
        await tester.pumpAndSettle();
        if (feed == HomeFeed.recommended) {
          final main = find.byKey(
            const ValueKey('home-primary-recommendations'),
          );
          expect(
            find.descendant(of: main, matching: find.text('真实电影')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: main, matching: find.text('真实剧集')),
            findsOneWidget,
          );
          await tester.tap(
            find.descendant(of: main, matching: find.text('真实电影')),
          );
          expect(opened, '420');
        } else {
          final hero = tester.widget<ModernFeatureCarousel>(
            find.byKey(const ValueKey('anime-feature-popular')),
          );
          expect(
            hero.entries.map((entry) => entry.id),
            containsAll(['miomedia:420', 'miomedia:430']),
          );
          expect(
            hero.entries.any((entry) => !entry.id.startsWith('miomedia:')),
            isTrue,
          );
          hero.entries
              .firstWhere((entry) => entry.id == 'miomedia:430')
              .onTap();
          expect(opened, '430');
        }
        await home.selectFeed(HomeFeed.anime);
        await tester.pumpAndSettle();
        final animeHero = tester.widget<ModernFeatureCarousel>(
          find.byKey(const ValueKey('anime-feature-anime')),
        );
        expect(
          animeHero.entries.any((entry) => entry.id.startsWith('miomedia:')),
          isFalse,
        );
      },
    );
  }

  testWidgets(
    'late category catalog updates the primary mix while unclassified global records are excluded',
    (tester) async {
      final catalog = Completer<Map<String, dynamic>>();
      final service = MioMediaService(
        request: (operation, _, _) => operation == 'catalog'
            ? catalog.future
            : Future.value({'data': {}}),
      );
      final media = MioHomeController(service);
      final raw = _video('420', '42', '电影大全', '晚到电影');
      // 即便全局目录里有此条，未成功读取明确分类 catalog 之前也不能拿来填影视位。
      media.items[MioKind.movie] = [MioVideo.fromJson(raw)];
      media.pages[MioKind.movie] = 1;
      media.loadedCategoryIds[MioKind.movie] = '41';
      final home = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => List.generate(8, item),
      );
      addTearDown(home.dispose);
      addTearDown(media.dispose);
      addTearDown(service.dispose);
      await home.refresh();
      await _mount(tester, home, media);
      await tester.pumpAndSettle();
      final main = find.byKey(const ValueKey('home-primary-recommendations'));
      expect(
        find.descendant(of: main, matching: find.text('晚到电影')),
        findsNothing,
      );
      media.categoryIds[MioKind.movie] = '42';
      final pending = media.load(MioKind.movie, reset: true);
      await tester.pump();
      expect(
        find.descendant(of: main, matching: find.text('晚到电影')),
        findsNothing,
      );
      catalog.complete({
        'data': {
          'videos': [raw],
          'pageinfo': {'total': 1},
        },
      });
      await pending;
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: main, matching: find.text('晚到电影')),
        findsOneWidget,
      );
    },
  );
}
