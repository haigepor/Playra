import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_browse.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/presentation/modern/widgets/modern_feature_carousel.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/source_models.dart';

Future<void> _mountFilmHome(
  WidgetTester tester,
  ModernHomeController home,
  MioHomeController media,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
}

Widget _carousel(double scale) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: ModernHomeScope(
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ModernFeatureCarousel(
          entries: [
            for (var i = 0; i < 6; i++)
              ModernFeatureEntry(
                id: '$i',
                title: '一部很长名称的推荐作品第 $i 季',
                subtitle: '科幻 · 悬疑 · 电影',
                cover: '',
                onTap: () {},
              ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'loaded film home does not display an anime empty state or retry',
    (tester) async {
      var animeRequests = 0;
      final service = MioMediaService(
        request: (_, payload, _) async => {
          'data': {
            'videos': payload['categoryId'] == '42'
                ? [
                    {
                      'id': '101',
                      'title': '测试电影',
                      'categoryId': '42',
                      'categoryName': '电影大全',
                      'score': 8.2,
                    },
                  ]
                : [],
          },
        },
      );
      final media = MioHomeController(service);
      final home = ModernHomeController(
        loadFeed: (_, _) async {
          animeRequests++;
          return [];
        },
        readHistory: () => [],
      );
      addTearDown(home.dispose);
      addTearDown(media.dispose);
      addTearDown(service.dispose);
      media.categoryIds[MioKind.movie] = '42';
      media.categoryIds[MioKind.variety] = '43';
      await media.load(MioKind.movie, reset: true);
      await media.load(MioKind.variety, reset: true);
      await home.selectFeed(HomeFeed.screen);
      await _mountFilmHome(tester, home, media);

      expect(media.items[MioKind.movie]!.single.title, '测试电影');
      expect(find.text('测试电影'), findsWidgets);
      expect(find.text('暂时没有可展示的番剧'), findsNothing);
      expect(find.text('这个分类暂时没有符合条件的作品'), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(animeRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty film home describes movie content without anime retry', (
    tester,
  ) async {
    var animeRequests = 0;
    final service = MioMediaService(
      request: (_, _, _) async => {
        'data': {'videos': []},
      },
    );
    final media = MioHomeController(service);
    final home = ModernHomeController(
      loadFeed: (_, _) async {
        animeRequests++;
        return [];
      },
      readHistory: () => [],
    );
    addTearDown(home.dispose);
    addTearDown(media.dispose);
    addTearDown(service.dispose);
    media.categoryIds[MioKind.movie] = '42';
    media.categoryIds[MioKind.variety] = '43';
    await media.load(MioKind.movie, reset: true);
    await media.load(MioKind.variety, reset: true);
    await home.selectFeed(HomeFeed.screen);
    await _mountFilmHome(tester, home, media);

    expect(find.text('暂无电影内容'), findsOneWidget);
    expect(find.text('暂时没有可展示的番剧'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(animeRequests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'film failure retries its source and clears the safe failure state',
    (tester) async {
      var unavailable = true;
      var animeRequests = 0;
      final service = MioMediaService(
        request: (_, _, _) async {
          if (unavailable) {
            throw const SourceException('TIMEOUT', 'private upstream detail');
          }
          return {
            'data': {'videos': []},
          };
        },
      );
      final media = MioHomeController(service);
      final home = ModernHomeController(
        loadFeed: (_, _) async {
          animeRequests++;
          return [];
        },
        readHistory: () => [],
      );
      addTearDown(home.dispose);
      addTearDown(media.dispose);
      addTearDown(service.dispose);
      media.categoryIds[MioKind.movie] = '42';
      media.categoryIds[MioKind.variety] = '43';
      await media.load(MioKind.movie, reset: true);
      await media.load(MioKind.variety, reset: true);
      await home.selectFeed(HomeFeed.screen);
      await _mountFilmHome(tester, home, media);

      expect(find.text('暂时没有可展示的番剧'), findsNothing);
      expect(find.textContaining('private upstream detail'), findsNothing);
      final filmSections = find.byType(MioHomeSections);
      final retry = find
          .descendant(
            of: filmSections,
            matching: find.widgetWithText(TextButton, '重试'),
          )
          .first;
      expect(find.text('内容请求超时，请稍后重试（TIMEOUT）'), findsWidgets);
      unavailable = false;
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(media.failed, isNot(contains(MioKind.movie)));
      expect(find.text('暂无电影内容'), findsOneWidget);
      expect(animeRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
        'six carousel indicators remain separate tappable targets at width=$width scale=$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(_carousel(scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final areas = [
            for (var i = 0; i < 6; i++)
              tester.getRect(find.byKey(ValueKey('feature-indicator-$i'))),
          ];
          for (var i = 0; i < areas.length; i++) {
            expect(
              areas[i].width,
              greaterThanOrEqualTo(24),
              reason: '第 ${i + 1} 个切换点需要足够的实际点击宽度',
            );
            expect(areas[i].height, greaterThanOrEqualTo(24));
            expect(areas[i].left, greaterThanOrEqualTo(0));
            expect(areas[i].right, lessThanOrEqualTo(width));
            if (i > 0) {
              expect(
                areas[i - 1].overlaps(areas[i]),
                isFalse,
                reason: '相邻切换点不能使用互相覆盖的点击区域',
              );
            }
          }
          for (final index in [5, 1, 0]) {
            // 点击有效区域的边缘，避免只验证视觉圆点中心可用。
            await tester.tapAt(
              Offset(areas[index].left + 1, areas[index].center.dy),
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<PageView>(find.byType(PageView)).controller!.page,
              index.toDouble(),
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
