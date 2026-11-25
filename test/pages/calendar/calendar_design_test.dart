import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/calendar/calendar_page.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

class CalendarTestSource extends MediaSource {
  bool fail = false;
  bool empty = false;
  int calls = 0;
  int invalidations = 0;
  @override
  void invalidateCache() => invalidations++;
  @override
  String get id => 'calendar-test';
  @override
  String get displayName => 'Calendar test';
  @override
  MediaSourceCapabilities get capabilities => const MediaSourceCapabilities();
  @override
  Future<HomeFeed> loadHome({int page = 1}) async {
    calls++;
    if (fail) throw Exception('network unavailable');
    final day = '一二三四五六日'[DateTime.now().weekday - 1];
    final items = empty
        ? <MediaItem>[]
        : [
            MediaItem(
              key: const MediaKey(sourceId: 'calendar-test', mediaId: 'timed'),
              title: '有时间的作品',
              updateSchedule: '周$day 18:30',
              subtitle: '更新至第3集',
            ),
            MediaItem(
              key: const MediaKey(
                sourceId: 'calendar-test',
                mediaId: 'unknown',
              ),
              title: '时间未知的作品',
              updateSchedule: '周$day',
              episodeCount: 12,
            ),
            const MediaItem(
              key: MediaKey(sourceId: 'calendar-test', mediaId: 'unplanned'),
              title: '没有更新计划',
              updateSchedule: '',
            ),
          ];
    return HomeFeed(
      sections: [
        MediaSection(
          id: 'a',
          title: '更新',
          layout: MediaSectionLayout.strip,
          items: items,
        ),
        MediaSection(
          id: 'b',
          title: '重复',
          layout: MediaSectionLayout.strip,
          items: items,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  final source = CalendarTestSource();
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-calendar-test-');
    Hive.init(data.path);
    await GStorage.init();
    mediaSources.register(source);
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });
  setUp(() {
    source.fail = false;
    source.empty = false;
    source.calls = 0;
    source.invalidations = 0;
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Size size,
    Brightness brightness,
    double scale,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShellTheme(brightness),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: const Scaffold(body: CalendarPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 700),
      const Size(390, 844),
      const Size(1280, 800),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$brightness $size scale=$scale shows genuine weekly schedule',
          (tester) async {
            await pumpPage(tester, size, brightness, scale);
            expect(find.text('有时间的作品'), findsOneWidget);
            expect(find.text('没有更新计划'), findsNothing);
            expect(find.text('18:30 更新'), findsOneWidget);
            expect(find.text('时间待定'), findsOneWidget);
            expect(find.text('12 集'), findsOneWidget);
            expect(find.textContaining('共 2 部更新'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('playra-calendar-picker')),
              size.width >= 900 && scale == 1 ? findsOneWidget : findsNothing,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('previous and next week keep selected weekday and data', (
    tester,
  ) async {
    await pumpPage(tester, const Size(390, 844), Brightness.dark, 1);
    await tester.tap(find.text('上周'));
    await tester.pumpAndSettle();
    expect(find.text('有时间的作品'), findsOneWidget);
    await tester.tap(find.text('下周'));
    await tester.pumpAndSettle();
    expect(find.text('有时间的作品'), findsOneWidget);
  });

  testWidgets('empty and failed schedules expose refresh and retry', (
    tester,
  ) async {
    source.empty = true;
    await pumpPage(tester, const Size(390, 844), Brightness.dark, 1);
    expect(find.text('这一天暂无更新'), findsOneWidget);
    source.empty = false;
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('有时间的作品'), findsOneWidget);
  });

  testWidgets('tablet month picker changes selected day', (tester) async {
    await pumpPage(tester, const Size(1280, 800), Brightness.dark, 1);
    final today = DateTime.now();
    final next = today.day <= 21 ? today.day + 1 : today.day - 1;
    final day = find.descendant(
      of: find.byKey(const ValueKey('playra-calendar-picker')),
      matching: find.text('$next'),
    );
    expect(day, findsOneWidget);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.textContaining('${today.month}月$next日（周'), findsOneWidget);
    expect(find.text('这一天暂无更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull to refresh invalidates and reloads', (tester) async {
    await pumpPage(tester, const Size(390, 844), Brightness.dark, 1);
    expect(source.calls, 1);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(source.invalidations, 1);
    expect(source.calls, 2);
    expect(find.text('有时间的作品'), findsOneWidget);
  });

  testWidgets('real follow toggle does not open detail', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester, const Size(390, 844), Brightness.dark, 1);
      final first = find.byTooltip('追番').first;
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      await GStorage.favorites.flush();
      expect(FavoriteStorage.isFavorite('calendar-test', 'timed'), isTrue);
      expect(find.byTooltip('取消追番'), findsOneWidget);
      await tester.tap(find.byTooltip('取消追番'));
      await tester.pumpAndSettle();
      await GStorage.favorites.flush();
      expect(FavoriteStorage.isFavorite('calendar-test', 'timed'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('failed fetch offers retry', (tester) async {
    source.fail = true;
    await pumpPage(tester, const Size(390, 844), Brightness.dark, 1);
    expect(find.text('更新内容暂未加载'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('有时间的作品'), findsOneWidget);
  });
}
