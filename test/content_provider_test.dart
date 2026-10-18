import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/source_policy.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Mio anime is classified as anime and offered only as a low priority fallback',
    () async {
      final provider = MioContentProvider(
        MioMediaService(
          request: (_, _, _) async => {
            'data': {
              'videos': [
                {'id': '42', 'title': '动画', 'categoryName': '日本动漫'},
                {'id': '43', 'title': '真人电影', 'categoryName': '电影大全'},
              ],
            },
          },
        ),
      );
      addTearDown(provider.dispose);
      expect(provider.groups, contains(ContentGroup.anime));
      expect(provider.priority, lessThan(0));
      final result = await provider.search(
        const ContentQuery('作品', group: ContentGroup.anime),
        1,
        CancelToken(),
      );
      expect(result.items.map((hit) => hit.contentId), ['42']);
      expect(result.items.single.group, ContentGroup.anime);
    },
  );
  test(
    'first-use registry loads sixteen official anime rules without installation',
    () async {
      final providers = await loadContentProviders(const []);
      addTearDown(() {
        for (final p in providers) {
          p.dispose();
        }
      });
      final rules = providers.whereType<RuleContentProvider>().toList();
      expect(rules, hasLength(16));
      expect(rules.map((p) => p.id).toSet(), {
        'dm84',
        'mxdm',
        'akianime',
        'moonci',
        '7sefun',
        'aafun',
        'age',
        'baimao',
        'dalvdm',
        'ezdmw',
        'girigirilove',
        'mgnacg',
        'mutefun',
        'sorani',
        'xfdmneo',
        'xfdmnext',
      });
      expect(
        rules.every(
          (p) => p.groups.length == 1 && p.groups.contains(ContentGroup.anime),
        ),
        isTrue,
      );
      final disabled = Plugin.fromJson({
        'name': '手动关闭',
        'type': 'anime',
        'enabled': false,
      });
      await SourcePolicy.shared.configure(disabled.providerId, enabled: false);
      addTearDown(
        () => SourcePolicy.shared.configure(disabled.providerId, enabled: true),
      );
      final filtered = await loadContentProviders([disabled]);
      addTearDown(() {
        for (final p in filtered) {
          p.dispose();
        }
      });
      expect(filtered.whereType<RuleContentProvider>(), isEmpty);
    },
  );
  test(
    'SDK classification routes all live series while anime rules remain anime only',
    () {
      final rule = RuleContentProvider(
        Plugin.fromJson({'name': '动漫规则', 'type': 'anime', 'api': '8'}),
      );
      expect(rule.groups, {ContentGroup.anime});
      final sdk = MioContentProvider(
        MioMediaService(request: (_, _, _) async => {'data': {}}),
      );
      expect(
        sdk.groups,
        containsAll([
          ContentGroup.screen,
          ContentGroup.series,
          ContentGroup.comicDrama,
        ]),
      );
      final registered = contentProviders([
        Plugin.fromJson({'name': '关闭', 'type': 'unknown'}),
      ], includeMetadata: false);
      expect(registered.length, 1);
      for (final p in registered) {
        p.dispose();
      }
      sdk.dispose();
    },
  );
  test(
    'SDK keeps long string IDs and filters classification without using the title',
    () async {
      final provider = MioContentProvider(
        MioMediaService(
          request: (_, _, _) async => {
            'data': {
              'videos': [
                {
                  'id': '9007199254740993',
                  'title': '动漫标题的真人日剧',
                  'categoryName': '日剧',
                },
                {'id': '2', 'title': '电影', 'categoryName': '电影大全'},
              ],
            },
          },
        ),
      );
      addTearDown(provider.dispose);
      final page = await provider.search(
        const ContentQuery('作品', group: ContentGroup.series),
        1,
        CancelToken(),
      );
      expect(page.items.map((h) => h.contentId), ['9007199254740993']);
      expect(page.items.single.group, ContentGroup.series);
      expect(provider.entry(page.items.single)?.id, '9007199254740993');
      expect(
        provider.entry(
          const ContentHit(
            providerId: 'other',
            contentId: '9007199254740993',
            title: '错来源',
            group: ContentGroup.series,
          ),
        ),
        isNull,
      );
    },
  );
}
