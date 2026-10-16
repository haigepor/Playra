import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/player/sdk_rank_section.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';

Map<String, dynamic> anime(List<String> ids) => {
  'data': {
    'videos': [
      for (final id in ids) {'id': id, 'title': '动漫$id'},
    ],
  },
};
Map<String, dynamic> media(
  String category,
  List<String> ids, {
  String categoryName = '电影大全',
}) => {
  'data': {
    'categoryId': category,
    'list': [
      {
        'id': 'MOD_818368',
        'name': '来源热播榜',
        'items': [
          for (final id in ids)
            {
              'id': id,
              'title': '电影$id',
              'categoryName': categoryName,
              'categoryId': category,
            },
        ],
      },
    ],
  },
};

void main() {
  test(
    'mixed recommendation uses explicit movie and series ranks even when global rank is all anime',
    () async {
      final calls = <String>[];
      final lumina = LuminaService(
        request: (_, _, _) async => anime(['101', '102']),
      );
      final mio = MioMediaService(
        request: (_, payload, _) async {
          final category = payload['categoryId'] as String;
          calls.add(category);
          return switch (category) {
            '42' => media(category, ['201', '202']),
            '43' => media(category, ['301'], categoryName: '剧集大全'),
            _ => media(category, ['999'], categoryName: '日本动漫'),
          };
        },
      );
      final controller = SdkRankController(lumina: lumina, mio: mio);
      addTearDown(() {
        controller.dispose();
        lumina.dispose();
        mio.dispose();
      });
      await controller.load(
        luminaChannelId: '1',
        mioCategoryIds: ['43', '0', '42', '42'],
      );
      expect(calls, ['42', '43']);
      expect(controller.entries.take(3).map((e) => e.video.categoryName), [
        '动漫',
        '电影大全',
        '剧集大全',
      ]);
      expect(controller.entries.take(3).map((e) => e.sourcePosition), [
        1,
        1,
        1,
      ]);
      expect(
        controller.entries
            .where((e) => e.providerId == 'miomedia')
            .map((e) => e.video.id),
        ['201', '301', '202'],
      );
    },
  );

  test(
    'one explicit cinema category failure retains the other and metadata arriving later enables new scope',
    () async {
      final calls = <String>[];
      final mio = MioMediaService(
        request: (_, payload, _) async {
          final category = payload['categoryId'] as String;
          calls.add(category);
          if (category == '42') throw StateError('offline');
          return media(category, ['301'], categoryName: '剧集大全');
        },
      );
      final controller = SdkRankController(mio: mio);
      addTearDown(() {
        controller.dispose();
        mio.dispose();
      });
      await controller.load(mioCategoryIds: []);
      expect(calls, isEmpty, reason: '分类元数据未到时不能退回全站0榜');
      await controller.load(mioCategoryIds: ['42', '43']);
      expect(calls, ['42', '43']);
      expect(controller.entries.single.video.id, '301');
      expect(controller.failed, contains('miomedia:42'));
      expect(controller.entries.single.sourceCategoryId, '43');
    },
  );

  test(
    'screen categories reject anime and foreign category metadata while retaining original rank position',
    () async {
      final data = media('42', ['201', '202', '203']);
      final items =
          (((data['data'] as Map)['list'] as List).single as Map)['items']
              as List;
      (items[0] as Map)['categoryName'] = '国产动漫';
      (items[1] as Map)['categoryId'] = '99';
      final mio = MioMediaService(request: (_, _, _) async => data);
      final controller = SdkRankController(mio: mio);
      addTearDown(() {
        controller.dispose();
        mio.dispose();
      });
      await controller.load(mioCategoryIds: ['42']);
      expect(controller.entries.single.video.id, '203');
      expect(controller.entries.single.sourcePosition, 3);
    },
  );

  test(
    'single explicit anime category remains available without Lumina and across scope mode changes',
    () async {
      for (final categoryName in ['日本动漫', '国产动漫', '动漫电影']) {
        final calls = <String>[];
        final mio = MioMediaService(
          request: (_, payload, _) async {
            final category = payload['categoryId'] as String;
            calls.add(category);
            return media(category, ['101', '102'], categoryName: categoryName);
          },
        );
        final controller = SdkRankController(mio: mio);
        addTearDown(() {
          controller.dispose();
          mio.dispose();
        });
        await controller.load(mioCategoryId: '44');
        expect(controller.entries.map((entry) => entry.identity), [
          'miomedia:101',
          'miomedia:102',
        ]);
        expect(controller.entries.map((entry) => entry.sourcePosition), [1, 2]);
        for (final entry in controller.entries) {
          expect(entry.sourceCategoryId, '44');
          expect(entry.video.categoryName, categoryName);
          final source = entry.playbackEntry.sources.single;
          expect(source.provider.id, 'miomedia');
          expect(source.contentId, entry.video.id);
          expect(entry.playbackEntry.autoPlay, isFalse);
        }
        await controller.load(mioCategoryIds: ['44']);
        expect(controller.entries, isEmpty);
        await controller.load(mioCategoryId: '44');
        expect(controller.entries.map((entry) => entry.identity), [
          'miomedia:101',
          'miomedia:102',
        ]);
        expect(calls, ['44', '44', '44']);
        expect(controller.failed, isEmpty);
        expect(controller.loading, isEmpty);
      }
    },
  );

  test(
    'removed cinema scope cannot publish late results or clear another scope state',
    () async {
      final pending = <String, Completer<Map<String, dynamic>>>{};
      final mio = MioMediaService(
        request: (_, payload, _) {
          final id = payload['categoryId'] as String;
          return (pending[id] = Completer<Map<String, dynamic>>()).future;
        },
      );
      final controller = SdkRankController(mio: mio);
      addTearDown(() {
        controller.dispose();
        mio.dispose();
      });
      final old = controller.load(mioCategoryIds: ['42']);
      final newer = controller.load(mioCategoryIds: ['43']);
      pending['43']!.complete(media('43', ['301'], categoryName: '剧集大全'));
      await newer;
      pending['42']!.complete(media('42', ['201']));
      await old;
      expect(controller.entries.single.identity, 'miomedia:301');
      expect(controller.entries.single.sourceCategoryId, '43');
      expect(controller.loading, isEmpty);
      expect(controller.failed, isEmpty);
    },
  );

  test(
    'upcoming placeholders are excluded without renumbering source positions',
    () async {
      final lumina = LuminaService(
        request: (_, _, _) async => {
          'data': {
            'videos': [
              {'id': '901', 'title': '未开播', 'updatedTo': 0, 'isEnd': false},
              {'id': '902', 'title': '更新未知'},
              {'id': '903', 'title': '已完结', 'updatedTo': 0, 'isEnd': true},
              {'id': '904', 'title': '连载中', 'updatedTo': 2},
            ],
          },
        },
      );
      final controller = SdkRankController(lumina: lumina);
      addTearDown(() {
        controller.dispose();
        lumina.dispose();
      });
      await controller.load(luminaChannelId: '1', mioCategoryId: null);
      expect(controller.entries.map((entry) => entry.video.id), [
        '902',
        '903',
        '904',
      ]);
      expect(controller.entries.map((entry) => entry.sourcePosition), [
        2,
        3,
        4,
      ]);
      expect(controller.entries.map((entry) => entry.position), [1, 2, 3]);
    },
  );

  test(
    'two SDKs retain identity and source order without claiming a seven day window',
    () async {
      final lumina = LuminaService(
        request: (op, payload, _) async {
          expect(op, 'catalog');
          expect(payload['sort'], 'weight');
          return anime(['101', '101', '102']);
        },
      );
      final mio = MioMediaService(
        request: (_, payload, _) async =>
            media(payload['categoryId'] as String, ['101', '103']),
      );
      final controller = SdkRankController(lumina: lumina, mio: mio);
      addTearDown(() {
        controller.dispose();
        lumina.dispose();
        mio.dispose();
      });
      await controller.load(luminaChannelId: '1', mioCategoryId: '42');
      expect(controller.entries.map((e) => e.identity), [
        'lumina:101',
        'miomedia:101',
        'lumina:102',
        'miomedia:103',
      ]);
      expect(controller.entries.map((e) => e.position), [1, 2, 3, 4]);
      expect(controller.entries.map((e) => e.sourcePosition), [1, 1, 3, 2]);
      expect(controller.entries.every((e) => e.window == null), isTrue);
      for (final entry in controller.entries) {
        expect(
          entry.playbackEntry.sources.single.provider.id,
          entry.providerId,
        );
        expect(entry.playbackEntry.sources.single.contentId, entry.video.id);
      }
    },
  );

  test(
    'a fast SDK renders while the other waits and one failure keeps usable data',
    () async {
      final slow = Completer<Map<String, dynamic>>();
      final lumina = LuminaService(request: (_, _, _) async => anime(['201']));
      final mio = MioMediaService(request: (_, _, _) => slow.future);
      final controller = SdkRankController(lumina: lumina, mio: mio);
      addTearDown(() {
        controller.dispose();
        lumina.dispose();
        mio.dispose();
      });
      final pending = controller.load(
        luminaChannelId: '1',
        mioCategoryId: '42',
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.entries.single.identity, 'lumina:201');
      expect(controller.loading, contains('miomedia'));
      slow.completeError(Exception('offline'));
      await pending;
      expect(controller.failed, contains('miomedia'));
      expect(controller.entries.single.identity, 'lumina:201');
    },
  );

  test(
    'same scope requests are deduplicated and changing one scope leaves the other cached',
    () async {
      final calls = <String>[];
      final lumina = LuminaService(
        request: (_, payload, _) async {
          calls.add('lumina:${payload['channelId']}');
          return anime(['201']);
        },
      );
      final mio = MioMediaService(
        request: (_, payload, _) async {
          calls.add('miomedia:${payload['categoryId']}');
          return media(payload['categoryId'] as String, ['301']);
        },
      );
      final controller = SdkRankController(lumina: lumina, mio: mio);
      addTearDown(() {
        controller.dispose();
        lumina.dispose();
        mio.dispose();
      });
      await Future.wait([
        controller.load(luminaChannelId: '1', mioCategoryId: '42'),
        controller.load(luminaChannelId: '1', mioCategoryId: '42'),
      ]);
      expect(calls, ['lumina:1', 'miomedia:42']);
      await controller.load(luminaChannelId: '2', mioCategoryId: '42');
      expect(calls, ['lumina:1', 'miomedia:42', 'lumina:2']);
    },
  );

  test(
    'late old refresh cannot overwrite newer results and refresh failure retains cache',
    () async {
      final requests = <Completer<Map<String, dynamic>>>[];
      final mio = MioMediaService(
        request: (_, _, _) {
          final value = Completer<Map<String, dynamic>>();
          requests.add(value);
          return value.future;
        },
      );
      final controller = SdkRankController(mio: mio);
      addTearDown(() {
        controller.dispose();
        mio.dispose();
      });
      final old = controller.load(mioCategoryId: '42');
      final current = controller.load(mioCategoryId: '42', refresh: true);
      requests[1].complete(media('42', ['302']));
      await current;
      requests[0].complete(media('42', ['301']));
      await old;
      expect(controller.entries.single.identity, 'miomedia:302');
      final failed = controller.load(mioCategoryId: '42', refresh: true);
      requests[2].completeError(Exception('offline'));
      await failed;
      expect(controller.entries.single.identity, 'miomedia:302');
      expect(controller.failed, contains('miomedia'));
    },
  );

  testWidgets(
    'combined posters keep both provider identities and original layout at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lumina = LuminaService(request: (_, _, _) async => anime(['101']));
      final mio = MioMediaService(
        request: (_, payload, _) async =>
            media(payload['categoryId'] as String, ['101']),
      );
      final controller = SdkRankController(lumina: lumina, mio: mio);
      await controller.load(luminaChannelId: '1', mioCategoryId: '42');
      SdkPlaybackEntry? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ModernHomeScope(
            child: Scaffold(
              body: SdkRankSection(
                controller: controller,
                onDetails: (entry) => selected = entry,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('热播推荐'), findsOneWidget);
      expect(find.textContaining('7天'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sdk-poster-lumina:101')));
      expect(selected!.sources.single.provider.id, 'lumina');
      expect(selected!.sources.single.contentId, '101');
      expect(selected!.autoPlay, isFalse);
      await tester.drag(
        find.byKey(const PageStorageKey('sdk-rank')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sdk-poster-miomedia:101')));
      expect(selected!.sources.single.provider.id, 'miomedia');
      expect(selected!.sources.single.contentId, '101');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      lumina.dispose();
      mio.dispose();
    },
  );
}
