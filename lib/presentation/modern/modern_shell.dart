import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'home/home_theme.dart';

class ModernShell extends StatelessWidget {
  const ModernShell({
    super.key,
    required this.selectedIndex,
    required this.selectDestination,
    required this.outlet,
  });
  final int selectedIndex;
  final ValueChanged<int> selectDestination;
  final Widget outlet;

  static const destinations = [
    NavigationDestination(icon: Icon(LucideIcons.compass), label: '发现'),
    NavigationDestination(icon: Icon(LucideIcons.calendarDays), label: '日历'),
    NavigationDestination(icon: Icon(LucideIcons.bookmark), label: '追番'),
    NavigationDestination(icon: Icon(LucideIcons.userRound), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: outlet,
    bottomNavigationBar: Theme(
      data: modernHomeTheme(Theme.of(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: modernHomeTheme(
                Theme.of(context),
              ).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          key: const ValueKey('modern-navigation'),
          selectedIndex: selectedIndex,
          onDestinationSelected: selectDestination,
          destinations: destinations,
        ),
      ),
    ),
  );
}
