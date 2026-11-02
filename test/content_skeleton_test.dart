import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

void main() {
  testWidgets('anime first page has skeletons and exits to retry on failure', (
    tester,
  ) async {
    final pending = Completer<List<BangumiItem>>();
    final controller = ModernHomeController(
      loadFeed: (_, _) => pending.future,
      readHistory: () => [],
    );
    final request = controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeView(
          controller: controller,
          onSearch: () {},
          onCalendar: () {},
          onHistory: () {},
          onToggleTheme: () {},
          onDetails: (_) {},
          onResume: (_) {},
          onBrowse: (_) {},
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('content-skeleton-feature')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('content-skeleton-posters')),
      findsWidgets,
    );
    pending.completeError(StateError('unavailable'));
    await request;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('content-skeleton-feature')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('content-skeleton-posters')),
      findsNothing,
    );
    expect(find.text('重试'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'reduced motion is static and skeleton excludes interaction and duplicate semantics',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ContentSkeleton(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('不可用占位'),
                ),
              ),
            ),
          ),
        ),
      );
      final effect =
          tester
                  .widget<Skeletonizer>(
                    find.byWidgetPredicate((widget) => widget is Skeletonizer),
                  )
                  .effect
              as PulseEffect;
      expect(effect.duration, Duration.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.text('不可用占位'), warnIfMissed: false);
      expect(taps, 0);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('正在加载内容'), findsOneWidget);
      expect(find.bySemanticsLabel('不可用占位'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('all skeleton layouts fit a narrow viewport with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeScope(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SkeletonFeature(height: 296),
                        SkeletonFeature(bento: true),
                        SkeletonPosters(),
                        SkeletonPosters(horizontal: false, count: 4),
                        SkeletonInfoList(count: 2),
                        SkeletonEpisodes(),
                        SkeletonComments(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty cover shows static fallback instead of indefinite loading',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NetworkImgLayer(src: '', width: 104, height: 148),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('content-skeleton-image')),
        findsNothing,
      );
      expect(find.byType(Image), findsOneWidget);
    },
  );
}
