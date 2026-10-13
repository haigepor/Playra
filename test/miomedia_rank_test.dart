import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_rank_view.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

Map<String, dynamic> rankData(String category, {String title = '服务端原始榜名'}) => {
  'categoryId': category,
  'list': [
    {
      'id': 'MOD_818368',
      'name': title,
      'k': 'hot',
      'cover': 'v',
      'layout': 'strip',
      'boardTabs': ['热播榜'],
      'items': List.generate(
        12,
        (i) => {
          'id': '${9007199254740993 + i}',
          'title': '作品$i',
          'categoryId': category,
          'categoryName': '电影大全',
          'playCount': i.isEven ? 50 : 9999999,
          'score': 10 - i / 2,
        },
      ),
    },
  ],
};

void main() {
  test(
    'request is one based and preserves title order and exact string IDs',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = MioMediaService(
        request: (op, payload, _) async {
          expect(op, 'hotRank');
          calls.add(payload);
          return {'data': rankData(payload['categoryId'] as String)};
        },
      );
      final rank = (await service.hotRank('42'))!;
      expect(calls.single, {
        'categoryId': '42',
        'pageIndex': 1,
        'pageSize': 20,
      });
      expect(rank.name, '服务端原始榜名');
      expect(
        rank.entries.map((e) => e.position),
        List.generate(10, (i) => i + 1),
      );
      expect(
        rank.entries.map((e) => e.video.id),
        List.generate(10, (i) => '${9007199254740993 + i}'),
      );
      expect(rank.window, isNull);
      expect(rank.metric, isNull);
      expect(rank.boardTabs, ['热播榜']);
      service.dispose();
    },
  );

  test(
    'missing module is empty; malformed or mismatched data is not empty',
    () async {
      var data = <String, dynamic>{'categoryId': '42', 'list': []};
      final service = MioMediaService(
        request: (_, _, _) async => {'data': data},
      );
      expect(await service.hotRank('42'), isNull);
      for (final bad in [
        <String, dynamic>{},
        rankData('0'),
        {
          'categoryId': '42',
          'list': [
            {'id': 'MOD_818368', 'name': '榜', 'items': 'bad'},
          ],
        },
      ]) {
        data = bad;
        await expectLater(service.hotRank('42'), throwsA(anything));
      }
      service.dispose();
    },
  );

  test(
    'category caches are isolated, deduplicated and retained after refresh failure',
    () async {
      final pending = <String, Completer<Map<String, dynamic>>>{};
      final calls = <String>[];
      final service = MioMediaService(
        request: (_, payload, _) {
          final id = payload['categoryId'] as String;
          calls.add(id);
          return (pending[id] = Completer()).future;
        },
      );
      final controller = MioHomeController(service);
      final a = controller.loadRanking('0');
      final b = controller.loadRanking('42');
      controller.loadRanking('42');
      expect(calls, ['0', '42']);
      pending['42']!.complete({'data': rankData('42', title: '分类榜')});
      await b;
      pending['0']!.complete({'data': rankData('0', title: '首页榜')});
      await a;
      expect(controller.rankings['42']!.name, '分类榜');
      expect(controller.rankings['0']!.name, '首页榜');
      final retry = controller.loadRanking('42', refresh: true);
      pending['42']!.completeError(Exception('offline'));
      await retry;
      expect(controller.rankFailed, contains('42'));
      expect(controller.rankings['42']!.name, '分类榜');
      controller.selectGenre(MioKind.movie, '');
      expect(controller.rankings['42']!.entries.first.position, 1);
      controller.dispose();
      service.dispose();
    },
  );

  test('a cancelled older refresh cannot overwrite a newer result', () async {
    final pending = <Completer<Map<String, dynamic>>>[];
    final service = MioMediaService(
      request: (_, _, _) {
        final value = Completer<Map<String, dynamic>>();
        pending.add(value);
        return value.future;
      },
    );
    final controller = MioHomeController(service);
    final old = controller.loadRanking('42');
    final newer = controller.loadRanking('42', refresh: true);
    pending[1].complete({'data': rankData('42', title: '新榜')});
    await newer;
    pending[0].complete({'data': rankData('42', title: '旧榜')});
    await old;
    expect(controller.rankings['42']!.name, '新榜');
    controller.dispose();
    service.dispose();
  });

  testWidgets(
    'ranking skeleton is independent; original rank 10 opens the source ID',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<Map<String, dynamic>>();
      final service = MioMediaService(request: (_, _, _) => pending.future);
      final controller = MioHomeController(service);
      MioVideo? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeScope(
            child: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, _) => MioRankSection(
                  controller: controller,
                  categoryId: '42',
                  onDetails: (v) => opened = v,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SkeletonPosters), findsOneWidget);
      pending.complete({'data': rankData('42')});
      await tester.pumpAndSettle();
      expect(find.text('服务端原始榜名'), findsOneWidget);
      final scrollable = find.descendant(
        of: find.byKey(const PageStorageKey('mio-rank-42')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mio-rank-42-10')),
        240,
        scrollable: scrollable,
      );
      await tester.tap(find.byKey(const ValueKey('mio-rank-42-10')));
      expect(opened!.id, '9007199254741002');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      service.dispose();
    },
  );
}
