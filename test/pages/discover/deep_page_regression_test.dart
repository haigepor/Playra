import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_header.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/home_sections.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';

void main() {
  testWidgets('channel tabs switch selection in-place', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTopBar(
            layout: HomeLayoutMetrics.phone,
            onSearch: () {},
            onChannelSelected: (index) => selectedIndex = index,
            onCalendar: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('热门'), findsOneWidget);
    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(selectedIndex, 1);
  });

  testWidgets('screen reader can hear visible score on poster', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPosterCard(
            item: const MediaItem(
              key: MediaKey(sourceId: 's', mediaId: '1'),
              title: '作品',
              score: 9.5,
            ),
            showScore: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('查看 作品，评分 9.5'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('desktop mouse can drag the horizontal home rail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final items = List.generate(
      12,
      (i) => MediaItem(
        key: MediaKey(sourceId: 's', mediaId: '$i'),
        title: '作品$i',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeSectionGrid(
            layout: HomeLayoutMetrics.tabletLandscape,
            section: MediaSection(
              id: 's',
              title: '热门',
              layout: MediaSectionLayout.strip,
              items: items,
            ),
            onTap: (_) {},
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(list));
    await mouse.down(tester.getCenter(list));
    await mouse.moveBy(const Offset(-50, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(-300, 0));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    await mouse.removePointer();
  });
}
