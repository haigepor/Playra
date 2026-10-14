import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
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
import 'package:kazumi/presentation/modern/miomedia/miomedia_browse.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

void main() {
  testWidgets('pending movie channel reserves cards without loading sentence', (
    tester,
  ) async {
    final service = MioMediaService(request: (_, _, _) async => {'data': {}});
    final controller = MioHomeController(service)..loading.add(MioKind.movie);
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeScope(
          child: Scaffold(
            body: MioHomeSections(
              controller: controller,
              feed: HomeFeed.movies,
              onDetails: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('正在加载电影'), findsNothing);
    expect(
      find.byKey(const ValueKey('content-skeleton-posters')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    service.dispose();
  });

  testWidgets('completed empty channel never masquerades as loading', (
    tester,
  ) async {
    final service = MioMediaService(request: (_, _, _) async => {'data': {}});
    final controller = MioHomeController(service);
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeScope(
          child: Scaffold(
            body: MioHomeSections(
              controller: controller,
              feed: HomeFeed.movies,
              onDetails: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('暂无电影内容'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('content-skeleton-posters')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    service.dispose();
  });

  testWidgets(
    'loaded cards survive refresh and tail placeholders end with loading',
    (tester) async {
      final service = MioMediaService(request: (_, _, _) async => {'data': {}});
      final controller = MioHomeController(service)..loading.add(MioKind.movie);
      controller.items[MioKind.movie] = [
        MioVideo.fromJson({
          'id': '9007199254740993',
          'title': '真实作品',
          'categoryName': '电影大全',
        }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ModernHomeScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => MioHomeSections(
                    controller: controller,
                    feed: HomeFeed.movies,
                    onDetails: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('真实作品'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-skeleton-posters')),
        findsOneWidget,
      );
      controller.loading.clear();
      controller.failed.add(MioKind.movie);
      controller.selectGenre(MioKind.movie, '');
      await tester.pump();
      expect(find.text('真实作品'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-skeleton-posters')),
        findsNothing,
      );
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      expect(controller.items[MioKind.movie]!.single.id, '9007199254740993');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      service.dispose();
    },
  );

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

  testWidgets('film first-load design renders a real page skeleton preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MioMediaService(request: (_, _, _) async => {'data': {}});
    final media = MioHomeController(service)..loading.add(MioKind.movie);
    final home = ModernHomeController(
      loadFeed: (_, _) async => [],
      readHistory: () => [],
    )..feed = HomeFeed.movies;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('skeleton-design-preview'),
          child: ModernHomeView(
            controller: home,
            media: media,
            onMediaDetails: (_) {},
            onSearch: () {},
            onCalendar: () {},
            onHistory: () {},
            onToggleTheme: () {},
            onDetails: (_) {},
            onResume: (_) {},
            onBrowse: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('content-skeleton-feature')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('content-skeleton-posters')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('skeleton-design-preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final preview = File(
        '.dart_tool/content-skeleton-before-20261012/film-skeleton-preview.png',
      );
      // 干净克隆没有本地预览目录，截图测试必须独立准备输出位置。
      await preview.parent.create(recursive: true);
      await preview.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    home.dispose();
    media.dispose();
    service.dispose();
  });
}
