import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/content_providers.dart';
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

class PreloadPlugin extends Plugin {
  PreloadPlugin(String id)
    : super(
        name: id,
        type: 'anime',
        api: '1',
        sourceId: id,
        version: '1',
        muliSources: true,
        useWebview: false,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: 'https://example.invalid',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
      );
  final ready = Completer<List<Road>>();
  int searches = 0, directories = 0;
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    searches++;
    return PluginSearchResponse(
      pluginName: name,
      data: [SearchItem(name: '吞噬星空', src: '/$name')],
    );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) {
    directories++;
    return ready.future;
  }
}

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
  test(
    'known result prepares a directory without repeating its search',
    () async {
      final plugin = PreloadPlugin('known-preload');
      final session = ContentSearchSession([RuleContentProvider(plugin)]);
      addTearDown(session.dispose);
      final cancel = RuleCancelToken();
      final pending = prepareSearchPlayback(
        item(900301, '吞噬星空', '2020-11-29'),
        ContentWork(hit(plugin.providerId, '/known')),
        session,
        cancel,
      );
      await Future<void>.delayed(Duration.zero);
      expect(plugin.searches, 0);
      expect(plugin.directories, 1);
      plugin.ready.complete([
        Road(name: '线路', data: ['/ep1'], identifier: ['第1集']),
      ]);
      final candidate = await pending;
      expect(
        candidate?.args(item(900301, '吞噬星空', '2020-11-29')).roads.first.data,
        ['/ep1'],
      );
      cancel.cancel();
    },
  );
  test(
    'metadata entry uses the first ready source without waiting for slow directories',
    () async {
      final slow = PreloadPlugin('slow-preload'),
          fast = PreloadPlugin('fast-preload');
      final session = ContentSearchSession([
        RuleContentProvider(slow),
        RuleContentProvider(fast),
      ]);
      addTearDown(session.dispose);
      final cancel = RuleCancelToken();
      final pending = prepareSearchPlayback(
        item(900302, '吞噬星空', '2020-11-29'),
        ContentWork(hit('metadata', '1')),
        session,
        cancel,
      );
      await Future<void>.delayed(Duration.zero);
      expect(slow.searches, 1);
      expect(fast.searches, 1);
      fast.ready.complete([
        Road(name: '线路', data: ['/ep1'], identifier: ['第1集']),
      ]);
      expect((await pending)?.plugin, same(fast));
      expect(slow.ready.isCompleted, isFalse);
      cancel.cancel();
      slow.ready.complete([]);
    },
  );
}
