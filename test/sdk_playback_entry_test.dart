import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';

class ForeignSdk extends SdkPlaybackProvider {
  ForeignSdk(this.id);
  @override
  final String id;
  @override
  String get name => id;
  final played = <String>[];
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async =>
      SdkVideoData(
        id: id,
        title: '相同电影',
        singleMovie: true,
        lines: [SdkLine('line/$id', '原生编码线路')],
      );
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => [SdkEpisode(number: 57, name: '正片', code: code)];
  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    played.add('$id|$code|$episode');
    return {'status': 'unavailable'};
  }
}

class SearchSdk extends ContentSearchProvider {
  SearchSdk(this.sdkPlayback, [this.hits = const []]);
  final List<ContentHit> hits;
  @override
  final ForeignSdk sdkPlayback;
  @override
  String get id => sdkPlayback.id;
  @override
  String get name => id;
  @override
  bool get canPlay => true;
  @override
  Set<ContentGroup> get groups => {ContentGroup.screen};
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async => ContentSearchPage(hits, hasMore: false);
}

ContentHit hit(String sdk, String id) => ContentHit(
  providerId: sdk,
  contentId: id,
  title: '相同电影',
  group: ContentGroup.screen,
  year: 2025,
);

void main() {
  test(
    'work carries both SDK identities without converting foreign references to Mio IDs',
    () async {
      final a = ForeignSdk('miomedia'), b = ForeignSdk('sdk_other');
      final providers = [
        SearchSdk(a, [hit(a.id, 'a-identity')]),
        SearchSdk(b, [hit(b.id, 'foreign/id?x')]),
      ];
      final session = ContentSearchSession(providers, ownsProviders: false);
      addTearDown(session.dispose);
      await session.submit(const ContentQuery('相同电影'));
      final work = session.works.single;
      final entry = SdkPlaybackEntry.fromWork(work, [
        SearchSdk(a),
        SearchSdk(b),
      ])!;
      expect(entry.sources.map((s) => s.provider.id), [
        'miomedia',
        'sdk_other',
      ]);
      expect(entry.sources.last.contentId, 'foreign/id?x');
    },
  );
  test('ambiguous IDs inside one SDK are not arbitrarily selected', () async {
    final sdk = ForeignSdk('sdk_other');
    final session = ContentSearchSession([
      SearchSdk(sdk, [hit(sdk.id, 'first'), hit(sdk.id, 'different-edition')]),
    ], ownsProviders: false);
    addTearDown(session.dispose);
    await session.submit(const ContentQuery('相同电影'));
    final work = session.works.single;
    expect(SdkPlaybackEntry.fromWork(work, [SearchSdk(sdk)]), isNull);
  });
  testWidgets(
    'second SDK works through the same player page and starts on explicit selection',
    (tester) async {
      final a = ForeignSdk('miomedia'), b = ForeignSdk('sdk_other');
      await tester.pumpWidget(
        MaterialApp(
          home: SdkDetailPage(
            entry: SdkPlaybackEntry(
              title: '相同电影',
              autoPlay: false,
              sources: [
                SdkSourceBinding(provider: a, contentId: 'a-identity'),
                SdkSourceBinding(provider: b, contentId: 'foreign/id?x'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'miomedia'), findsOneWidget);
      final other = find.widgetWithText(ChoiceChip, 'sdk_other');
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(other).selected, isTrue);
      expect(a.played, isEmpty);
      expect(b.played, ['foreign/id?x|line/foreign/id?x|57']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
