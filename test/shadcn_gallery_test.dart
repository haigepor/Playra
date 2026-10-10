import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/components/shadcn_gallery.dart';
import 'package:kazumi/presentation/modern/components/component_catalog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('宿主中的弹窗留在画廊内，安卓返回先退出示例', (tester) async {
    final hostNavigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: hostNavigator,
        home: const Scaffold(body: Text('宿主旧版页面')),
      ),
    );
    hostNavigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ShadcnGallery(onExit: () => hostNavigator.currentState!.pop()),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('组件实验室'))).pushNamed('/dialog');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('组件实验室'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('宿主旧版页面'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final route in shadcnDemoRoutes.keys) {
      testWidgets('手机${dark ? "深色" : "浅色"}渲染 $route', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const ShadcnGallery());
        await tester.pumpAndSettle();
        if (dark) {
          await tester.tap(find.byTooltip('切换明暗主题'));
          await tester.pumpAndSettle();
        }
        Navigator.of(tester.element(find.text('组件实验室'))).pushNamed(route);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }

  testWidgets('组件目录可搜索、打开按钮示例并返回', (tester) async {
    await tester.pumpWidget(const ShadcnGallery());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'button');
    await tester.pumpAndSettle();
    expect(find.text('Button'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);
    await tester.tap(find.text('Button'));
    // 官方按钮示例包含持续旋转的进度指示器。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(ShadButton, 'Primary'), findsOneWidget);
    await tester.tap(find.byTooltip('切换明暗主题'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Button'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'button',
    );
  });

  testWidgets('画廊主题可切换，关闭回调可退出隔离导航', (tester) async {
    var closed = false;
    await tester.pumpWidget(ShadcnGallery(onExit: () => closed = true));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('组件实验室'));
    expect(ShadTheme.of(context).brightness, Brightness.light);
    await tester.tap(find.byTooltip('切换明暗主题'));
    await tester.pumpAndSettle();
    expect(ShadTheme.of(context).brightness, Brightness.dark);
    await tester.tap(find.byTooltip('关闭组件实验室'));
    expect(closed, isTrue);
  });
}
