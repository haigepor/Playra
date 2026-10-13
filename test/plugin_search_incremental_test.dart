import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'publishes a search hit before its slow episode directory finishes',
    () async {
      final plugin = _ControlledPlugin('early');
      final fixture = _Fixture([plugin]);
      final directory = plugin.directory('/early');
      final batch = fixture.service.queryAllSource('Example');
      plugin.search('Example').complete(_response(plugin, '/early'));
      await _flush();

      try {
        expect(directory.isCompleted, isFalse);
        expect(fixture.paths, ['/early']);
        expect(
          fixture.info.pluginSearchStatus[plugin.name],
          PluginSearchStatus.success,
        );
      } finally {
        plugin.finish();
        await batch;
      }
    },
  );

  test(
    'a fifth source can publish while four episode directories are pending',
    () async {
      final plugins = List.generate(
        5,
        (index) => _ControlledPlugin('slot$index'),
      );
      final fixture = _Fixture(plugins);
      for (var index = 0; index < plugins.length; index++) {
        plugins[index].directory('/slot$index');
        plugins[index]
            .search('Example')
            .complete(_response(plugins[index], '/slot$index'));
      }
      final batch = fixture.service.queryAllSource('Example');
      await _flush();

      try {
        expect(
          plugins.take(4).every((p) => !p.directory('/${p.name}').isCompleted),
          isTrue,
        );
        expect(fixture.paths, contains('/slot4'));
      } finally {
        for (final plugin in plugins) {
          plugin.finish();
        }
        await batch;
      }
    },
  );

  test(
    'a replacement batch ignores an old search response arriving late',
    () async {
      final plugin = _ControlledPlugin('replace-search');
      final fixture = _Fixture([plugin]);
      final oldBatch = fixture.service.queryAllSource('old');
      final newBatch = fixture.service.queryAllSource('new');
      plugin.search('new').complete(_response(plugin, '/new'));
      plugin.directory('/new').complete(_roads);
      await newBatch;

      plugin.search('old').complete(_response(plugin, '/old'));
      plugin.directory('/old').complete(_roads);
      await oldBatch;

      expect(fixture.paths, ['/new']);
      expect(
        fixture.info.pluginSearchStatus[plugin.name],
        PluginSearchStatus.success,
      );
    },
  );

  test(
    'a replacement batch ignores an old episode directory arriving late',
    () async {
      final plugin = _ControlledPlugin('replace-directory');
      final fixture = _Fixture([plugin]);
      plugin.search('old').complete(_response(plugin, '/old'));
      final oldBatch = fixture.service.queryAllSource('old');
      await _flush();

      final newBatch = fixture.service.queryAllSource('new');
      plugin.search('new').complete(_response(plugin, '/new'));
      plugin.directory('/new').complete(_roads);
      await newBatch;
      plugin.directory('/old').complete(_roads);
      await oldBatch;
      await _flush();

      expect(fixture.paths, ['/new']);
      expect(
        fixture.info.pluginSearchStatus[plugin.name],
        PluginSearchStatus.success,
      );
    },
  );

  test('cancelled search does not publish a late response', () async {
    final plugin = _ControlledPlugin('cancel-search');
    final fixture = _Fixture([plugin]);
    final batch = fixture.service.queryAllSource('Example');
    fixture.service.cancel();
    plugin.search('Example').complete(_response(plugin, '/cancelled'));
    plugin.directory('/cancelled').complete(_roads);
    await batch;

    expect(fixture.paths, isEmpty);
    expect(
      fixture.info.pluginSearchStatus[plugin.name],
      isNot(PluginSearchStatus.success),
    );
  });

  test(
    'cancelled preparation cannot change already published results',
    () async {
      final plugin = _ControlledPlugin('cancel-directory');
      final fixture = _Fixture([plugin]);
      plugin.search('Example').complete(_response(plugin, '/candidate'));
      final batch = fixture.service.queryAllSource('Example');
      await _flush();
      fixture.service.cancel();
      final before = fixture.paths;
      final statusBefore = fixture.info.pluginSearchStatus[plugin.name];
      plugin.directory('/candidate').complete(_roads);
      await batch;
      await _flush();

      expect(fixture.paths, before);
      expect(fixture.info.pluginSearchStatus[plugin.name], statusBefore);
    },
  );
}

Future<void> _flush() async {
  // Yield to the event queue so all already-ready asynchronous work runs.
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Road> get _roads => [
  Road(name: 'Main', data: ['/episode-1'], identifier: ['1']),
];

PluginSearchResponse _response(Plugin plugin, String path) =>
    PluginSearchResponse(
      pluginName: plugin.name,
      data: [SearchItem(name: 'Example', src: path)],
    );

class _Fixture {
  _Fixture(List<Plugin> plugins) {
    info.bangumiItem = BangumiItem(
      id: _nextWorkId++,
      type: 2,
      name: 'Example',
      nameCn: '',
      summary: '',
      airDate: '',
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
    final controller = PluginsController()..pluginList.addAll(plugins);
    service = PluginSearchService(
      infoController: info,
      pluginsController: controller,
    );
  }

  static int _nextWorkId = 900000;
  final info = InfoController(CollectController(_UnusedCollectRepository()));
  late final PluginSearchService service;
  List<String> get paths => info.pluginSearchResponseList
      .expand((response) => response.data)
      .map((item) => item.src)
      .toList();
}

class _UnusedCollectRepository implements ICollectCrudRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Search must not access collection storage');
}

class _ControlledPlugin extends Plugin {
  _ControlledPlugin(String name)
    : super(
        api: '1',
        type: 'anime',
        name: name,
        version: '1',
        sourceId: 'test.incremental.$name',
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

  final _searches = <String, Completer<PluginSearchResponse>>{};
  final _directories = <String, Completer<List<Road>>>{};

  Completer<PluginSearchResponse> search(String keyword) =>
      _searches.putIfAbsent(keyword, Completer<PluginSearchResponse>.new);
  Completer<List<Road>> directory(String path) =>
      _directories.putIfAbsent(path, Completer<List<Road>>.new);

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) => search(keyword).future;

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) => directory(source).future;

  void finish() {
    for (final pending in _searches.values) {
      if (!pending.isCompleted) {
        pending.complete(PluginSearchResponse(pluginName: name, data: []));
      }
    }
    for (final pending in _directories.values) {
      if (!pending.isCompleted) pending.complete(_roads);
    }
  }
}
