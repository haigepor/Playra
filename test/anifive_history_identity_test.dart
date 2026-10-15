import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/playback_identity.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';

BangumiItem subject([int id = 42]) => BangumiItem.fromJson({
  'id': id,
  'name': '测试动漫',
  'rating': <String, dynamic>{},
  'images': <String, dynamic>{},
});

Plugin moonci({
  String name = 'moonci',
  String sourceId = 'moonci',
  String baseUrl = 'https://www.moonci.com/',
  bool managed = true,
}) => Plugin.fromJson({
  'api': '8',
  'type': 'anime',
  'name': name,
  'sourceId': sourceId,
  'baseURL': baseUrl,
  if (managed) ...{
    'searchMode': 'api',
    'searchApiConfig': {
      'request': {
        'method': 'GET',
        'url':
            'https://source-runtime.playra.invalid/v1/adapters/anifive-d/search',
      },
    },
    'sourceConfig': {'managedBy': 'playra-anifive'},
  },
});

Road road(List<String> urls, {String name = '线路 2'}) => Road(
  name: name,
  data: urls,
  identifier: List.generate(urls.length, (index) => '目录位置 ${index + 1}'),
);

OnlineVideoPlaybackArgs playback(
  Plugin plugin, {
  String source = '/anime/42.html',
  List<Road>? roads,
  int bangumiId = 42,
}) => OnlineVideoPlaybackArgs(
  bangumiItem: subject(bangumiId),
  plugin: plugin,
  title: '测试动漫',
  src: source,
  roads: roads ?? [road(['/anime/42/play/2-174.html'])],
);

History watched({
  String adapterName = 'moonci',
  String source = '/anime/42.html',
  String episodeUrl = '/anime/42/play/2-174.html',
  String entryKind = HistoryEntryKind.online,
  int bangumiId = 42,
}) => History(
  subject(bangumiId),
  2,
  adapterName,
  DateTime(2026, 10, 15),
  source,
  '第174集',
  entryKind: entryKind,
  episodePageUrl: episodeUrl,
)..progresses[2] = Progress(2, 2, 65000);

void main() {
  group('AniFive history URL identity', () {
    test('relative history restores against absolute SDK detail and episode URLs', () {
      final result = verifiedResume(
        playback(
          moonci(),
          source: 'https://www.moonci.com/anime/42.html',
          roads: [road(['https://www.moonci.com/anime/42/play/2-174.html'])],
        ),
        [watched()],
      );

      expect(result?.selection.episode, 1);
      expect(result?.selection.road, 0);
      expect(result?.offset, 65);
    });

    test('absolute historical URLs restore against relative current URLs', () {
      final result = verifiedResume(playback(moonci()), [
        watched(
          source: 'https://www.moonci.com/anime/42.html',
          episodeUrl: 'https://www.moonci.com/anime/42/play/2-174.html',
        ),
      ]);

      expect(result?.selection.episode, 1);
      expect(result?.offset, 65);
    });

    test('same-site historical HTTP URLs normalize to the current HTTPS source', () {
      final result = verifiedResume(playback(moonci()), [
        watched(
          source: 'http://www.moonci.com/anime/42.html',
          episodeUrl: 'http://www.moonci.com/anime/42/play/2-174.html',
        ),
      ]);

      expect(result?.selection.episode, 1);
      expect(result?.offset, 65);
    });

    test('removed and reordered roads resume the unique page rather than old indexes', () {
      final result = verifiedResume(
        playback(
          moonci(),
          roads: [
            road([
              '/anime/42/play/2-176.html',
              '/anime/42/play/2-175.html',
              '/anime/42/play/2-174.html',
            ]),
          ],
        ),
        [watched()],
      );

      // 旧目录是第 3 条线路的第 2 项，新目录只有一条线路，目标变成第 3 项。
      expect(result?.selection.road, 0);
      expect(result?.selection.episode, 3);
      expect(result?.offset, 65);
    });

    test('a deleted episode never resumes another page at its former index', () {
      final result = verifiedResume(
        playback(
          moonci(),
          roads: [road(['/anime/42/play/2-173.html', '/anime/42/play/2-175.html'])],
        ),
        [watched()],
      );

      expect(result, isNull);
    });

    test('the same page appearing in two roads is ambiguous', () {
      final result = verifiedResume(
        playback(
          moonci(),
          roads: [
            road(['/anime/42/play/2-174.html'], name: '线路 2'),
            road(['https://www.moonci.com/anime/42/play/2-174.html'], name: '重复线路'),
          ],
        ),
        [watched()],
      );

      expect(result, isNull);
    });

    test('missing episode URLs cannot fall back to labels or numeric indexes', () {
      expect(verifiedResume(playback(moonci()), [watched(episodeUrl: '')]), isNull);
    });

    test('a different Bangumi work or offline history cannot restore online progress', () {
      expect(verifiedResume(playback(moonci()), [watched(bangumiId: 43)]), isNull);
      expect(
        verifiedResume(playback(moonci()), [watched(entryKind: HistoryEntryKind.offline)]),
        isNull,
      );
    });
  });

  group('managed source aliases and custom rule isolation', () {
    test('aafun restores into the managed moonci source on the same site', () {
      for (final alias in ['aafun', 'AAFUN']) {
        final result = verifiedResume(playback(moonci()), [watched(adapterName: alias)]);
        expect(result?.selection.episode, 1, reason: alias);
        expect(result?.offset, 65, reason: alias);
      }
    });

    test('aafun alias survives managed source renaming to avoid a custom rule collision', () {
      final plugin = moonci(name: 'moonci SDK', sourceId: 'anifive-moonci');
      final result = verifiedResume(playback(plugin), [watched(adapterName: 'aafun')]);

      // providerId/显示名因冲突而改变，受管的 anifive-d 路由与原站仍一致。
      expect(result?.selection.episode, 1);
      expect(result?.offset, 65);
    });

    test('original moonci history survives the managed source collision suffix', () {
      final plugin = moonci(name: 'moonci SDK 2', sourceId: 'anifive-moonci-2');
      final result = verifiedResume(playback(plugin), [watched()]);

      expect(result?.selection.episode, 1);
      expect(result?.offset, 65);
    });

    test('an unmanaged custom moonci does not inherit the aafun alias', () {
      final result = verifiedResume(
        playback(moonci(managed: false)),
        [watched(adapterName: 'aafun')],
      );

      expect(result, isNull);
    });

    test('a different source name cannot inherit progress even with identical URLs', () {
      expect(
        verifiedResume(playback(moonci()), [watched(adapterName: 'MXdm')]),
        isNull,
      );
    });

    test('matching names do not make absolute detail or episode URLs cross-site identities', () {
      final plugin = moonci(managed: false, baseUrl: 'https://custom.example/');
      expect(
        verifiedResume(playback(plugin), [
          watched(
            source: 'https://www.moonci.com/anime/42.html',
            episodeUrl: 'https://www.moonci.com/anime/42/play/2-174.html',
          ),
        ]),
        isNull,
      );
      expect(
        verifiedResume(playback(moonci()), [
          watched(episodeUrl: 'https://another.example/anime/42/play/2-174.html'),
        ]),
        isNull,
      );
    });

    test('a same-name custom rule cannot rebind relative built-in history to a new site', () {
      final plugin = moonci(managed: false, baseUrl: 'https://custom.example/');
      final result = verifiedResume(playback(plugin), [watched()]);

      // 历史没有记录原站 origin，不能仅凭同名和同形路径推断跨站身份。
      expect(result, isNull);
    });
  });
}
