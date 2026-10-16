import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/lumina/lumina_content_provider.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

class _Provider extends ContentSearchProvider {
  _Provider(this.id, this.result, {this.priority = 0});
  @override
  final String id;
  final Future<ContentSearchPage> result;
  @override
  final int priority;
  @override
  String get name => id;
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) => result;
}

ContentHit _hit(String source, String title) => ContentHit(
  providerId: source,
  contentId: title,
  title: title,
  group: ContentGroup.anime,
  year: 2026,
  cover: 'https://images.example/$source.jpg',
);

void main() {
  test(
    'real traditional channel names retain regional catalog and next-page SDK identities',
    () async {
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (operation == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '日漫'},
                  {'id': '2', 'name': '國漫'},
                  {'id': '26', 'name': '動漫電影'},
                  {'id': '3', 'name': '其他動漫'},
                ],
              },
            };
          }
          if (operation == 'banners') {
            return {
              'data': {'banners': []},
            };
          }
          final id = '${payload['channelId']}',
              page = payload['pageIndex'] as int;
          return {
            'data': {
              'videos': [
                {'id': '$id$page', 'title': '真实作品$id-$page', 'updatedTo': 2},
                {
                  'id': '${id}99',
                  'title': '尚未更新的占位$id',
                  'updatedTo': 0,
                  'isEnd': false,
                },
              ],
              'pageInfo': {'total': 25},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      var publishedReady = false;
      home.addListener(() {
        if (home.browseItems().length == 4 && !home.loadingIn('all')) {
          publishedReady = true;
        }
      });
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(home.browseItems('japanese').map((v) => v.id), ['11']);
      expect(home.browseItems('chinese').map((v) => v.id), ['21']);
      expect(home.browseItems('movies').map((v) => v.id), ['261']);
      expect(home.browseItems().map((v) => v.id), ['11', '21', '261', '31']);
      expect(home.loadingIn('all'), isFalse);
      expect(publishedReady, isTrue);
      expect(home.hasMoreIn('chinese'), isTrue);
      await home.loadMoreIn('chinese');
      expect(home.browseItems('chinese').map((v) => v.id), ['21', '22']);
      expect(home.hasMoreIn('chinese'), isTrue);
      await home.loadMoreIn('chinese');
      expect(home.browseItems('chinese').map((v) => v.id), ['21', '22', '23']);
      expect(home.hasMoreIn('chinese'), isFalse);
    },
  );
  test(
    'explicit SDK detail refresh replaces cached parts without inventing an episode',
    () async {
      var updated = false;
      final service = LuminaService(
        request: (_, _, _) async => {
          'data': {
            'video': {'id': '42', 'title': '作品'},
            'parts': [
              {
                'play': 'mp4',
                'name': '线路3',
                'episodes': [
                  {'part': '第1集', 'name': '第1集', 'index': 1},
                  if (updated) {'part': '第2集', 'name': '第2集', 'index': 2},
                ],
              },
            ],
          },
        },
      );
      addTearDown(service.dispose);
      final sdk = LuminaContentProvider(service).sdkPlayback;
      await sdk.detail('42');
      expect(await sdk.episodes('42', 'mp4'), hasLength(1));
      updated = true;
      await sdk.detail('42');
      expect((await sdk.episodes('42', 'mp4')).map((e) => e.reference), [
        '第1集',
        '第2集',
      ]);
    },
  );

  testWidgets(
    'a pending Lumina refresh never delays other homepage providers',
    (tester) async {
      final luminaRefresh = Completer<void>();
      var legacyRefreshes = 0;
      final mioOperations = <String>[];
      final legacy = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async {
          legacyRefreshes++;
          return [];
        },
      );
      final mioService = MioMediaService(
        request: (operation, _, _) async {
          mioOperations.add(operation);
          return {
            'data': {
              'videos': [],
              'pageinfo': {'total': 0},
            },
          };
        },
      );
      final mio = MioHomeController(mioService);
      final anime = LuminaHomeController(
        LuminaService(request: (_, _, _) async => {'data': {}}),
      );
      addTearDown(legacy.dispose);
      addTearDown(mio.dispose);
      addTearDown(mioService.dispose);
      addTearDown(anime.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeView(
            controller: legacy,
            media: mio,
            anime: anime,
            refreshAnime: () => luminaRefresh.future,
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
      final refreshing = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(legacyRefreshes, 1);
      expect(mioOperations, contains('catalog'));
      expect(luminaRefresh.isCompleted, isFalse);
      luminaRefresh.complete();
      await refreshing;
      await tester.pumpAndSettle();
    },
  );

  test(
    'late preferred SDK owns merged presentation without merging conflicting seasons',
    () async {
      final delayed = Completer<ContentSearchPage>();
      final session = ContentSearchSession([
        _Provider(
          'legacy',
          Future.value(
            ContentSearchPage([
              _hit('legacy', '作品'),
              _hit('legacy', '其他'),
            ], hasMore: false),
          ),
        ),
        _Provider('lumina', delayed.future, priority: 100),
      ]);
      addTearDown(session.dispose);
      final pending = session.submit(const ContentQuery('作品'));
      await Future<void>.delayed(Duration.zero);
      expect(session.works.first.primary.providerId, 'legacy');
      delayed.complete(
        ContentSearchPage([
          _hit('lumina', '作品'),
          _hit('lumina', '作品 第二季'),
        ], hasMore: false),
      );
      await pending;
      expect(session.works.first.primary.providerId, 'lumina');
      expect(session.works.first.cover, 'https://images.example/lumina.jpg');
      expect(session.works, hasLength(3));
      expect(session.works.last.title, '其他');
    },
  );

  test(
    'Lumina preserves opaque part identity and never sends an array index as episode',
    () async {
      Map<String, dynamic>? playbackPayload;
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (operation == 'play') {
            playbackPayload = payload;
            return {
              'data': {
                'status': 'ready',
                'media': {
                  'url': 'https://media.example/video.mp4',
                  'format': 'mp4',
                  'headers': {'User-Agent': '', 'Referer': ''},
                },
              },
            };
          }
          return {
            'data': {
              'video': {'id': '42', 'title': '作品'},
              'parts': [
                {
                  'play': 'mp4',
                  'name': '线路3',
                  'episodes': [
                    {'part': 'SP 上篇', 'name': 'SP 上篇', 'index': 1},
                    {'part': '第12集', 'name': '第12集', 'index': 2},
                  ],
                },
              ],
            },
          };
        },
      );
      addTearDown(service.dispose);
      final provider = LuminaContentProvider(service);
      final episodes = await provider.sdkPlayback.episodes('42', 'mp4');
      expect(episodes.first.number, isNull);
      expect(episodes.first.identityKey, 'SP 上篇');
      expect(episodes.last.number, 12);
      final result = await provider.sdkPlayback.playEpisode(
        '42',
        'mp4',
        episodes.first,
      );
      expect(playbackPayload, {
        'videoId': '42',
        'playFormat': 'mp4',
        'part': 'SP 上篇',
      });
      expect(result['selection'], {
        'videoId': '42',
        'code': 'mp4',
        'episodeRef': 'SP 上篇',
      });
      expect((result['media'] as Map)['headers'], {
        'User-Agent': '',
        'Referer': '',
      });
    },
  );

  test(
    'detail rejects a foreign source identity and tolerates missing covers',
    () async {
      final service = LuminaService(
        request: (_, _, _) async => {
          'data': {
            'video': {'id': '99', 'title': '其他作品'},
            'parts': [],
          },
        },
      );
      addTearDown(service.dispose);
      expect(service.detail('42'), throwsA(isA<Exception>()));
    },
  );

  test(
    'homepage publishes real catalog while banner request is still pending',
    () async {
      final slowBanner = Completer<Map<String, dynamic>>();
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (operation == 'channels') {
            return {
              'data': {
                'channels': [
                  {
                    'id': '1',
                    'name': '国漫',
                    'types': ['weight'],
                  },
                ],
              },
            };
          }
          if (operation == 'banners') return slowBanner.future;
          return {
            'data': {
              'videos': [
                {
                  'id': '42',
                  'title': '作品',
                  'totalEpisodes': 12,
                  'updatedTo': 2,
                },
              ],
              'pageInfo': {'total': 1},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap();
      expect(home.items.single.id, '42');
      expect(home.items.single.updatedTo, 2);
      expect(home.items.single.lines, isEmpty);
      expect(home.loading, isFalse);
      expect(home.hasMore, isFalse);
      slowBanner.complete({
        'data': {'banners': []},
      });
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'homepage failure leaves old content eligible and can recover with original SDK identity',
    () async {
      var fail = true;
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (fail) throw StateError('local diagnostic never reaches UI');
          if (operation == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '动漫'},
                ],
              },
            };
          }
          if (operation == 'banners') {
            return {
              'data': {'banners': []},
            };
          }
          return {
            'data': {
              'videos': [
                {'id': '101', 'title': '作品'},
              ],
              'pageInfo': {'total': 1},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap();
      expect(home.useFallback, isTrue);
      expect(home.errorCode, 'SOURCE_ERROR');
      fail = false;
      await home.bootstrap(force: true);
      expect(home.useFallback, isFalse);
      expect(home.items.single.id, '101');
    },
  );

  testWidgets(
    'Lumina browse stays readable at 320px with enlarged text and keeps SDK identity',
    (tester) async {
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (operation == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '国产动漫'},
                  {'id': '2', 'name': '日本动漫'},
                ],
              },
            };
          }
          if (operation == 'banners') {
            return {
              'data': {'banners': []},
            };
          }
          return {
            'data': {
              'videos': [
                {'id': '421', 'title': '很长的动漫名称：第二季与特别篇', 'updatedTo': 2},
              ],
              'pageInfo': {'total': 1},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap();
      String? opened;
      final legacy = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => [],
      );
      addTearDown(legacy.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: modernHomeTheme(ThemeData(), forceDark: true),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: ModernHomeView(
              controller: legacy,
              anime: home,
              onAnimeDetails: (video) => opened = video.id,
              onSearch: () {},
              onCalendar: () {},
              onBrowse: (_) {},
              onHistory: () {},
              onToggleTheme: () {},
              onDetails: (_) {},
              onResume: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('home-shuffle-featured')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('lumina-browse')), findsNothing);
      expect(find.text('动漫 · Lumina'), findsNothing);
      await tester.tap(find.text('很长的动漫名称：第二季与特别篇').first);
      expect(opened, '421');
    },
  );
}
