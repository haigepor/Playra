import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'modern_home_controller_test.dart' show item;
import 'modern_home_view_test.dart' show mountHome;

void main() {
  test(
    'anime next-page failure retains data and retries the same page',
    () async {
      var fail = true;
      final pages = <int>[];
      final service = LuminaService(
        request: (op, payload, _) async {
          if (op == 'channels') {
            return {
              'data': {
                'channels': [
                  {'id': '1', 'name': '日漫'},
                ],
              },
            };
          }
          if (op == 'banners') {
            return {
              'data': {'banners': []},
            };
          }
          final page = payload['pageIndex'] as int;
          pages.add(page);
          if (page == 2 && fail) throw StateError('offline');
          return {
            'data': {
              'videos': List.generate(
                12,
                (i) => {'id': '${(page - 1) * 12 + i}', 'title': '动漫$i'},
              ),
              'pageInfo': {'total': 24},
            },
          };
        },
      );
      final home = LuminaHomeController(service);
      addTearDown(home.dispose);
      addTearDown(service.dispose);
      await home.bootstrap(warmOtherChannels: false);
      await home.loadMoreIn('all');
      expect(home.items, hasLength(12));
      expect(home.pageFailedIn('all'), isTrue);
      expect(home.hasMoreIn('all'), isTrue);
      fail = false;
      await home.loadMoreIn('all');
      expect(pages, [1, 2, 2]);
      expect(home.items, hasLength(24));
      expect(home.pageFailedIn('all'), isFalse);
      expect(home.hasMoreIn('all'), isFalse);
    },
  );

  testWidgets('anime more sheet loads next page by scrolling', (tester) async {
    final offsets = <int>[];
    final next = Completer<List<BangumiItem>>();
    final home = ModernHomeController(
      readHistory: () => [],
      loadFeed: (_, offset) async {
        offsets.add(offset);
        if (offset == 0) return List.generate(24, item);
        return next.future;
      },
    );
    addTearDown(home.dispose);
    await home.refresh();
    await mountHome(tester, home);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-more-anime')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('home-more-anime')));
    await tester.pumpAndSettle();
    final grid = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.fling(grid, const Offset(0, -5000), 4000);
    await tester.pump(const Duration(seconds: 1));
    expect(offsets, [0, 24]);
    next.complete(List.generate(24, (i) => item(i + 24)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
