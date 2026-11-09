import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('count=$count'),
    ),
  );
}

void main() {
  testWidgets('last page action stays above navigation and system safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ModernShell(
          selectedIndex: 3,
          selectDestination: (_) {},
          outlet: ListView(
            children: [
              for (var i = 0; i < 20; i++)
                SizedBox(height: 60, child: Text('$i')),
              TextButton(
                onPressed: () => opened = true,
                child: const Text('关于应用'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('关于应用'), 400);
    await tester.pumpAndSettle();
    final action = find.widgetWithText(TextButton, '关于应用');
    expect(
      tester.getBottomRight(action).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byType(f.FBottomNavigationBar)).dy,
      ),
    );
    await tester.tap(action);
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adaptive navigation preserves page state and destination', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => ModernShell(
            selectedIndex: selected,
            selectDestination: (index) => update(() => selected = index),
            outlet: const _Counter(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('count=0'));
    await tester.pumpAndSettle();
    expect(find.byType(f.FBottomNavigationBar), findsOneWidget);
    expect(tester.getSize(find.byType(f.FBottomNavigationBar)).width, 360);

    for (final width in [600.0, 800.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 853);
      await tester.pumpAndSettle();
      expect(find.text('count=1'), findsOneWidget);
      expect(find.byType(f.FBottomNavigationBar), findsNothing);
      expect(
        find.byKey(const ValueKey('modern-side-navigation')),
        findsOneWidget,
      );
      await tester.tap(find.text('追番'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    }

    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text('count=1'), findsOneWidget);
    expect(tester.getSize(find.byType(f.FBottomNavigationBar)).width, 320);
    expect(
      tester
          .widget<f.FBottomNavigationBar>(find.byType(f.FBottomNavigationBar))
          .index,
      2,
    );
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });
}
