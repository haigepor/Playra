import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/anime_source_session.dart';
import 'package:kazumi/services/source/source_candidates.dart';

const _title = '目录会话测试';

BangumiItem _work() => BangumiItem(
  id: 900401,
  type: 2,
  name: _title,
  nameCn: _title,
  summary: '',
  airDate: '2026-01-01',
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

List<Road> _roads() => [
  Road(
    id: '2',
    name: '线路2',
    data: ['opaque-title/road-2/episode-14'],
    identifier: ['第14集'],
  ),
];

class _DirectoryPlugin extends Plugin {
  _DirectoryPlugin(String id)
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

  int searches = 0, directories = 0;
  final directoryTokens = <RuleCancelToken?>[];
  Future<List<Road>> Function()? loadDirectory;
  List<SearchItem> Function(String)? searchResults;
  final keywords = <String>[];

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    searches++;
    keywords.add(keyword);
    return PluginSearchResponse(
      pluginName: name,
      data:
          searchResults?.call(keyword) ??
          [SearchItem(name: _title, src: '/$name/work')],
    );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    directories++;
    directoryTokens.add(cancelToken);
    return loadDirectory == null ? _roads() : await loadDirectory!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'normal no-result exceptions are not reported as a network failure',
    () async {
      final plugin = _DirectoryPlugin('normal-empty')
        ..searchResults = (_) => throw const NoResultException('normal-empty');
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], contains('未匹配'));
    },
  );

  test(
    'metadata refresh cancels an older request and rejects its late directory',
    () async {
      final old = Completer<List<Road>>();
      final plugin = _DirectoryPlugin('metadata-late')
        ..loadDirectory = () => old.future;
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);
      final pending = session.prepare(plugin);
      await Future<void>.delayed(Duration.zero);
      plugin.loadDirectory = () async => [
        Road(id: 'new', name: '新目录', data: ['/new'], identifier: ['第14集']),
      ];
      session.updateWork(_work()..alias = ['新增别名']);
      await Future<void>.delayed(Duration.zero);
      expect(plugin.directoryTokens.first!.isCancelled, isTrue);
      expect(session.entries[plugin.providerId]!.single.roads.single.id, 'new');
      old.complete(_roads());
      await pending;
      expect(session.entries[plugin.providerId]!.single.roads.single.id, 'new');
      expect(session.loading, isEmpty);
    },
  );

  test('explicit retry refreshes a previously successful directory', () async {
    final plugin = _DirectoryPlugin('refresh-directory');
    final session = AnimeSourceSession(_work(), candidates: SourceCandidates());
    addTearDown(session.dispose);
    await session.prepare(plugin);
    plugin.loadDirectory = () async => [
      Road(id: 'updated', name: '已更新', data: ['/new'], identifier: ['第14集']),
    ];
    await session.prepare(plugin, retry: true);
    expect(plugin.directories, 2);
    expect(
      session.entries[plugin.providerId]!.single.roads.single.id,
      'updated',
    );
  });

  test(
    'alias search is bounded, deduplicated and cancelled before sending requests',
    () async {
      final candidates = SourceCandidates();
      final work = _work()
        ..alias = [_title, '合法别名一', '合法别名二', '合法别名三', '合法别名四'];
      final plugin = _DirectoryPlugin('bounded-alias')
        ..searchResults = (_) => [];
      final cancel = RuleCancelToken()..cancel();
      expect(
        await candidates.searchMatches(work, plugin, cancelToken: cancel),
        isEmpty,
      );
      expect(plugin.searches, 0);
      await candidates.searchMatches(work, plugin);
      expect(plugin.keywords, hasLength(4));
      expect(plugin.keywords.toSet(), hasLength(4));
    },
  );

  test(
    'a failed search stays retryable when no alias provides a confirmed match',
    () async {
      final work = _work()..alias = ['另一个合法别名'];
      final plugin = _DirectoryPlugin('failed-alias')
        ..searchResults = (keyword) {
          if (keyword == _title) throw StateError('search unavailable');
          return [];
        };
      final session = AnimeSourceSession(work, candidates: SourceCandidates());
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], contains('重试'));
      expect(plugin.directories, 0);
    },
  );

  test(
    'detail metadata replaces a stale negative match and refreshes the open session',
    () async {
      final thin = _work()
        ..name = 'ONE PIECE'
        ..nameCn = '航海王';
      final full = _work()
        ..name = 'ONE PIECE'
        ..nameCn = '航海王'
        ..alias = ['海贼王'];
      final plugin = _DirectoryPlugin('metadata-refresh')
        ..searchResults = (_) => [SearchItem(name: '海贼王', src: '/main-series')];
      final session = AnimeSourceSession(thin, candidates: SourceCandidates());
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], isNot('ready'));
      session.updateWork(full);
      await Future<void>.delayed(Duration.zero);
      expect(session.work, same(full));
      expect(session.status[plugin.providerId], 'ready');
      expect(
        session.entries[plugin.providerId]!.single.item.src,
        '/main-series',
      );
      final searched = plugin.searches;
      session.updateWork(full);
      await session.prepare(plugin);
      expect(plugin.searches, searched);
    },
  );

  test('metadata refresh preserves a manually confirmed directory', () async {
    final work = _work();
    final plugin = _DirectoryPlugin('metadata-confirmed');
    final session = AnimeSourceSession(work, candidates: SourceCandidates());
    addTearDown(session.dispose);
    await session.prepare(plugin);
    final confirmed = session.entries[plugin.providerId]!.single;
    session.seed(confirmed);
    session.updateWork(_work()..alias = ['新的合法别名']);
    await Future<void>.delayed(Duration.zero);
    expect(session.entries[plugin.providerId]!.single, same(confirmed));
    expect(plugin.searches, 1);
  });

  test(
    'duplicate search references do not turn a unique work into an ambiguity',
    () async {
      final plugin = _DirectoryPlugin('deduplicate-search')
        ..searchResults = (_) => [
          SearchItem(name: _title, src: '/same'),
          SearchItem(name: _title, src: '/same'),
        ];
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], 'ready');
      expect(plugin.directories, 1);
    },
  );

  test('different references with the same title stay ambiguous', () async {
    final plugin = _DirectoryPlugin('ambiguous-search')
      ..searchResults = (_) => [
        SearchItem(name: _title, src: '/one'),
        SearchItem(name: _title, src: '/two'),
      ];
    final session = AnimeSourceSession(_work(), candidates: SourceCandidates());
    addTearDown(session.dispose);
    await session.prepare(plugin);
    expect(session.status[plugin.providerId], contains('歧义'));
    expect(session.entries[plugin.providerId], hasLength(2));
  });

  test(
    'a metadata alias finds the main series when the Chinese title only returns spinoffs',
    () async {
      final work = _work()
        ..name = 'ONE PIECE'
        ..nameCn = '航海王'
        ..alias = ['海贼王'];
      final plugin = _DirectoryPlugin('alias-fallback')
        ..searchResults = (keyword) => keyword == '海贼王'
            ? [SearchItem(name: '海贼王', src: '/main-series')]
            : [
                SearchItem(name: '航海王鱼人岛篇特别编辑版', src: '/special'),
                SearchItem(name: '航海王：红发歌姬', src: '/movie'),
              ];
      final session = AnimeSourceSession(work, candidates: SourceCandidates());
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], 'ready');
      expect(
        session.entries[plugin.providerId]!.single.item.src,
        '/main-series',
      );
      expect(plugin.keywords, contains('海贼王'));
      expect(plugin.directories, 1, reason: '特别编辑版和电影不得加载为正片候选');
    },
  );

  test(
    'automatic discovery uses the same alias fallback as the line sheet',
    () async {
      final work = _work()
        ..name = 'ONE PIECE'
        ..nameCn = '航海王'
        ..alias = ['海贼王'];
      final plugin = _DirectoryPlugin('automatic-alias')
        ..searchResults = (keyword) => keyword == '海贼王'
            ? [SearchItem(name: '海贼王', src: '/main-series')]
            : [];
      final found = await SourceCandidates().discover(work, [
        plugin,
      ], RuleCancelToken());
      expect(found, hasLength(1));
      expect(found.single.item.src, '/main-series');
    },
  );

  test(
    'a manually inspected unrelated directory never becomes an automatic match',
    () async {
      final work = _work();
      final plugin = _DirectoryPlugin('unmatched-cache')
        ..searchResults = (_) => [];
      final candidates = SourceCandidates();
      await candidates.prepare(work, plugin, [
        SearchItem(name: '完全不同的作品', src: '/unrelated'),
      ], allowUnmatched: true);
      final session = AnimeSourceSession(work, candidates: candidates);
      addTearDown(session.dispose);
      await session.prepare(plugin);
      expect(session.status[plugin.providerId], isNot('ready'));
      expect(session.entries[plugin.providerId], isEmpty);
    },
  );

  test(
    'page session reuses prepared directories when the sheet reopens',
    () async {
      final plugin = _DirectoryPlugin('session-reopen');
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);

      await session.prepare(plugin);
      final first = session.entries[plugin.providerId]!.single;
      await session.prepare(plugin);
      await session.prepare(plugin);

      expect(session.status[plugin.providerId], 'ready');
      expect(session.entries[plugin.providerId]!.single, same(first));
      expect(plugin.searches, 1);
      expect(plugin.directories, 1);
      expect(session.loading, isEmpty);
    },
  );

  test(
    'reopening while a directory is pending does not duplicate requests',
    () async {
      final plugin = _DirectoryPlugin('session-pending');
      final ready = Completer<List<Road>>();
      plugin.loadDirectory = () => ready.future;
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);

      final pending = session.prepare(plugin);
      await Future<void>.delayed(Duration.zero);
      try {
        expect(session.loading, contains(plugin.providerId));
        await session.prepare(plugin);
        await session.prepare(plugin, retry: true);
        expect(plugin.searches, 1);
        expect(plugin.directories, 1);
      } finally {
        ready.complete(_roads());
        await pending;
      }

      expect(session.status[plugin.providerId], 'ready');
      expect(session.loading, isEmpty);
    },
  );

  test(
    'a new page reuses the supplied candidate cache without searching again',
    () async {
      final plugin = _DirectoryPlugin('session-cache');
      final work = _work();
      final candidates = SourceCandidates();
      final cached = await candidates.prepare(work, plugin, [
        SearchItem(name: _title, src: '/known-work'),
      ]);
      final session = AnimeSourceSession(work, candidates: candidates);
      addTearDown(session.dispose);

      await session.prepare(plugin);

      expect(session.status[plugin.providerId], 'ready');
      expect(
        session.entries[plugin.providerId]!.single.item.src,
        '/known-work',
      );
      expect(
        session.entries[plugin.providerId]!.single.roads,
        cached.single.roads,
      );
      expect(plugin.searches, 0);
      expect(plugin.directories, 1);
    },
  );

  test(
    'directory failure stays retryable and an explicit retry loads it again',
    () async {
      final plugin = _DirectoryPlugin('session-retry');
      plugin.loadDirectory = () async {
        if (plugin.directories == 1) throw StateError('directory unavailable');
        return _roads();
      };
      final session = AnimeSourceSession(
        _work(),
        candidates: SourceCandidates(),
      );
      addTearDown(session.dispose);

      await session.prepare(plugin);
      expect(session.status[plugin.providerId], contains('重试'));
      expect(session.entries[plugin.providerId], isNull);
      expect(session.loading, isEmpty);
      await session.prepare(plugin);
      expect(plugin.directories, 1);

      await session.prepare(plugin, retry: true);

      expect(plugin.searches, 2);
      expect(plugin.directories, 2);
      expect(session.status[plugin.providerId], 'ready');
      expect(session.entries[plugin.providerId]!.single.roads.single.id, '2');
      expect(session.loading, isEmpty);
    },
  );

  test(
    'disposing cancels pending work and late directories cannot publish or cache',
    () async {
      final plugin = _DirectoryPlugin('session-dispose');
      final ready = Completer<List<Road>>();
      plugin.loadDirectory = () => ready.future;
      final work = _work();
      final candidates = SourceCandidates();
      final session = AnimeSourceSession(work, candidates: candidates);
      var notifications = 0;
      session.addListener(() => notifications++);
      final pending = session.prepare(plugin);
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      session.dispose();

      // 模拟不响应取消的底层请求仍然返回；页面与共享目录都不能接受迟到结果。
      ready.complete(_roads());
      await pending;

      expect(plugin.directoryTokens.single?.isCancelled, isTrue);
      expect(notifications, beforeDispose);
      expect(session.entries, isEmpty);
      expect(session.status, isEmpty);
      expect(candidates.cached(work, [plugin]), isEmpty);
      await session.prepare(plugin, retry: true);
      expect(plugin.searches, 1);
      expect(plugin.directories, 1);
    },
  );

  test(
    'a confirmed seed survives an older pending directory response',
    () async {
      final plugin = _DirectoryPlugin('session-confirmed');
      final ready = Completer<List<Road>>();
      plugin.loadDirectory = () => ready.future;
      final work = _work();
      final candidates = SourceCandidates();
      final session = AnimeSourceSession(work, candidates: candidates);
      addTearDown(session.dispose);
      final pending = session.prepare(plugin);
      await Future<void>.delayed(Duration.zero);
      final confirmed = PlaybackCandidate(
        plugin: plugin,
        item: SearchItem(name: _title, src: '/manually-confirmed-work'),
        roads: [
          Road(
            id: 'confirmed-road',
            name: '确认线路',
            data: ['/confirmed-episode'],
            identifier: ['第14集'],
          ),
        ],
        matched: true,
      );

      session.seed(confirmed);
      try {
        expect(plugin.directoryTokens.single?.isCancelled, isTrue);
        expect(session.loading, isEmpty);
        expect(session.entries[plugin.providerId]!.single, same(confirmed));
      } finally {
        // 旧目录故意忽略取消并返回，必须保持用户刚确认的作品和线路。
        ready.complete(_roads());
        await pending;
      }

      expect(session.status[plugin.providerId], 'ready');
      expect(session.entries[plugin.providerId]!.single, same(confirmed));
      expect(session.loading, isEmpty);
      expect(candidates.cached(work, [plugin]), isEmpty);
      await session.prepare(plugin);
      expect(plugin.searches, 1);
      expect(plugin.directories, 1);
    },
  );

  test(
    'filtered candidates preserve upstream road 2 instead of renumbering it',
    () async {
      final plugin = _DirectoryPlugin('session-road-id');
      plugin.loadDirectory = () async => [
        Road(id: '1', name: '空线路', data: [''], identifier: ['第14集']),
        ..._roads(),
      ];
      final work = _work();
      final session = AnimeSourceSession(work, candidates: SourceCandidates());
      addTearDown(session.dispose);

      await session.prepare(plugin);

      final candidate = session.entries[plugin.providerId]!.single;
      expect(candidate.roads, hasLength(1));
      expect(candidate.roads.single.id, '2');
      expect(candidate.args(work).roads.single.id, '2');
      expect(candidate.matchEpisode(14), (road: 0, episode: 1));
      expect(candidate.roads.single.data, ['opaque-title/road-2/episode-14']);
    },
  );
}
