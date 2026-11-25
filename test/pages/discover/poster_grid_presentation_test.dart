import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';

void main() {
  const items = [
    MediaItem(
      key: MediaKey(sourceId: 's', mediaId: '1'),
      title: '很长的作品名称一',
      subtitle: '更新至第 12 集',
    ),
    MediaItem(
      key: MediaKey(sourceId: 's', mediaId: '2'),
      title: '很长的作品名称二',
      subtitle: '已完结',
    ),
    MediaItem(
      key: MediaKey(sourceId: 's', mediaId: '3'),
      title: '很长的作品名称三',
    ),
  ];

  for (final scale in [1.0, 2.0]) {
    testWidgets('browse uses three columns when readable at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  MediaPosterGrid(
                    items: items,
                    onTap: (_) {},
                    fixedColumns: 3,
                    overlayStatus: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final first = tester.getTopLeft(find.text(items[0].title));
      final third = tester.getTopLeft(find.text(items[2].title));
      if (scale == 1) {
        expect(third.dy, first.dy);
      } else {
        expect(third.dy, greaterThan(first.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final columns in [2, 3]) {
    for (final brightness in Brightness.values) {
      testWidgets('$columns columns, $brightness, large text', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    MediaPosterGrid(
                      items: items,
                      onTap: (_) {},
                      fixedColumns: columns,
                      overlayStatus: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final first = tester.getTopLeft(find.text(items[0].title));
        final second = tester.getTopLeft(find.text(items[1].title));
        expect(first.dy, second.dy);
        expect(second.dx, greaterThan(first.dx));
        final title = tester.widget<Text>(find.text(items[0].title));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(
          tester.getBottomLeft(find.text(items[0].subtitle)).dy,
          lessThan(first.dy),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
