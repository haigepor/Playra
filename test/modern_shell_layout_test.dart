import 'package:flutter/material.dart';
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
  testWidgets(
    'floating navigation retains the current page at phone and tablet widths',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => ModernShell(
              selectedIndex: selected,
              selectDestination: (index) => setState(() => selected = index),
              outlet: const _Counter(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('count=0'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      tester.view.physicalSize = const Size(1280, 853);
      await tester.pumpAndSettle();
      expect(find.text('count=1'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.getSize(find.byType(NavigationBar)).width, 440);
      expect(
        tester.getBottomRight(find.byType(NavigationBar)).dy,
        lessThan(853),
      );
      await tester.tap(find.text('追番'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      tester.view.physicalSize = const Size(600, 960);
      await tester.pumpAndSettle();
      expect(find.text('count=1'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.byType(NavigationRail), findsNothing);
      final dock = tester.getRect(find.byType(NavigationBar));
      await tester.dragFrom(
        Offset(dock.left + dock.width * .625, dock.center.dy),
        Offset(-dock.width * .5, 0),
      );
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(find.text('count=1'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 700);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(NavigationBar)).width, 288);
      expect(tester.takeException(), isNull);
    },
  );
}
