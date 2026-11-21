import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/assets.dart' show FLucideIcons;

import 'package:kazumi/pages/calendar/calendar_page.dart';
import 'package:kazumi/pages/discover/discover_page.dart';
import 'package:kazumi/pages/favorites/favorites_page.dart';
import 'package:kazumi/pages/profile/profile_page.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/shell/playra_bottom_nav.dart';
import 'package:kazumi/shell/playra_side_rail.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const _destinations = [
    PlayraNavDestination(
      label: '发现',
      icon: FLucideIcons.compass,
      selectedIcon: FLucideIcons.compass,
    ),
    PlayraNavDestination(
      label: '日历',
      icon: FLucideIcons.calendarDays,
      selectedIcon: FLucideIcons.calendarDays,
    ),
    PlayraNavDestination(
      label: '追番',
      icon: FLucideIcons.bookmark,
      selectedIcon: FLucideIcons.bookmark,
    ),
    PlayraNavDestination(
      label: '我的',
      icon: FLucideIcons.userRound,
      selectedIcon: FLucideIcons.userRound,
    ),
  ];

  void _selectTab(int index) {
    if (index < 0 || index >= _destinations.length || index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final overlayStyle = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use the shortest side so a landscape phone (for example 844×390)
          // keeps the bottom navigation instead of inheriting the tablet rail.
          final wide =
              MediaQuery.sizeOf(context).shortestSide >=
              PlayraLayout.compactWidth;
          final pages = <Widget>[
            DiscoverPage(onSelectTab: _selectTab),
            const CalendarPage(),
            FavoritesPage(onDiscover: () => _selectTab(0)),
            const ProfilePage(),
          ];
          return Scaffold(
            extendBody: false,
            body: SafeArea(
              bottom: false,
              child: wide
                  ? Row(
                      children: [
                        PlayraSideRail(
                          selectedIndex: _index,
                          onSelected: _selectTab,
                        ),
                        Expanded(
                          child: IndexedStack(index: _index, children: pages),
                        ),
                      ],
                    )
                  : IndexedStack(index: _index, children: pages),
            ),
            bottomNavigationBar: wide
                ? null
                : PlayraBottomNav(
                    destinations: _destinations,
                    selectedIndex: _index,
                    onSelected: _selectTab,
                  ),
          );
        },
      ),
    );
  }
}
