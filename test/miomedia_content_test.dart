import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_detail_page.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

void main() {
  test('source identities stay strings and metadata owns classification', () {
    final movie = MioVideo.fromJson({
      'id': '329257153645817856',
      'title': '动漫同名作品',
      'categoryId': '42',
      'categoryName': '电影大全',
    });
    expect(movie.id, '329257153645817856');
    expect(movie.kind, MioKind.movie);
    expect(
      MioVideo.fromJson({'id': '2', 'title': '电影', 'categoryName': '未知'}).kind,
      MioKind.unknown,
    );
    expect(
      () => MioVideo.fromJson({'id': 329257153645817856, 'title': 'wrong'}),
      throwsFormatException,
    );
  });
  test('search ignores broken pages zero and uses total for pagination', () {
    final page = MioPage.fromJson(
      {
        'videos': [
          {'id': '1', 'title': '吞噬'},
        ],
        'pageinfo': {'total': 9, 'pages': 0},
      },
      page: 2,
      size: 2,
    );
    expect(page.hasMore, isTrue);
    expect(
      MioPage.fromJson(
        {
          'videos': [],
          'pageinfo': {'total': 9, 'pages': 0},
        },
        page: 3,
        size: 2,
      ).hasMore,
      isFalse,
    );
  });
  test(
    'search and catalog forward only verified keyword/categoryId parameters',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          requests.add({'operation': operation, ...payload});
          return {
            'data': {
              'videos': [],
              'pageinfo': {'total': 0},
            },
          };
        },
      );
      await service.search(' 吞噬星空 ', page: 2, size: 3);
      await service.catalog(categoryId: '42', page: 2, size: 3);
      expect(requests[0]['keyword'], '吞噬星空');
      expect(requests[0]['pageIndex'], 2);
      expect(requests[1]['categoryId'], '42');
      service.dispose();
    },
  );
  test('episode selection uses actual numbers and line codes', () {
    final episode = MioEpisode.fromJson({
      'episodeNum': 12,
      'displayName': '特别篇',
      'code': 'real_line',
    });
    expect(episode.number, 12);
    expect(episode.code, 'real_line');
    expect(episode.name, '特别篇');
    expect(
      () => MioEpisode.fromJson({'episodeNum': '12', 'code': 'x'}),
      throwsFormatException,
    );
    expect(
      MioVideo.fromJson({
        'id': '3',
        'title': 'dirty',
        'currentEpisodes': 'unknown',
      }).episodeCount,
      0,
    );
  });

  test('home publishes catalog before a slow search config finishes', () async {
    final slow = Completer<Map<String, dynamic>>();
    final service = MioMediaService(
      request: (operation, payload, cancel) async {
        if (operation == 'searchConfig') return slow.future;
        return {
          'data': {
            'videos': [
              {
                'id': '123',
                'title': '电影',
                'categoryName': '电影大全',
                'categoryId': '42',
              },
            ],
            'pageinfo': {'total': 1},
          },
        };
      },
    );
    final controller = MioHomeController(service);
    final future = controller.bootstrap();
    await Future<void>.delayed(Duration.zero);
    expect(controller.items[MioKind.movie]?.single.id, '123');
    expect(controller.discovering, isTrue);
    slow.complete({'data': {}});
    await future;
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    service.dispose();
  });

  test(
    'anime-only bootstrap discovers movie category from bounded metadata search',
    () async {
      final requests = <Map<String, dynamic>>[];
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          requests.add({'operation': operation, ...payload});
          if (operation == 'searchConfig') return {'data': {}};
          final videos =
              operation == 'search' && payload['keyword'] == '电影' ||
                  payload['categoryId'] == '42'
              ? [
                  {
                    'id': '321',
                    'title': '无关标题',
                    'categoryName': '电影大全',
                    'categoryId': '42',
                  },
                ]
              : [
                  {
                    'id': '123',
                    'title': '电影同名动漫',
                    'categoryName': '国产动漫',
                    'categoryId': '11',
                  },
                ];
          return {
            'data': {
              'videos': videos,
              'pageinfo': {'total': 1},
            },
          };
        },
      );
      final controller = MioHomeController(service);
      await controller.bootstrap();
      expect(controller.categoryIds[MioKind.movie], '42');
      expect(controller.items[MioKind.movie]?.single.id, '321');
      expect(requests.where((r) => r['operation'] == 'search').length, 4);
      expect(
        requests.any(
          (r) => r['operation'] == 'catalog' && r['categoryId'] == '42',
        ),
        isTrue,
      );
      expect(controller.items[MioKind.series], isNull);
      controller.dispose();
      service.dispose();
    },
  );

  testWidgets(
    'detail displays episodes before playback and keeps real episode identity',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <Map<String, dynamic>>[];
      final raw = {
        'id': '123',
        'title': '测试作品',
        'categoryName': '电影大全',
        'player': [
          {'playerCode': 'source_a', 'playerName': '线路甲'},
        ],
      };
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          calls.add({'operation': operation, ...payload});
          return {
            'data': switch (operation) {
              'detail' => {'video': raw},
              'episodes' => {
                'episodes': [
                  {'episodeNum': 12, 'displayName': '特别篇', 'code': 'source_a'},
                ],
              },
              'play' => {
                'status': 'ad_required',
                'ad': {'adRequired': true},
              },
              _ => {},
            },
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MioDetailPage(item: MioVideo.fromJson(raw), service: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('特别篇'), findsOneWidget);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(calls.where((r) => r['operation'] == 'play'), isEmpty);
      await tester.tap(find.text('特别篇'));
      await tester.pumpAndSettle();
      expect(calls.last['episodeNum'], 12);
      expect(calls.last['code'], 'source_a');
      expect(find.textContaining('广告校验'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets('all episodes sort and retain nonconsecutive real numbers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    final raw = {
      'id': '123',
      'title': '长篇作品',
      'player': [
        {'playerCode': 'line_a', 'playerName': '线路甲'},
      ],
    };
    final service = MioMediaService(
      request: (operation, payload, cancel) async {
        calls.add({'operation': operation, ...payload});
        return {
          'data': switch (operation) {
            'detail' => {'video': raw},
            'episodes' => {
              'episodes': [
                for (var index = 0; index < 80; index++)
                  {
                    'episodeNum': 100 + index * 2,
                    'displayName': '集${100 + index * 2}',
                    'code': 'line_a',
                  },
              ],
            },
            'play' => {'status': 'ad_required', 'ad': {}},
            _ => {},
          },
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MioDetailPage(item: MioVideo.fromJson(raw), service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部 80集 ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('集258'));
    await tester.pumpAndSettle();
    expect(calls.last['episodeNum'], 258);
    expect(calls.last['code'], 'line_a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
