import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

void main() {
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
      expect(
        contentProviders([
          Plugin.fromJson({'name': '关闭', 'type': 'unknown'}),
        ], includeMetadata: false).length,
        1,
      );
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
    },
  );
}
