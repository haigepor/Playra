import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';
import 'package:kazumi/pages/discover/discover_page.dart';
import 'package:kazumi/pages/discover/search_page.dart';
import 'package:kazumi/pages/discover/browse_page.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/pages/profile/profile_page.dart';
import 'package:kazumi/pages/calendar/calendar_page.dart';
import 'package:kazumi/pages/favorites/favorites_page.dart';
import 'package:kazumi/pages/discover/home_banner.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

class BoundarySource extends MediaSource {
  static Future<MediaPage> Function(String keyword, int page)? searchHandler;
  static Future<MediaPage> Function(String sort, int page)? browseHandler;
  static bool small = false;
  static int bannerCount = 3;
  static int browseCalls = 0;
  static int searchCalls = 0;
  @override
  String get id => 'audit';
  @override
  String get displayName => 'Sample';
  @override
  MediaSourceCapabilities get capabilities => const MediaSourceCapabilities();
  final items = List.generate(
    12,
    (i) => MediaItem(
      key: MediaKey(sourceId: 'audit', mediaId: '$i'),
      title: 'A long media title for boundary layout $i',
      subtitle: 'Updated 12',
      updateSchedule: '周日${i.isEven ? ' 18:30' : ''}',
    ),
  );
  @override
  Future<HomeFeed> loadHome({int page = 1}) async => HomeFeed(
    banners: List.generate(
      bannerCount,
      (i) => MediaBanner(
        id: '$i',
        title: 'A long recommended media title $i',
        imageUrl: '',
        target: items[i % items.length].key,
      ),
    ),
    sections: [
      MediaSection(
        id: 'rank',
        title: 'Ranking',
        layout: MediaSectionLayout.strip,
        items: items,
        ranked: true,
      ),
      MediaSection(
        id: 'recent',
        title: 'New',
        layout: MediaSectionLayout.strip,
        items: items,
      ),
    ],
  );
  @override
  Future<List<MediaCategory>> loadCategories() async => const [
    MediaCategory(id: 'cat', name: 'Animation'),
  ];
  @override
  Future<MediaPage> browse({
    required String categoryId,
    int page = 1,
    String sort = '',
    String billing = '',
  }) async {
    browseCalls++;
    if (browseHandler != null) return browseHandler!(sort, page);
    return small
        ? MediaPage(
            items: items.take(1).toList(),
            pageIndex: page,
            pages: 3,
            total: 3,
          )
        : MediaPage(items: items);
  }

  @override
  Future<MediaPage> search(String keyword, {int page = 1}) async {
    searchCalls++;
    if (searchHandler != null) return searchHandler!(keyword, page);
    return small
        ? MediaPage(
            items: items.take(1).toList(),
            pageIndex: page,
            pages: 3,
            total: 3,
          )
        : MediaPage(items: items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  setUpAll(() async {
    final font = FontLoader('MI_Sans_Regular')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('assets/fonts/MiSans-Regular.ttf').readAsBytes(),
          ),
        ),
      );
    await font.load();
    data = await Directory.systemTemp.createTemp('playra-layout-data-');
    Hive.init(data.path);
    await GStorage.init();
    mediaSources.register(BoundarySource());
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });
  tearDown(() {
    BoundarySource.small = false;
    BoundarySource.bannerCount = 3;
    BoundarySource.searchHandler = null;
    BoundarySource.browseHandler = null;
  });
  final pages = <String, Widget Function()>{
    'home': () => const DiscoverPage(),
    'calendar': () => const CalendarPage(),
    'profile': () => const ProfilePage(),
    'favorites': () => FavoritesPage(onDiscover: () {}),
    'search': () => const SearchPage(),
    'browse': () => const BrowsePage(
      args: BrowseArgs(
        sourceId: 'audit',
        categoryId: 'cat',
        title: 'Animation',
      ),
    ),
  };
  for (final size in [
    const Size(320, 640),
    const Size(360, 760),
    const Size(390, 844),
    const Size(760, 360),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final entry in pages.entries) {
        testWidgets('${entry.key} ${size.width}x${size.height} scale=$scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildShellTheme(Brightness.dark),
              home: Scaffold(body: entry.value()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('Android decoder choice persists at 320dp with large text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      await GStorage.putSetting(SettingsKeys.hAenable, true);
      await GStorage.putSetting(SettingsKeys.hardwareDecoder, 'auto-safe');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.dark),
        home: const ProfilePage(),
      ),
    );
    await tester.scrollUntilVisible(find.text('硬件解码方式'), 180);
    await tester.tap(find.text('硬件解码方式'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('性能优先'),
      80,
      scrollable: find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('性能优先'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(GStorage.getSetting(SettingsKeys.hardwareDecoder), 'mediacodec');
    expect(find.text('性能优先'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    await tester.runAsync(
      () => GStorage.putSetting(SettingsKeys.hardwareDecoder, 'auto-safe'),
    );
  });

  testWidgets('resume card shows episode on artwork and keeps progress', (
    tester,
  ) async {
    await tester.runAsync(
      () => HistoryStorage.save(
        HistoryRecord(
          sourceId: 'audit',
          mediaId: 'resume-test',
          title: '一部特别长的继续观看作品标题用于验证单行省略',
          cover: '',
          roadCode: 'main',
          roadName: '主线',
          episode: 6,
          episodeTitle: '第 6 集',
          positionMs: 60000,
          durationMs: 120000,
          updatedAt: DateTime.now(),
        ),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.dark),
        home: const Scaffold(body: DiscoverPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final title = tester.widget<Text>(find.text('一部特别长的继续观看作品标题用于验证单行省略'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.text('第 6 集'), findsOneWidget);
    expect(find.text('01:00 / 02:00'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => HistoryStorage.delete('audit', 'resume-test'));
  });

  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    for (final count in [3, 40]) {
      testWidgets('carousel has no indicators at $size with $count banners', (
        tester,
      ) async {
        BoundarySource.bannerCount = count;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildShellTheme(Brightness.dark),
            home: const Scaffold(body: DiscoverPage()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final carousel = find.byType(HomeBannerCarousel);
        expect(carousel, findsOneWidget);
        expect(
          find.descendant(
            of: carousel,
            matching: find.textContaining(RegExp(r'^\d+\s*/\s*\d+$')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: carousel,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.constraints?.maxHeight == 5 &&
                  (widget.constraints?.maxWidth == 5 ||
                      widget.constraints?.maxWidth == 14),
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('phone carousel cards retain 16:9 and respond to swipes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.dark),
        home: const Scaffold(body: DiscoverPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final carousel = find.byType(HomeBannerCarousel);
    final pages = find.descendant(
      of: carousel,
      matching: find.byType(PageView),
    );
    final controller = tester.widget<PageView>(pages).controller!;
    expect(controller.viewportFraction, closeTo(.84, .001));
    expect(find.text('A long recommended media title 0'), findsOneWidget);
    final artwork = find.descendant(
      of: carousel,
      matching: find.byType(MediaCoverImage),
    );
    final size = tester.getSize(artwork.first);
    expect(size.width / size.height, closeTo(16 / 9, .01));
    expect(size.width, lessThan(360));
    await tester.drag(pages, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('A long recommended media title 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone carousel advances automatically after six seconds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.dark),
        home: const Scaffold(body: DiscoverPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A long recommended media title 0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('A long recommended media title 0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('A long recommended media title 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'narrow calendar keeps date targets and input actions reachable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: const Scaffold(body: CalendarPage()),
        ),
      );
      await tester.pumpAndSettle();
      final day = find
          .ancestor(of: find.text('周日'), matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(day).width, greaterThanOrEqualTo(48));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('周日'));
      await tester.pumpAndSettle();
      expect(tester.getRect(day).left, greaterThanOrEqualTo(16));
      expect(tester.getRect(day).right, lessThanOrEqualTo(304));
      await tester.tap(find.text('${DateTime.now().month}月'));
      await tester.pumpAndSettle();
      expect(find.byType(InputDatePickerFormField), findsOneWidget);
      expect(find.text('确定').hitTestable(), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('underfilled browse can reach more content', (tester) async {
    BoundarySource.small = true;
    BoundarySource.browseCalls = 0;
    addTearDown(() => BoundarySource.small = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.light),
        home: const BrowsePage(
          args: BrowseArgs(
            sourceId: 'audit',
            categoryId: 'cat',
            title: 'Animation',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      BoundarySource.browseCalls,
      greaterThan(1),
      reason: 'More pages exist and the user swiped to reach them',
    );
  });
  testWidgets('underfilled search can reach more content', (tester) async {
    BoundarySource.small = true;
    BoundarySource.searchCalls = 0;
    addTearDown(() => BoundarySource.small = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.light),
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sample');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      BoundarySource.searchCalls,
      greaterThan(1),
      reason: 'More pages exist and the user swiped to reach them',
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('tablet search retains real results at text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: const SearchPage(),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'sample');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Playra'), findsOneWidget);
      expect(find.textContaining('搜索结果：'), findsOneWidget);
      final cover = tester.getSize(find.byType(MediaCoverImage).first);
      expect(cover.width, 168);
      expect(cover.width / cover.height, closeTo(1.5, .01));
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> openPage(WidgetTester tester, bool search) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(Brightness.light),
        home: search
            ? const SearchPage()
            : const BrowsePage(
                args: BrowseArgs(
                  sourceId: 'audit',
                  categoryId: 'cat',
                  title: 'Animation',
                ),
              ),
      ),
    );
    await tester.pump();
    if (search) {
      await tester.enterText(find.byType(TextField), 'sample');
      await tester.testTextInput.receiveAction(TextInputAction.search);
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  MediaItem item(String name) => MediaItem(
    key: MediaKey(sourceId: 'audit', mediaId: name),
    title: name,
  );
  for (final search in [false, true]) {
    final label = search ? 'search' : 'browse';
    testWidgets('$label stops after failure and retries the same page', (
      tester,
    ) async {
      final calls = <int>[];
      var failed = false;
      Future<MediaPage> load(String _, int page) async {
        calls.add(page);
        if (page == 2 && !failed) {
          failed = true;
          throw Exception('Offline');
        }
        return MediaPage(
          items: [item('Result $page')],
          pageIndex: page,
          pages: 2,
          total: 2,
        );
      }

      if (search) {
        BoundarySource.searchHandler = load;
      } else {
        BoundarySource.browseHandler = load;
      }
      await openPage(tester, search);
      await tester.pumpAndSettle();
      expect(calls, [1, 2]);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, [1, 2]);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(calls, [1, 2, 2]);
      expect(find.text('Result 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label crosses an empty middle page', (tester) async {
      final calls = <int>[];
      Future<MediaPage> load(String _, int page) async {
        calls.add(page);
        return MediaPage(
          items: page == 2 ? [] : [item('Result $page')],
          pageIndex: page,
          pages: 3,
          total: 2,
        );
      }

      if (search) {
        BoundarySource.searchHandler = load;
      } else {
        BoundarySource.browseHandler = load;
      }
      await openPage(tester, search);
      await tester.pumpAndSettle();
      expect(calls, [1, 2, 3]);
      expect(find.text('Result 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label ignores the old page after changing the request', (
      tester,
    ) async {
      final pending = Completer<MediaPage>();
      Future<MediaPage> load(String query, int page) async {
        final old = search ? query == 'sample' : query.isEmpty;
        if (old && page == 2) return pending.future;
        return MediaPage(
          items: [item(old ? 'Original' : 'Updated')],
          pageIndex: page,
          pages: old ? 2 : 1,
        );
      }

      if (search) {
        BoundarySource.searchHandler = load;
      } else {
        BoundarySource.browseHandler = load;
      }
      await openPage(tester, search);
      expect(find.text('Original'), findsOneWidget);
      if (search) {
        await tester.enterText(find.byType(TextField), 'new');
        await tester.testTextInput.receiveAction(TextInputAction.search);
      } else {
        await tester.tap(find.text('最热'));
      }
      await tester.pump();
      pending.complete(
        MediaPage(items: [item('STALE')], pageIndex: 2, pages: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated'), findsOneWidget);
      expect(find.text('STALE'), findsNothing);
      expect(find.text('Original'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final search in [false, true]) {
    testWidgets(
      '${search ? 'search' : 'browse'} keeps pagination reachable after viewport grows',
      (tester) async {
        final calls = <int>[];
        Future<MediaPage> load(String _, int page) async {
          calls.add(page);
          return MediaPage(
            items: [item('Page $page')],
            pageIndex: page,
            pages: 3,
            total: 3,
          );
        }

        if (search) {
          BoundarySource.searchHandler = load;
        } else {
          BoundarySource.browseHandler = load;
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 180);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildShellTheme(Brightness.light),
            home: search
                ? const SearchPage()
                : const BrowsePage(
                    args: BrowseArgs(
                      sourceId: 'audit',
                      categoryId: 'cat',
                      title: 'Animation',
                    ),
                  ),
          ),
        );
        await tester.pump();
        if (search) {
          await tester.enterText(find.byType(TextField), 'sample');
          await tester.testTextInput.receiveAction(TextInputAction.search);
        }
        await tester.pumpAndSettle();
        expect(calls, [1]);
        tester.view.physicalSize = const Size(360, 760);
        await tester.pumpAndSettle();
        await tester.tap(find.text('加载更多'));
        await tester.pumpAndSettle();
        expect(calls, [1, 2, 3]);
        expect(find.text('Page 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
