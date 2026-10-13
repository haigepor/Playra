import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/services/source/content_search.dart';

class FixtureProvider extends ContentSearchProvider {
  FixtureProvider(this.id, this.groups, this.fetch);
  @override
  final String id;
  @override
  String get name => id;
  @override
  final Set<ContentGroup> groups;
  final Future<ContentSearchPage> Function(int, CancelToken) fetch;
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) => fetch(page, cancel);
}

ContentHit hit(
  String provider,
  String id, {
  String title = '作品 第二季',
  int? year = 2026,
  ContentGroup group = ContentGroup.anime,
}) => ContentHit(
  providerId: provider,
  contentId: id,
  title: title,
  group: group,
  year: year,
);

void main() {
  test(
    'region matching keeps coproductions without treating substrings as country codes',
    () {
      expect(contentRegions('中国/美国'), {'CN', 'US'});
      expect(contentRegions('RUSSIA'), isEmpty);
      expect(contentRegions('JP'), {'JP'});
      expect(contentRegions('JP US'), {'JP', 'US'});
      expect(contentRegions('JP\tKR'), {'JP', 'KR'});
    },
  );
  test(
    'sparse same-name records stay independent until identity evidence is available',
    () async {
      final session = ContentSearchSession([
        FixtureProvider(
          'a',
          {ContentGroup.anime},
          (_, _) async =>
              ContentSearchPage([hit('a', '1', year: null)], hasMore: false),
        ),
        FixtureProvider(
          'b',
          {ContentGroup.anime},
          (_, _) async =>
              ContentSearchPage([hit('b', '2', year: null)], hasMore: false),
        ),
      ]);
      addTearDown(session.dispose);
      await session.submit(const ContentQuery('作品'));
      expect(session.works, hasLength(2));
      expect(
        matchContent(session.works.first.primary, session.works.last.primary),
        ContentMatch.possible,
      );
    },
  );
  test(
    'the whole batch budget releases hung providers and keeps an explicit timeout',
    () async {
      final session = ContentSearchSession(
        [
          FixtureProvider('hang', {
            ContentGroup.anime,
          }, (_, _) => Completer<ContentSearchPage>().future),
        ],
        timeout: const Duration(seconds: 10),
        batchTimeout: const Duration(milliseconds: 25),
      );
      addTearDown(session.dispose);
      await session
          .submit(const ContentQuery('作品'))
          .timeout(const Duration(seconds: 2));
      expect(session.searching, isFalse);
      expect(session.errors['hang'], 'TIMEOUT');
    },
  );
  test('four groups separate series, animated films and short dramas', () {
    expect(ContentGroup.values.map((e) => e.label), ['动漫', '影视', '漫剧', '剧集']);
    expect(ContentGroup.fromKind('anime'), ContentGroup.anime);
    expect(ContentGroup.fromKind('shortDrama'), ContentGroup.series);
    expect(ContentGroup.fromKind('documentary'), ContentGroup.screen);
    expect(ContentGroup.fromKind('unknown'), isNull);
  });

  test(
    'fast results publish before a slow provider finishes; duplicate work retains both sources',
    () async {
      final slow = Completer<ContentSearchPage>();
      final session = ContentSearchSession([
        FixtureProvider(
          'fast',
          {ContentGroup.anime},
          (_, _) async => ContentSearchPage([
            hit('fast', '1'),
            hit('fast', '1'),
          ], hasMore: false),
        ),
        FixtureProvider('slow', {ContentGroup.anime}, (_, _) => slow.future),
      ]);
      addTearDown(session.dispose);
      final first = Completer<void>();
      session.addListener(() {
        if (session.works.isNotEmpty && !first.isCompleted) first.complete();
      });
      final pending = session.submit(
        const ContentQuery('作品', group: ContentGroup.anime),
      );
      await first.future;
      expect(session.searching, isTrue);
      expect(session.works.single.hits, hasLength(1));
      final groupId = session.works.single.id;
      slow.complete(ContentSearchPage([hit('slow', '2')], hasMore: false));
      await pending;
      expect(session.works.single.id, groupId);
      expect(session.works.single.hits, hasLength(2));
      expect(session.searching, isFalse);
    },
  );

  test(
    'conflicting seasons, years and media groups are never merged',
    () async {
      final session = ContentSearchSession([
        FixtureProvider(
          'a',
          {ContentGroup.anime},
          (_, _) async => ContentSearchPage([
            hit('a', '1'),
            hit('a', '2', year: 2025),
            hit('a', '3', title: '作品 第一季'),
          ], hasMore: false),
        ),
        FixtureProvider(
          'b',
          {ContentGroup.series},
          (_, _) async => ContentSearchPage([
            hit('b', '1', group: ContentGroup.series),
          ], hasMore: false),
        ),
      ]);
      addTearDown(session.dispose);
      await session.submit(const ContentQuery('作品'));
      expect(session.works, hasLength(4));
    },
  );

  test(
    'reserved groups issue no requests and old query cannot overwrite a new one',
    () async {
      final old = Completer<ContentSearchPage>();
      var calls = 0;
      final session = ContentSearchSession([
        FixtureProvider('a', {ContentGroup.anime}, (_, _) {
          calls++;
          return calls == 1
              ? old.future
              : Future.value(
                  ContentSearchPage([hit('a', 'new')], hasMore: false),
                );
        }),
      ]);
      addTearDown(session.dispose);
      await session.submit(
        const ContentQuery('漫剧', group: ContentGroup.comicDrama),
      );
      expect(calls, 0);
      expect(session.hasProviders, isFalse);
      final first = session.submit(
        const ContentQuery('旧', group: ContentGroup.anime),
      );
      await Future<void>.delayed(Duration.zero);
      await session.submit(const ContentQuery('新', group: ContentGroup.anime));
      old.complete(ContentSearchPage([hit('a', 'old')], hasMore: false));
      await first;
      expect(session.works.single.hits.single.contentId, 'new');
    },
  );

  test('duplicate-only page does not terminate upstream pagination', () async {
    final session = ContentSearchSession([
      FixtureProvider(
        'a',
        {ContentGroup.anime},
        (page, _) async => ContentSearchPage([
          hit('a', page < 3 ? '1' : '2', title: page < 3 ? '甲' : '乙'),
        ], hasMore: page < 3),
      ),
    ]);
    addTearDown(session.dispose);
    await session.submit(const ContentQuery('作品'));
    await session.loadMore();
    expect(session.hasMore, isTrue);
    await session.loadMore();
    expect(session.works, hasLength(2));
    expect(session.hasMore, isFalse);
  });

  test(
    'partial failures retain results; concurrency limit is respected',
    () async {
      var running = 0, maximum = 0;
      final releases = List.generate(5, (_) => Completer<ContentSearchPage>());
      final session = ContentSearchSession(
        List.generate(
          5,
          (i) => FixtureProvider('$i', {ContentGroup.anime}, (_, _) async {
            running++;
            maximum = running > maximum ? running : maximum;
            try {
              return await releases[i].future;
            } finally {
              running--;
            }
          }),
        ),
        concurrency: 2,
      );
      addTearDown(session.dispose);
      final pending = session.submit(const ContentQuery('作品'));
      await Future<void>.delayed(Duration.zero);
      expect(maximum, 2);
      releases[0].completeError(StateError('failure'));
      releases[1].complete(ContentSearchPage([hit('1', '1')], hasMore: false));
      for (var i = 2; i < 5; i++) {
        releases[i].complete(ContentSearchPage([], hasMore: false));
      }
      await pending;
      expect(session.works, hasLength(1));
      expect(session.failures, 1);
      expect(maximum, 2);
    },
  );
}
