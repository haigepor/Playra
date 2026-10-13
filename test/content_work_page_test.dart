import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/content_work_page.dart';
import 'package:kazumi/services/source/content_search.dart';

class CandidateProvider extends ContentSearchProvider {
  @override
  String get id => 'candidate';
  @override
  String get name => '候选来源';
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  @override
  bool get canPlay => true;
  @override
  Future<ContentSearchPage> search(
    ContentQuery q,
    int page,
    CancelToken c,
  ) async => const ContentSearchPage([
    ContentHit(
      providerId: 'candidate',
      contentId: '2',
      title: '同名作品',
      group: ContentGroup.anime,
    ),
  ], hasMore: false);
  @override
  Future<List<ContentLine>> lines(ContentHit hit, CancelToken c) async =>
      const [
        ContentLine('line', '候选线路', [ContentEpisode('ep', '第1集')]),
      ];
}

void main() {
  testWidgets(
    'sparse same-name source requires confirmation before episode selection',
    (tester) async {
      final session = ContentSearchSession([CandidateProvider()]);
      addTearDown(session.dispose);
      await session.submit(const ContentQuery('同名作品'));
      final work = ContentWork(
        const ContentHit(
          providerId: 'metadata',
          contentId: '1',
          title: '同名作品',
          group: ContentGroup.anime,
          year: 2026,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ContentWorkPage(work: work, session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('候选线路'));
      await tester.pumpAndSettle();
      expect(find.text('确认同名候选'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('第1集'), findsNothing);
      await tester.tap(find.text('候选线路'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认选择'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('第1集'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('第1集'), findsOneWidget);
      expect(find.textContaining('已起播'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
