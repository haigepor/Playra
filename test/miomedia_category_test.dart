import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_category_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

MioVideo video(
  int id, {
  String types = '动作',
  double score = 7,
  bool recommended = false,
}) => MioVideo.fromJson({
  'id': '$id',
  'title': '作品$id',
  'categoryId': '42',
  'categoryName': '电影大全',
  'types': types,
  'score': score,
  'isRecommend': recommended,
});

void main() {
  test(
    'genre evidence and recommendation use metadata and preserve source order',
    () {
      final service = MioMediaService(request: (_, _, _) async => {'data': {}});
      final controller = MioHomeController(service);
      controller.items[MioKind.movie] = [
        video(1, types: '喜剧,动作', score: 9),
        video(2, types: '爱情', score: 6, recommended: true),
        video(3, types: '喜剧', score: 8),
      ];
      expect(controller.genres(MioKind.movie), ['动作', '喜剧', '爱情']);
      expect(controller.featured(MioKind.movie)!.id, '2');
      controller.selectGenre(MioKind.movie, '喜剧');
      expect(controller.filtered(MioKind.movie).map((v) => v.id), ['1', '3']);
      controller.shuffleFeatured(MioKind.movie);
      expect(controller.featured(MioKind.movie)!.id, '3');
      expect(controller.items[MioKind.movie]!.map((v) => v.id), [
        '1',
        '2',
        '3',
      ]);
      controller.selectGenre(MioKind.movie, '未提供的题材');
      expect(controller.genreSelections[MioKind.movie], '喜剧');
      controller.dispose();
      service.dispose();
    },
  );

  testWidgets('featured card supports compact viewport and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MioMediaService(request: (_, _, _) async => {'data': {}});
    final controller = MioHomeController(service);
    controller.items[MioKind.movie] = [video(1, types: '动作,科幻,冒险')];
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeScope(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MioFeaturedCard(
                    controller: controller,
                    kind: MioKind.movie,
                    onDetails: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('精选推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    service.dispose();
  });

  testWidgets(
    'category tail automatically pages without changing real IDs or faking weekly rank',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Map<String, dynamic>>[];
      final service = MioMediaService(
        request: (operation, payload, _) async {
          if (operation == 'hotRank') {
            return {
              'data': {'categoryId': payload['categoryId'], 'list': []},
            };
          }
          requests.add(payload);
          return {
            'data': {
              'videos': List.generate(
                20,
                (i) => {
                  'id': '${i + 21}',
                  'title': '作品${i + 21}',
                  'categoryId': '42',
                  'categoryName': '电影大全',
                  'types': '动作',
                },
              ),
              'pageinfo': {'total': 40},
            },
          };
        },
      );
      final media = MioHomeController(service);
      media.items[MioKind.movie] = List.generate(20, (i) => video(i + 1));
      media.categoryIds[MioKind.movie] = '42';
      media.pages[MioKind.movie] = 1;
      media.more.add(MioKind.movie);
      final home = ModernHomeController(
        loadFeed: (_, _) async => [],
        readHistory: () => [],
      )..feed = HomeFeed.movies;
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
      await tester.pumpAndSettle();
      expect(find.text('当前分类无榜单'), findsOneWidget);
      for (var i = 0; i < 8 && requests.isEmpty; i++) {
        await tester.drag(
          find.byKey(const PageStorageKey('modern-home-scroll')),
          const Offset(0, -800),
        );
        await tester.pumpAndSettle();
      }
      expect(requests.single['pageIndex'], 2);
      expect(requests.single['categoryId'], '42');
      expect(media.items[MioKind.movie]!.length, 40);
      expect(media.items[MioKind.movie]!.first.id, '1');
      expect(media.items[MioKind.movie]!.last.id, '40');
      expect(media.more, isNot(contains(MioKind.movie)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      home.dispose();
      media.dispose();
      service.dispose();
    },
  );
}
