import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/shell/playra_bottom_nav.dart';

const _destinations = [
  PlayraNavDestination(
    label: '发现',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore_rounded,
  ),
  PlayraNavDestination(
    label: '日历',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month_rounded,
  ),
  PlayraNavDestination(
    label: '追番',
    icon: Icons.bookmark_outline_rounded,
    selectedIcon: Icons.bookmark_rounded,
  ),
  PlayraNavDestination(
    label: '我的',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

void main() {
  testWidgets('bottom dock shows all destinations and reports selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PlayraBottomNav(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (index) => selected = index,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('发现'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('追番'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('日历'));
    await tester.pump();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}
