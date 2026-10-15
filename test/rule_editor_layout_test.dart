import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/plugin_editor/editor_form_widgets.dart';
import 'package:kazumi/pages/plugin_editor/plugin_editor_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

void main() {
  for (final width in [320.0, 390.0, 900.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('规则编辑器 $width / $scale 切换分区保留草稿且不溢出', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final plugin = Plugin.fromJson(
          jsonDecode(File('assets/plugins/DM84.json').readAsStringSync()),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ModernSettingsScope(
              child: SettingsPaneScope(
                embedded: true,
                showBackButton: false,
                onBack: () {},
                child: PluginEditorPage(
                  plugin: plugin,
                  controller: PluginsController(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final name = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is EditorTextField && w.label == '规则名称',
          ),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(name);
        await tester.enterText(name, '保留的规则草稿');
        for (final label in ['搜索', '选集', '高级', '基本']) {
          final tab = find.text(label);
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        expect(tester.widget<TextField>(name).controller!.text, '保留的规则草稿');
        expect(
          find.widgetWithText(OutlinedButton, scale > 1.4 ? '测试' : '测试规则'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
      });
    }
  }
}
