import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/theme/playra_theme.dart';
import 'package:kazumi/presentation/widgets/playra_sheet.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'package:kazumi/presentation/modern/library/sdk_library_widgets.dart';
import 'package:kazumi/services/storage/sdk_library_models.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_widgets.dart';
import 'package:forui/forui.dart' as f;
import 'package:kazumi/presentation/widgets/playra_controls.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets('icon label and tap semantics stay together, enabled=$enabled', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlayraIconButton(
        key: const ValueKey('accessible-action'),
        tooltip: '打开设置',
        icon: const Icon(Icons.settings),
        onPressed: enabled ? () {} : null,
      ))));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.bySemanticsLabel('打开设置')), matchesSemantics(
        label: '打开设置',
        isButton: true,
        hasEnabledState: true,
        isEnabled: enabled,
        hasTapAction: enabled,
      ));
      semantics.dispose();
    });
  }

  testWidgets('mobile controls retain touch targets, contrast and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var actions = 0;
    final theme = playraTheme(ThemeData());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2), disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              for (final size in PlayraButtonSize.values)
                PlayraButton(
                  size: size,
                  onPressed: () => actions++,
                  child: Text('保存 ${size.name}'),
                ),
              PlayraIconButton(
                size: 32,
                tooltip: '搜索',
                onPressed: () => actions++,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final size in PlayraButtonSize.values) {
      final button = find.widgetWithText(PlayraButton, '保存 ${size.name}');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final text = tester.widget<RichText>(
        find.descendant(of: button, matching: find.byType(RichText)),
      );
      expect(text.text.style!.color, theme.colorScheme.onPrimary);
      await tester.tapAt(
        tester.getTopLeft(button) +
            Offset(2, tester.getSize(button).height / 2),
      );
    }
    final icon = find.byType(PlayraIconButton);
    expect(tester.getSize(icon), const Size(48, 48));
    await tester.tapAt(tester.getTopLeft(icon) + const Offset(2, 24));
    await tester.pumpAndSettle();
    expect(actions, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SDK history and download cards retain their real actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ModernSettingsScope(
          child: Scaffold(
            body: ListView(
              children: [
                SdkLibraryTile(
                  record: const SdkLibraryRecord(
                    providerId: 'whisklet',
                    contentId: 'sample',
                    title: '较长作品名称的真实历史卡片',
                  ),
                  onOpen: () => opened++,
                ),
                DownloadRecordCard(
                  record: DownloadRecord(
                    1,
                    '离线缓存作品',
                    '',
                    'sample',
                    {},
                    DateTime(2026),
                  ),
                  expanded: false,
                  onToggle: () => toggled++,
                  onResumeAll: () {},
                  onDeleteAll: () {},
                  totalSpeed: 0,
                  episodeTileBuilder: () => [],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayraCard), findsNWidgets(2));
    await tester.tap(find.text('较长作品名称的真实历史卡片'));
    await tester.tap(find.text('离线缓存作品'));
    expect(opened, 1);
    expect(toggled, 1);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 760.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'settings render library cards and usable actions $width/$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var changes = 0;
          var actions = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: ModernSettingsScope(
                  child: Scaffold(
                    body: ListView(
                      children: [
                        SettingsSection(
                          tiles: [
                            SettingsTile.switchTile(
                              title: const Text('自动同步'),
                              description: const Text('保留换行说明和系统文字大小'),
                              initialValue: false,
                              onToggle: (_) async => changes++,
                            ),
                          ],
                        ),
                        Center(
                          child: StateActionButton(
                            text: '执行操作',
                            onPressed: () => actions++,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.descendant(
            of: find.byType(SettingsSection),
            matching: find.byType(f.FTileGroup),
          );
          expect(card, findsOneWidget);
          final surface = tester.widget<DecoratedBox>(
            find
                .descendant(of: card, matching: find.byType(DecoratedBox))
                .first,
          );
          final decoration = surface.decoration as ShapeDecoration;
          final expected =
              f.FTheme.neutral.dark.touch.tileGroupStyle.decoration
                  as ShapeDecoration;
          expect(decoration.color, expected.color);
          expect(decoration.shape, expected.shape);
          final action = find.widgetWithText(PlayraButton, '执行操作');
          expect(action, findsOneWidget);
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
          await tester.tap(find.byType(PlayraSwitch));
          await tester.tap(find.text('执行操作'));
          await tester.pumpAndSettle();
          expect(changes, 1);
          expect(actions, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'root dialogs inherit the product surface without a page context',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: playraTheme(ThemeData()),
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [KazumiDialog.observer],
          home: Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                KazumiDialog.show<void>(
                  builder: (_) => PlayraDialog(
                    title: const Text('确认操作'),
                    content: const Text('根弹层保持当前品牌样式'),
                    actions: [
                      TextButton(
                        onPressed: KazumiDialog.dismiss,
                        child: const Text('返回'),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final surfaces = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(f.FDialog),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        surfaces.any(
          (m) =>
              m.decoration is ShapeDecoration &&
              (m.decoration as ShapeDecoration).color ==
                  f.FTheme.neutral.dark.touch.colors.card,
        ),
        isTrue,
      );
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      expect(find.text('确认操作'), findsNothing);
      expect(find.text('打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared sheet keeps close and input reachable above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: playraTheme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showPlayraSheet<void>(
                    context: context,
                    title: '筛选条件',
                    builder: (_) => const SingleChildScrollView(
                      child: Column(
                        children: [
                          TextField(
                            decoration: InputDecoration(labelText: '关键词'),
                          ),
                          SizedBox(height: 600),
                          Text('末项'),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('打开筛选'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留草稿');
      expect(find.text('保留草稿'), findsOneWidget);
      expect(
        tester.getBottomRight(_tooltip('关闭').first).dy,
        lessThanOrEqualTo(380),
      );
      await tester.tap(_tooltip('关闭').first);
      await tester.pumpAndSettle();
      expect(find.text('筛选条件'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _tooltip(String message) => find.byWidgetPredicate(
  (widget) =>
      widget is PlayraIconButton && widget.tooltip == message ||
      widget is Tooltip && widget.message == message,
);
