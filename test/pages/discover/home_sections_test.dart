import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/home_sections.dart';

MediaSection _section({int count = 6}) {
  return MediaSection(
    id: 'hot',
    title: '热门番剧',
    layout: MediaSectionLayout.grid,
    items: [
      for (var i = 0; i < count; i++)
        MediaItem(
          key: MediaKey(sourceId: 'fake', mediaId: '$i'),
          title: '作品 $i',
          subtitle: '更新至 ${i + 1} 集',
          cover: '',
        ),
    ],
    ranked: true,
    tabs: const ['热播榜'],
  );
}

Widget _harness(HomeLayoutMetrics layout) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeSectionGrid(
          layout: layout,
          section: _section(),
          onTap: (_) {},
          onMore: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('phone section exposes the full poster rail', (tester) async {
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phone));
    await tester.pump();
    expect(find.byType(HomePosterCard), findsNWidgets(6));
    expect(find.text('热门番剧'), findsOneWidget);
    expect(find.text('6 部'), findsNothing);
    expect(find.text('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape section exposes the full poster rail', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(HomeLayoutMetrics.tabletLandscape));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('作品 5'),
      find.byType(ListView),
      const Offset(-160, 0),
    );
    expect(find.text('作品 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
