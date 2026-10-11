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
  Widget build(BuildContext context) {
    final theme = modernHomeTheme(Theme.of(context), forceDark: true);
    return Scaffold(
      body: outlet,
      bottomNavigationBar: Theme(
        data: theme,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.navigationBarTheme.backgroundColor,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          // 外层先消费系统底部安全区，NavigationBar 内部不会再次叠加同一间距。
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: NavigationBar(
              key: const ValueKey('modern-navigation'),
              selectedIndex: selectedIndex,
              onDestinationSelected: selectDestination,
              destinations: destinations,
            ),
          ),
        ),
      ),
    );
  }
}
