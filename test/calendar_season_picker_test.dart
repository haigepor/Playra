import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/calendar/widgets/calendar_season_picker.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    ValueChanged<DateTime> onSelected, {
    DateTime? now,
    double width = 390,
    double height = 844,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ModernHomeScope(
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: CalendarSeasonPicker(
                  selectedSeason: DateTime(2026, 10),
                  now: now ?? DateTime(2026, 10, 11),
                  onSelected: onSelected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('年份与四季同时显示，草稿不提交，确认一次返回准确季度', (tester) async {
    final submissions = <DateTime>[];
    await mount(tester, submissions.add);
    expect(find.byType(YearPicker), findsOneWidget);
    expect(find.text('冬季'), findsOneWidget);
    expect(find.text('秋季'), findsOneWidget);
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    expect(find.byType(YearPicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-season-4')));
    await tester.pumpAndSettle();
    expect(submissions, isEmpty);
    expect(find.text('查看 2024 年 · 春季'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-season-confirm')));
    await tester.tap(find.byKey(const ValueKey('calendar-season-confirm')));
    expect(submissions, [DateTime(2024, 4)]);
  });

  testWidgets('未来季度禁用，从历史年份返回今年时调整到可选季度', (tester) async {
    DateTime? selected;
    await mount(tester, (value) => selected = value, now: DateTime(2026, 5));
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('calendar-season-7')))
          .onTap,
      isNull,
    );
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-this-year')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('查看 2026 年 · 春季'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-season-confirm')));
    expect(selected, DateTime(2026, 4));
  });

  testWidgets('当前季度只重置草稿，确认后提交', (tester) async {
    DateTime? selected;
    await mount(tester, (value) => selected = value);
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-season-current')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('查看 2026 年 · 秋季'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-season-confirm')));
    expect(selected, DateTime(2026, 10));
  });

  testWidgets('320 宽 1.5 倍字体下，年份与季度和确认按钮无溢出', (tester) async {
    await mount(tester, (_) {}, width: 320, scale: 1.5);
    expect(tester.takeException(), isNull);
    final winter = tester.getRect(
      find.byKey(const ValueKey('calendar-season-1')),
    );
    final spring = tester.getRect(
      find.byKey(const ValueKey('calendar-season-4')),
    );
    final summer = tester.getRect(
      find.byKey(const ValueKey('calendar-season-7')),
    );
    expect(winter.top, spring.top);
    expect(spring.left, greaterThan(winter.right));
    expect(summer.top, greaterThan(winter.bottom));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('calendar-season-confirm')))
          .bottom,
      lessThan(844),
    );
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('矮屏可滚动主体，确认按钮始终在可视范围', (tester) async {
    await mount(tester, (_) {}, width: 568, height: 360);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('calendar-season-confirm')))
          .bottom,
      lessThan(360),
    );
  });
}
