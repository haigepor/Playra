import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/calendar/modern_calendar_controller.dart';
import 'package:kazumi/presentation/modern/calendar/modern_calendar_view.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';

void main() {
  Future<ModernCalendarController> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      readCollections: () => {},
      readHistory: () => [],
      load: (season, {required force, required cancelToken}) async =>
          SeasonScheduleSnapshot(
            season: season,
            entries: [
              for (var day = 1; day <= 7; day++)
                parseScheduleEntry({
                  'id': day,
                  'name': '星期$day的番剧',
                  'metaTags': ['日本', 'TV'],
                }, weekday: day),
            ],
          ),
    );
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: ModernShell(
            selectedIndex: 1,
            selectDestination: (_) {},
            outlet: ModernCalendarView(
              controller: controller,
              onDetails: (_) {},
              onResume: (_) {},
              onStyle: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('320dp and large type put the complete title above the period', (
    tester,
  ) async {
    final controller = await mount(tester, width: 320, scale: 2);
    final title = tester.getRect(find.text('放送日历'));
    final period = tester.getRect(
      find.byKey(const ValueKey('calendar-season')),
    );
    expect(period.top, greaterThanOrEqualTo(title.bottom));
    expect(title.left, greaterThanOrEqualTo(0));
    expect(title.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('加载与失败不显示零部，失败时重试不会清空筛选', (tester) async {
    final controller = await mount(tester);
    controller.snapshot = null;
    controller.loading = true;
    controller.setFilters(watchingOnly: true);
    await tester.pump();
    expect(find.text('0部'), findsNothing);
    expect(find.text('加载中'), findsOneWidget);
    controller.loading = false;
    controller.error = '暂时无法获取放送日历';
    controller.setFilters(hideWatched: true);
    await tester.pumpAndSettle();
    expect(find.text('暂时无法获取放送日历'), findsOneWidget);
    expect(find.text('0部'), findsNothing);
    expect(find.text('清除筛选'), findsNothing);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(controller.snapshot, isNotNull);
    expect(controller.watchingOnly, isTrue);
    expect(controller.hideWatched, isTrue);
    expect(find.text('没有符合筛选的番剧'), findsOneWidget);
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('星期7的番剧'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('减少动画时星期切换立即到达对应列表', (tester) async {
    final controller = await mount(tester, reduceMotion: true);
    await tester.tap(find.byKey(const ValueKey('calendar-weekday-1')));
    await tester.pump();
    await tester.pump();
    expect(controller.weekday, 1);
    expect(find.text('星期1的番剧'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('星期点击与左右滑动同步，顶部固定，沿用暗色主题', (tester) async {
    final controller = await mount(tester);
    expect(find.text('星期7的番剧'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-weekday-1')));
    await tester.pumpAndSettle();
    expect(controller.weekday, 1);
    expect(find.text('星期1的番剧'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('calendar-days')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.weekday, 2);
    await tester.tap(find.byKey(const ValueKey('calendar-weekday-6')));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const ValueKey('calendar-weekday-3')));
    await tester.pumpAndSettle();
    expect(controller.weekday, 3);
    expect(find.text('星期3的番剧'), findsOneWidget);
    expect(find.text('放送日历'), findsOneWidget);
    final pageContext = tester.element(find.text('放送日历'));
    expect(Theme.of(pageContext).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('320 宽与大字体无溢出，筛选和季度弹层可打开', (tester) async {
    final controller = await mount(tester, width: 320, scale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('calendar-filters')));
    await tester.pumpAndSettle();
    expect(find.text('筛选与排序'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(_tooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season')));
    await tester.pumpAndSettle();
    expect(find.text('选择放送季度'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final originalSeason = controller.season;
    expect(find.byType(YearPicker), findsOneWidget);
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-4')));
    await tester.pumpAndSettle();
    expect(find.text('查看 2024 年 · 春季'), findsOneWidget);
    expect(controller.season, originalSeason);
    await tester.tap(_tooltip('关闭'));
    await tester.pumpAndSettle();
    expect(controller.season, originalSeason);
    expect(find.byType(YearPicker), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('季度草稿只在确认时切换，按钮避开底部安全区', (tester) async {
    final controller = await mount(tester);
    final originalSeason = controller.season;
    await tester.tap(find.byKey(const ValueKey('calendar-season')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-4')));
    await tester.pumpAndSettle();
    expect(controller.season, originalSeason);
    final confirm = find.byKey(const ValueKey('calendar-season-confirm'));
    expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(844 - 24));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(controller.season, DateTime(2024, 4));
    expect(find.byType(YearPicker), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('横屏矮窗口的季度弹层保留固定确认按钮', (tester) async {
    final controller = await mount(tester, width: 568, height: 360);
    await tester.tap(find.byKey(const ValueKey('calendar-season')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('calendar-season-confirm')))
          .bottom,
      lessThanOrEqualTo(360 - 24),
    );
    await tester.tap(_tooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Finder _tooltip(String message) => find.byTooltip(message);
