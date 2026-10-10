import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/presentation/modern/library/modern_library_controller.dart';
import 'package:kazumi/presentation/modern/library/modern_library_view.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';
import 'modern_library_controller_test.dart' show item;

void main() {
  Future<ModernLibraryController> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    List<CollectedBangumi>? records,
    ValueChanged<History>? onResume,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collection =
        records ??
        [
          for (var id = 1; id <= 20; id++)
            CollectedBangumi(
              item(id, '番剧$id'),
              DateTime(2026),
              id == 2 ? 2 : 1,
            ),
        ];
    final controller = ModernLibraryController(
      readCollections: () => collection,
      readHistory: () => collection.isEmpty
          ? []
          : [
              History(
                collection.first.bangumiItem,
                7,
                '来源',
                DateTime(2026, 10, 11),
                '/a',
                '第七话',
              )..progresses[7] = Progress(7, 0, 754000),
            ],
      changeCollection: (bangumi, type) async {
        collection.firstWhere((e) => e.bangumiItem.id == bangumi.id).type =
            type.value;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: ModernShell(
            selectedIndex: 2,
            selectDestination: (_) {},
            outlet: ModernLibraryView(
              controller: controller,
              showRating: true,
              onDetails: (_) {},
              onResume: onResume ?? (_) {},
              onChangeType: (bangumi, type) =>
                  controller.changeStatus(bangumi, type),
              onSync: () {},
              onStyle: () {},
              onDiscover: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('固定顶部、真实续播、分类搜索与底部暗色', (tester) async {
    History? resumed;
    final controller = await mount(
      tester,
      onResume: (history) => resumed = history,
    );
    expect(find.text('上次看到第七话'), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    final searchButton = tester.widget<IconButton>(
      find.widgetWithIcon(
        IconButton,
        (tester.widget<IconButton>(find.byTooltip('搜索追番')).icon as Icon).icon!,
      ),
    );
    final searchContext = tester.element(find.byTooltip('搜索追番'));
    expect(
      (searchButton.icon as Icon).color,
      Theme.of(searchContext).colorScheme.onSurfaceVariant,
    );
    await tester.tap(find.byKey(const ValueKey('library-resume-1')));
    expect(resumed!.adapterName, '来源');
    final headerBefore = tester.getTopLeft(
      find.byKey(const ValueKey('library-header')),
    );
    await tester.drag(
      find.byKey(const ValueKey('library-results')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('library-header'))),
      headerBefore,
    );
    await tester.tap(find.byKey(const ValueKey('library-category-2')));
    await tester.pumpAndSettle();
    expect(controller.category, CollectType.planToWatch);
    expect(find.text('番剧2'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索追番'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的番剧'), findsOneWidget);
    final navigation = tester.element(
      find.byKey(const ValueKey('modern-navigation')),
    );
    expect(Theme.of(navigation).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320宽大字体、排序与状态弹层没有溢出', (tester) async {
    final controller = await mount(tester, width: 320, scale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('评分最高'));
    await tester.pumpAndSettle();
    expect(controller.sort, LibrarySort.rating);
    await tester.tap(find.byKey(const ValueKey('library-manage-1')));
    await tester.pumpAndSettle();
    expect(find.text('修改追番状态'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-status-4')));
    await tester.pumpAndSettle();
    expect(controller.count(CollectType.watched), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('空库引导与桌面卡片布局', (tester) async {
    await mount(tester, records: []);
    expect(find.text('还没有追番'), findsOneWidget);
    expect(find.text('去发现番剧'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final controller = await mount(tester, width: 1200, height: 800);
    controller.setLayout(CollectLayout.cards);
    await tester.pumpAndSettle();
    expect(find.text('番剧1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
