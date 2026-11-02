import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/content_search_playback.dart';

BangumiItem item(int id, String title, String date) => BangumiItem(
  id: id,
  type: 2,
  name: title,
  nameCn: title,
  summary: '',
  airDate: date,
  airWeekday: 0,
  rank: 0,
  images: {},
  tags: [],
  alias: [],
  ratingScore: 0,
  votes: 0,
  votesCount: [],
  info: '',
);
ContentHit hit(String provider, String id, {int? year}) => ContentHit(
  providerId: provider,
  contentId: id,
  title: '吞噬星空',
  group: ContentGroup.anime,
  year: year,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a unique exact metadata identity opens without a confirmation choice',
    () {
      final target = item(1, '吞噬星空', '2020-11-29');
      expect(uniqueAnimeMetadata(hit('rule', '/1'), [target]), same(target));
      expect(
        uniqueAnimeMetadata(hit('rule', '/1', year: 2020), [
          target,
          item(2, '吞噬星空', '2026-01-01'),
        ]),
        same(target),
      );
      expect(
        uniqueAnimeMetadata(hit('rule', '/1'), [
          target,
          item(2, '吞噬星空', '2026-01-01'),
        ]),
        isNull,
      );
    },
  );
  test('retired rule preload cannot open old content', () async {
    final session = ContentSearchSession([]);
    addTearDown(session.dispose);
    expect(
      await prepareSearchPlayback(
        item(1, '吞噬星空', '2020-11-29'),
        ContentWork(hit('retired', '/old')),
        session,
        RuleCancelToken(),
      ),
      isNull,
    );
  });
}
