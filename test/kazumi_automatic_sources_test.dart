import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/source_candidates.dart';
import 'package:kazumi/services/source/source_policy.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';

const _title = '自动优先来源测试';
final _work = BangumiItem.fromJson({
  'id': 900617,
  'type': 2,
  'name': _title,
  'rating': <String, dynamic>{},
  'images': <String, dynamic>{},
});

class _Rule extends Plugin {
  _Rule(String official, this.calls)
    : super(
        name: official,
        type: 'anime',
        api: '9',
        sourceId: official.toLowerCase(),
        version: '1',
        muliSources: true,
        useWebview: true,
        useNativePlayer: true,
        usePost: false,
        useLegacyParser: false,
        adBlocker: false,
        userAgent: '',
        baseUrl: '${kazumiRuleOrigins[official]}/',
        searchURL: '',
        searchList: '',
        searchName: '',
        searchResult: '',
        chapterRoads: '',
        chapterResult: '',
        referer: '',
        sourceConfig: {'managedBy': 'playra-kazumi', 'officialName': official},
      );
  final List<String> calls;
  Future<void> Function()? beforeSearch;
  bool missing = false;
  RuleCancelToken? searchToken;
  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    calls.add(sourceConfig['officialName'] as String);
    searchToken = cancelToken;
    await beforeSearch?.call();
    return PluginSearchResponse(
      pluginName: name,
      data: missing ? [] : [SearchItem(name: _title, src: '/work')],
    );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async => [
    Road(
      id: 'original',
      name: '官方第一条',
      data: ['/episode/1'],
      identifier: ['第1集'],
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SourcePolicy.shared.restore('{}'));

  test(
    'all sixteen rules remain manual while only three enter automatic selection',
    () {
      final rules = kazumiRuleOrigins.keys
          .map((name) => _Rule(name, []))
          .toList();
      final groups = PlaybackSourceGroup.fromPlugins(rules);
      expect(groups, hasLength(1));
      expect(groups.single.id, 'kazumi');
      expect(groups.single.plugins, hasLength(16));
      expect(
        automaticPlaybackSources(
          rules,
        ).map((p) => p.sourceConfig['officialName']),
        ['akianime', 'mutefun', 'giriGiriLove'],
      );
      final custom = _Rule('AGE', [])..sourceConfig.remove('managedBy');
      expect(automaticPlaybackSources([custom]), [custom]);
      expect(playbackSdkId(custom), 'rule:age');
    },
  );

  test(
    'automatic first choice ignores fast manual-only sources and prefers akianime',
    () async {
      final calls = <String>[];
      final age = _Rule('AGE', calls),
          giri = _Rule('giriGiriLove', calls),
          mute = _Rule('mutefun', calls);
      final aki = _Rule('akianime', calls)
        ..beforeSearch = () =>
            Future<void>.delayed(const Duration(milliseconds: 20));
      final choice = await SourceCandidates().selectEpisode(
        _work,
        [age, giri, mute, aki],
        1,
        RuleCancelToken(),
      );
      expect(choice?.candidate.plugin, same(aki));
      expect(calls, ['akianime']);
    },
  );

  test('a cached fast backup cannot bypass an uncached primary', () async {
    final calls = <String>[];
    final aki = _Rule('akianime', calls),
        mute = _Rule('mutefun', calls),
        giri = _Rule('giriGiriLove', calls);
    final candidates = SourceCandidates();
    await candidates.prepare(_work, giri, [
      SearchItem(name: _title, src: '/work'),
    ]);
    SourcePolicy.shared.record(
      giri.providerId,
      giri.version,
      success: true,
      elapsedMs: 1,
    );
    final choice = await candidates.selectEpisode(
      _work,
      [giri, mute, aki],
      1,
      RuleCancelToken(),
    );
    expect(choice?.candidate.plugin, same(aki));
    expect(calls, ['akianime']);
  });

  test(
    'unavailable primary directories fall through to mutefun then giri',
    () async {
      final calls = <String>[];
      final aki = _Rule('akianime', calls)..missing = true;
      final mute = _Rule('mutefun', calls)..missing = true;
      final giri = _Rule('giriGiriLove', calls), age = _Rule('AGE', calls);
      final choice = await SourceCandidates().selectEpisode(
        _work,
        [age, giri, mute, aki],
        1,
        RuleCancelToken(),
      );
      expect(choice?.candidate.plugin, same(giri));
      expect(calls, ['akianime', 'mutefun', 'giriGiriLove']);
    },
  );

  test(
    'manual-only rules remain preparable and cached without joining automatic selection',
    () async {
      final calls = <String>[];
      final age = _Rule('AGE', calls);
      final candidates = SourceCandidates();
      final manual = await candidates.prepare(_work, age, [
        SearchItem(name: _title, src: '/work'),
      ]);
      expect(manual.single.roads.single.name, '官方第一条');
      expect(candidates.cached(_work, [age]), hasLength(1));
      expect(
        await candidates.selectEpisode(_work, [age], 1, RuleCancelToken()),
        isNull,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'disabled primary is skipped and managed identity survives local renaming',
    () async {
      final calls = <String>[];
      final aki = _Rule('akianime', calls)
        ..name = '本地改名'
        ..sourceId = 'custom-aki-id';
      final mute = _Rule('mutefun', calls), giri = _Rule('giriGiriLove', calls);
      expect(
        (await SourceCandidates().selectEpisode(
          _work,
          [giri, mute, aki],
          1,
          RuleCancelToken(),
        ))?.candidate.plugin,
        same(aki),
      );
      calls.clear();
      await SourcePolicy.shared.configure(aki.providerId, enabled: false);
      expect(
        (await SourceCandidates().selectEpisode(
          _work,
          [giri, mute, aki],
          1,
          RuleCancelToken(),
        ))?.candidate.plugin,
        same(mute),
      );
      expect(calls, ['mutefun']);
    },
  );

  testWidgets(
    'a stalled primary has a bounded preparation window before the backup',
    (tester) async {
      final calls = <String>[];
      final stalled = Completer<void>();
      final aki = _Rule('akianime', calls)..beforeSearch = () => stalled.future;
      final mute = _Rule('mutefun', calls);
      final selection = SourceCandidates().selectEpisode(
        _work,
        [aki, mute],
        1,
        RuleCancelToken(),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect((await selection)?.candidate.plugin, same(mute));
      expect(aki.searchToken?.isCancelled, isTrue);
      stalled.complete();
      await tester.pump();
    },
  );

  test(
    'fallback cache respects primary order and filters manual-only Kazumi rules',
    () async {
      final calls = <String>[];
      final aki = _Rule('akianime', calls),
          mute = _Rule('mutefun', calls),
          giri = _Rule('giriGiriLove', calls),
          age = _Rule('AGE', calls);
      final candidates = SourceCandidates();
      for (final source in [age, giri, mute, aki]) {
        await candidates.prepare(_work, source, [
          SearchItem(name: _title, src: '/work'),
        ]);
      }
      SourcePolicy.shared.record(
        giri.providerId,
        giri.version,
        success: true,
        elapsedMs: 1,
      );
      final allowed = automaticPlaybackSources([age, giri, mute, aki]);
      expect(candidates.cached(_work, allowed).map((c) => c.plugin), [
        aki,
        mute,
        giri,
      ]);
      final next = await candidates.selectEpisode(
        _work,
        allowed.where((p) => p != aki).toList(),
        1,
        RuleCancelToken(),
      );
      expect(next?.candidate.plugin, same(mute));
      expect(candidates.cached(_work, [age]), hasLength(1));
    },
  );

  test('cancelling a pending preferred source never starts a backup', () async {
    final calls = <String>[];
    final stalled = Completer<void>();
    final aki = _Rule('akianime', calls)..beforeSearch = () => stalled.future;
    final mute = _Rule('mutefun', calls);
    final cancel = RuleCancelToken();
    final selection = SourceCandidates().selectEpisode(
      _work,
      [aki, mute],
      1,
      cancel,
    );
    await Future<void>.delayed(Duration.zero);
    cancel.cancel('left page');
    expect(await selection, isNull);
    expect(calls, ['akianime']);
    await Future<void>.delayed(Duration.zero);
    expect(aki.searchToken?.isCancelled, isTrue);
    stalled.complete();
  });
}
