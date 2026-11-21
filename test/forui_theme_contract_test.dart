import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;
import 'package:kazumi/presentation/theme/playra_forui_theme.dart';
import 'package:kazumi/shell/shell_theme.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Forui tab header and swipe view stay synchronized at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TabController(length: 3, vsync: tester);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: PlayraForuiScope(child: child!),
          ),
          home: Scaffold(
            appBar: AppBar(
              bottom: PlayraTabBar(
                controller: controller,
                tabs: const [
                  Tab(text: '详情'),
                  Tab(text: '讨论'),
                  Tab(text: '评价'),
                ],
              ),
            ),
            body: TabBarView(
              controller: controller,
              children: const [
                Center(child: Text('详情内容')),
                Center(child: Text('讨论内容')),
                Center(child: Text('评价内容')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('讨论'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(find.text('讨论内容').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 2);
      expect(find.text('评价内容').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final brightness in Brightness.values) {
    test('Forui and the shell share the $brightness content palette', () {
      final material = buildShellTheme(brightness);
      final theme = playraForuiTheme(material);
      final tokens = material.extension<PlayraTokens>()!;
      expect(theme.colors.background, material.colorScheme.surface);
      expect(theme.colors.foreground, material.colorScheme.onSurface);
      expect(theme.colors.primary, tokens.primary);
      expect(theme.colors.primaryForeground, tokens.primaryForeground);
      expect(theme.colors.destructive, tokens.destructive);
    });
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Forui controls remain usable at 320px/$scale/$brightness with reduced motion',
        (tester) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var enabled = false;
          var selected = false;
          var saved = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildShellTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                  accessibleNavigation: true,
                ),
                child: PlayraForuiScope(child: child!),
              ),
              home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: ListView(
                    children: [
                      PlayraCard(
                        child: Column(
                          children: [
                            PlayraSwitch(
                              value: enabled,
                              onChanged: (value) =>
                                  setState(() => enabled = value),
                            ),
                            PlayraChoice(
                              label: const Text('带有较长中文名称的线路选项'),
                              selected: selected,
                              onSelected: (value) =>
                                  setState(() => selected = value),
                            ),
                            PlayraButton(
                              onPressed: () => saved++,
                              child: const Text('保存设置'),
                            ),
                            const PlayraButton(
                              onPressed: null,
                              child: Text('暂不可用'),
                            ),
                            PlayraButton(
                              busy: true,
                              onPressed: () => saved++,
                              child: const Text('正在保存'),
                            ),
                            const PlayraBadge.destructive(child: Text('失败')),
                            const PlayraAlert(
                              title: Text('提示'),
                              subtitle: Text('设置已就绪'),
                            ),
                            const PlayraDivider(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(f.FSwitch), findsOneWidget);
          expect(find.byType(f.FCard), findsOneWidget);
          expect(find.byType(f.FBadge), findsOneWidget);
          expect(find.byType(f.FAlert), findsOneWidget);
          await tester.tap(find.byType(PlayraSwitch));
          await tester.pumpAndSettle();
          expect(enabled, isTrue);
          await tester.tap(find.byType(PlayraChoice));
          await tester.pumpAndSettle();
          expect(selected, isTrue);
          final save = find.widgetWithText(PlayraButton, '保存设置');
          expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          await tester.tap(find.text('暂不可用'));
          await tester.tap(find.text('正在保存'));
          await tester.pumpAndSettle();
          expect(saved, 1);
          // Keyboard activation must reach the same action as touch.
          Focus.of(tester.element(find.text('保存设置'))).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(saved, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
