import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:kazumi/presentation/theme/playra_forui_theme.dart';
import 'package:kazumi/presentation/theme/playra_theme.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/navigation.dart';

void main() {
  testWidgets('Forui form retains validation, controller and IME submission', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => PlayraForuiScope(child: child!),
        home: Scaffold(
          body: Form(
            key: form,
            child: PlayraTextField.form(
              controller: controller,
              decoration: const InputDecoration(labelText: '服务器地址'),
              textInputAction: TextInputAction.done,
              validator: (value) =>
                  value == null || value.isEmpty ? '请输入地址' : null,
              onFieldSubmitted: (value) => submitted = value,
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('请输入地址'), findsOneWidget);
    await tester.enterText(
      find.byType(EditableText),
      'https://example.com/dav',
    );
    expect(form.currentState!.validate(), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, controller.text);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Forui radios retain group arrow-key navigation', (tester) async {
    var selection = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => PlayraForuiScope(child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => RadioGroup<int>(
              groupValue: selection,
              onChanged: (value) => update(() => selection = value!),
              child: Column(
                children: [
                  for (var value = 0; value < 2; value++)
                    PlayraRadioTile<int>(
                      value: value,
                      title: Text('选项 $value'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<RawRadio<int>>(find.byType(RawRadio<int>).first)
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selection, 1);
    expect(find.byType(FRadio), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Forui toast actions execute once and leave the current route open',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [KazumiDialog.observer],
          builder: (_, child) =>
              PlayraForuiScope(withOverlays: true, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => PlayraButton(
                onPressed: () => KazumiDialog.showToast(
                  context: context,
                  message: '已完成',
                  showActionButton: true,
                  actionLabel: '查看结果',
                  onActionPressed: () => actions++,
                ),
                child: const Text('操作'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('操作'));
      await tester.pumpAndSettle();
      expect(find.byType(FToast), findsOneWidget);
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(find.byType(FToast), findsNothing);
      expect(find.text('操作'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Forui controls work inside the existing Material router foundation',
    (tester) async {
      var presses = 0;
      var selected = false;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: playraTheme(ThemeData()),
          builder: (context, child) =>
              PlayraForuiScope(withOverlays: true, child: child!),
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: ListView(
                children: [
                  FCard(
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Forui card'),
                    ),
                  ),
                  FButton(onPress: () => presses++, child: const Text('Apply')),
                  FTextField(
                    control: FTextFieldControl.managed(controller: controller),
                    hint: 'Search',
                  ),
                  FSwitch(
                    value: selected,
                    onChange: (value) => update(() => selected = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.enterText(find.byType(EditableText), 'query');
      await tester.tap(find.byType(FSwitch));
      await tester.pumpAndSettle();
      expect(presses, 1);
      expect(controller.text, 'query');
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
