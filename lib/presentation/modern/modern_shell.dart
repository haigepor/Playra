import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'home/home_theme.dart';
import '../theme/playra_forui_theme.dart';
import '../theme/playra_tokens.dart';

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
  Widget build(BuildContext context) => Theme(
    data: modernHomeTheme(Theme.of(context), forceDark: true),
    child: PlayraForuiScope(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= PlayraLayout.compactWidth;
          final design = f.FTheme.of(context);
          return Scaffold(
            backgroundColor: design.colors.background,
            extendBody: false,
            body: Row(
              children: [
                if (wide) _navigation(context, bounds.maxWidth),
                Expanded(key: const ValueKey('modern-content'), child: outlet),
              ],
            ),
            bottomNavigationBar:
                wide || MediaQuery.viewInsetsOf(context).bottom > 0
                ? null
                : f.FBottomNavigationBar(
                    key: const ValueKey('modern-navigation'),
                    index: selectedIndex,
                    onChange: selectDestination,
                    safeAreaBottom: true,
                    style: f.FBottomNavigationBarStyleDelta.delta(
                      decoration: f.DecorationDelta.value(
                        BoxDecoration(
                          color: design.colors.background,
                          border: Border(
                            top: BorderSide(color: design.colors.border),
                          ),
                        ),
                      ),
                    ),
                    children: [
                      for (final destination in destinations)
                        f.FBottomNavigationBarItem(
                          icon: destination.icon,
                          label: Text(destination.label),
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
  );

  Widget _navigation(BuildContext context, double width) {
    final design = f.FTheme.of(context);
    final expanded = width >= PlayraLayout.catalogWidth;
    return Container(
      key: const ValueKey('modern-side-navigation'),
      width: expanded ? 208 : 88,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: design.colors.border)),
      ),
      child: SafeArea(
        child: expanded
            ? f.FSidebar(
                header: Padding(
                  padding: const EdgeInsets.all(PlayraSpace.xxl),
                  child: Text('Playra', style: design.typography.display.xl),
                ),
                children: [
                  f.FSidebarGroup(
                    children: [
                      for (final entry in destinations.indexed)
                        f.FSidebarItem(
                          icon: entry.$2.icon,
                          label: Text(entry.$2.label),
                          selected: selectedIndex == entry.$1,
                          onPress: () => selectDestination(entry.$1),
                        ),
                    ],
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayraSpace.sm,
                  vertical: PlayraSpace.lg,
                ),
                children: [
                  for (final entry in destinations.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: PlayraSpace.sm),
                      child: f.FButton(
                        selected: selectedIndex == entry.$1,
                        variant: selectedIndex == entry.$1
                            ? f.FButtonVariant.secondary
                            : f.FButtonVariant.ghost,
                        onPress: () => selectDestination(entry.$1),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            entry.$2.icon,
                            const SizedBox(height: PlayraSpace.xs),
                            Text(
                              entry.$2.label,
                              style: design.typography.body.xs2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
