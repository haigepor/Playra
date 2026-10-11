import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
// 当前 7.1.0 只在此库提供保留根页面的 URL 上报；升级依赖时需复验导航测试。
// ignore: implementation_imports
import 'package:flutter_modular/src/navigation/modular_router_delegate.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/router.dart';
import 'package:kazumi/presentation/interface_style.dart';
import 'mobile_tab_view.dart';

typedef TabShellBuilder =
    Widget Function(
      BuildContext context,
      int selectedIndex,
      ValueChanged<int> selectDestination,
      Widget outlet,
    );

/// 子页面借用现有壳层切换根 Tab，避免叠加第二个导航壳层。
class TabDestinationScope extends InheritedWidget {
  const TabDestinationScope({
    super.key,
    required this.selectDestination,
    required super.child,
  });
  final ValueChanged<int> selectDestination;
  static ValueChanged<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TabDestinationScope>()
      ?.selectDestination;
  static ValueChanged<int> of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TabDestinationScope>()!
      .selectDestination;
  @override
  bool updateShouldNotify(TabDestinationScope oldWidget) =>
      selectDestination != oldWidget.selectDestination;
}

class TabShell extends StatefulWidget {
  const TabShell({
    super.key,
    required this.location,
    required this.builder,
    this.mobilePageBuilders,
  });

  final String location;
  final TabShellBuilder builder;
  final List<WidgetBuilder>? mobilePageBuilders;

  @override
  State<TabShell> createState() => _TabShell();
}

class _TabShell extends State<TabShell> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;
  bool _mobilePaging = false;

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant TabShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    if (index < 0 || index >= menu.menuList.length) return;
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    if (_mobilePaging) {
      setState(() => _selectedIndex = index);
      // 7.1.0 的公开导航会替换整棵根路由；只报告 Tab URL 才能保留缓存页。
      // 该适配局限于壳层，搜索、详情、设置等仍通过标准 push/pop 调用。
      final delegate = Router.of(context).routerDelegate;
      if (delegate is ModularRouterDelegate) {
        delegate.reportNestedLocation(Uri.parse('/tab${menu.getPath(index)}/'));
      }
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
  }

  void _handleSystemBack(BuildContext context) {
    if (!_mobilePaging && (_outletKey.currentState?.maybePop() ?? false)) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.watch<InterfaceStyleController>().style;
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final usePager =
        mobile &&
        style == InterfaceStyle.modern &&
        widget.mobilePageBuilders != null;
    if (usePager) {
      _selectedIndex = menu.indexForPath(context.routeState().uri.path);
    }
    if (_mobilePaging && !usePager) {
      // 从缓存壳层退回旧版时，恢复当前 Tab，而非根路由最初的 seed 页面。
      final index = _selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_mobilePaging) {
          _outletKey.currentState?.navigate('/tab${menu.getPath(index)}/');
        }
      });
    }
    _mobilePaging = usePager;
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: TabDestinationScope(
          selectDestination: _selectDestination,
          child: widget.builder(
            context,
            _selectedIndex,
            _selectDestination,
            usePager
                ? MobileTabView(
                    selectedIndex: _selectedIndex,
                    pageBuilders: widget.mobilePageBuilders!,
                    isCovered: _isCovered,
                  )
                : _outlet(),
          ),
        ),
      ),
    );
  }

  Widget _outlet() => NotificationListener<NavigationNotification>(
    onNotification: (notification) => !notification.canHandlePop,
    child: RouterOutlet(key: _outletKey),
  );
}
