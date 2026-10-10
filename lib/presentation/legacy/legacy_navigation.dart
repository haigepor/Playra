import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/widget/embedded_native_control_area.dart';
import '../shared/tab_shell.dart';

class ScaffoldMenu extends StatelessWidget {
  const ScaffoldMenu({super.key, required this.location});
  final String location;

  @override
  Widget build(BuildContext context) => TabShell(
    location: location,
    builder: (context, index, select, outlet) => LegacyNavigation(
      selectedIndex: index,
      selectDestination: select,
      outlet: outlet,
    ),
  );
}

/// 旧版的导航视图；状态机和 RouterOutlet 由共享 TabShell 持有。
class LegacyNavigation extends StatelessWidget {
  const LegacyNavigation({
    super.key,
    required this.selectedIndex,
    required this.selectDestination,
    required this.outlet,
  });
  final int selectedIndex;
  final ValueChanged<int> selectDestination;
  final Widget outlet;

  @override
  Widget build(BuildContext context) => OrientationBuilder(
    builder: (context, orientation) => orientation == Orientation.portrait
        ? _bottomMenu(context, selectedIndex, selectDestination, outlet)
        : _sideMenu(context, selectedIndex, selectDestination, outlet),
  );

  Widget _styledOutlet(
    BuildContext context,
    Widget outlet, {
    BorderRadius? borderRadius,
  }) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: borderRadius,
    ),
    child: borderRadius == null
        ? outlet
        : ClipRRect(borderRadius: borderRadius, child: outlet),
  );

  Widget _bottomMenu(
    BuildContext context,
    int selectedIndex,
    ValueChanged<int> selectDestination,
    Widget outlet,
  ) {
    return Scaffold(
      body: _styledOutlet(context, outlet),
      bottomNavigationBar: NavigationBar(
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.home),
            icon: Icon(Icons.home_outlined),
            label: '推荐',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.timeline),
            icon: Icon(Icons.timeline_outlined),
            label: '时间表',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.favorite),
            icon: Icon(Icons.favorite_outlined),
            label: '追番',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: selectDestination,
      ),
    );
  }

  Widget _sideMenu(
    BuildContext context,
    int selectedIndex,
    ValueChanged<int> selectDestination,
    Widget outlet,
  ) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              leading: FloatingActionButton(
                elevation: 0,
                heroTag: null,
                onPressed: () => context.pushNamed('/search/'),
                child: const Icon(Icons.search),
              ),
              labelType: NavigationRailLabelType.selected,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.home),
                  icon: Icon(Icons.home_outlined),
                  label: Text('推荐'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.timeline),
                  icon: Icon(Icons.timeline_outlined),
                  label: Text('时间表'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.favorite),
                  icon: Icon(Icons.favorite_border),
                  label: Text('追番'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.settings),
                  icon: Icon(Icons.settings_outlined),
                  label: Text('我的'),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: selectDestination,
            ),
          ),
          Expanded(
            child: _styledOutlet(context, outlet, borderRadius: borderRadius),
          ),
        ],
      ),
    );
  }
}
