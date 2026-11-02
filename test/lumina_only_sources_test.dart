import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/clients/trace_client.dart';
import 'package:kazumi/request/clients/rules_repo_client.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/lumina/lumina_content_provider.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/source_models.dart';

final removed = isA<SourceException>().having(
  (e) => e.code,
  'code',
  'SOURCE_REMOVED',
);

void main() {
  test(
    'default registry never adds another source on unsupported platforms',
    () {
      final providers = contentProviders();
      addTearDown(() {
        for (final provider in providers) {
          provider.dispose();
        }
      });
      expect(
        providers.map((p) => p.id),
        luminaSupported ? ['lumina'] : isEmpty,
      );
    },
  );

  test('retired clients reject before issuing any HTTP request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/retired';
    for (final request in <Future<dynamic> Function()>[
      () => BangumiClient.instance.get(url),
      () => BangumiClient.instance.post(url),
      () => DanmakuClient.instance.get(url),
      () => TraceClient.instance.post(url),
      () => RulesRepoClient.instance.getText(url),
      () => PluginSiteClient.instance.requestText(url, method: 'GET'),
    ]) {
      await expectLater(request(), throwsA(removed));
    }
    await expectLater(BangumiApi.getCalendar(), throwsA(removed));
    await expectLater(DanmakuApi.searchAnimes('作品'), throwsA(removed));
    expect(requests, 0);
  });

  test('Lumina search keeps its real provider and content identity', () async {
    final service = LuminaService(
      request: (operation, payload, cancel) async => {
        'data': {
          'videos': [
            {'id': '42', 'title': 'Lumina作品'},
          ],
          'pageInfo': {'total': 1},
        },
      },
    );
    final session = ContentSearchSession([LuminaContentProvider(service)]);
    addTearDown(session.dispose);
    await session.submit(const ContentQuery('Lumina作品'));
    expect(session.works.single.primary.providerId, 'lumina');
    expect(session.works.single.primary.contentId, '42');
  });

  testWidgets(
    'homepage never renders the old metadata fallback, then recovers Lumina',
    (tester) async {
      var available = false;
      final service = LuminaService(
        request: (operation, payload, cancel) async {
          if (!available) throw StateError('unavailable');
          return {
            'data': switch (operation) {
              'channels' => {
                'channels': [
                  {'id': '1', 'name': '动漫'},
                ],
              },
              'banners' => {'banners': []},
              _ => {
                'videos': [
                  {'id': '42', 'title': 'Lumina恢复作品'},
                ],
                'pageInfo': {'total': 1},
              },
            },
          };
        },
      );
      final anime = LuminaHomeController(service);
      final controller = ModernHomeController(
        readHistory: () => [],
        loadFeed: (_, _) async => [
          BangumiItem(
            id: 99,
            type: 2,
            name: '旧来源卡片',
            nameCn: '旧来源卡片',
            summary: '',
            airDate: '',
            airWeekday: 0,
            rank: 0,
            images: {},
            tags: [],
            alias: [],
            ratingScore: 9,
            votes: 0,
            votesCount: [],
            info: '',
          ),
        ],
      );
      addTearDown(anime.dispose);
      addTearDown(service.dispose);
      addTearDown(controller.dispose);
      await anime.bootstrap();
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeView(
            controller: controller,
            anime: anime,
            onAnimeDetails: (_) {},
            onSearch: () {},
            onCalendar: () {},
            onBrowse: (_) {},
            onHistory: () {},
            onToggleTheme: () {},
            onDetails: (_) {},
            onResume: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧来源卡片'), findsNothing);
      expect(find.text('Lumina 暂无可展示的内容'), findsOneWidget);
      available = true;
      await anime.bootstrap(force: true);
      await tester.pumpAndSettle();
      expect(find.text('Lumina恢复作品'), findsWidgets);
      expect(find.text('旧来源卡片'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retired entry explains unavailable source without starting a loader',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SourceUnavailablePage(feature: '放送日历')),
      );
      expect(find.text('当前仅保留 Lumina 数据源'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
