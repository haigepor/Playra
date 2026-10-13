import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_browse.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

MioVideo movie(String id) => MioVideo.fromJson({
  'id': id,
  'title': '电影$id',
  'categoryId': '42',
  'categoryName': '电影大全',
  'year': 2025,
  'area': '中国',
  'currentEpisodes': 1,
});

Widget screen(Widget child, {double scale = 1}) => MaterialApp(
  home: ModernHomeScope(
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'movie metadata avoids a fake episode caption and fits large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        screen(
          Padding(
            padding: const EdgeInsets.all(20),
            child: MioPosterGrid(
              items: [movie('1'), movie('2'), movie('3'), movie('4')],
              onDetails: (_) {},
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1集 · 电影大全'), findsNothing);
      expect(find.text('2025 · 中国'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category load more retains existing titles and real category pagination',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          requests.add(payload);
          return {
            'data': {
              'videos': [
                {
                  'id': '1',
                  'title': '电影1',
                  'categoryId': '42',
                  'categoryName': '电影大全',
                },
                {
                  'id': '2',
                  'title': '电影2',
                  'categoryId': '42',
                  'categoryName': '电影大全',
                },
              ],
              'pageinfo': {'total': 2},
            },
          };
        },
      );
      final controller = MioHomeController(service);
      controller.categoryIds[MioKind.movie] = '42';
      controller.items[MioKind.movie] = [movie('1')];
      controller.pages[MioKind.movie] = 1;
      controller.more.add(MioKind.movie);
      await tester.pumpWidget(
        screen(
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => MioHomeSections(
              controller: controller,
              feed: HomeFeed.movies,
              onDetails: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('加载更多电影'));
      await tester.pumpAndSettle();
      expect(requests.single['pageIndex'], 2);
      expect(requests.single['categoryId'], '42');
      expect(controller.items[MioKind.movie]!.map((v) => v.id), ['1', '2']);
      expect(find.text('电影2'), findsOneWidget);
      expect(find.text('已显示当前全部内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      service.dispose();
    },
  );

  testWidgets(
    'first category failure can retry despite discovery cards and no page',
    (tester) async {
      var requests = 0;
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          requests++;
          return {
            'data': {
              'videos': [
                {
                  'id': '2',
                  'title': '电影2',
                  'categoryId': '42',
                  'categoryName': '电影大全',
                },
              ],
              'pageinfo': {'total': 1},
            },
          };
        },
      );
      final controller = MioHomeController(service);
      controller.categoryIds[MioKind.movie] = '42';
      controller.items[MioKind.movie] = [movie('1')];
      controller.failed.add(MioKind.movie);
      await tester.pumpWidget(
        screen(
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => MioHomeSections(
              controller: controller,
              feed: HomeFeed.movies,
              onDetails: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('加载失败，点击重试'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(controller.pages[MioKind.movie], 1);
      expect(controller.items[MioKind.movie]!.single.id, '2');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      service.dispose();
    },
  );
}
