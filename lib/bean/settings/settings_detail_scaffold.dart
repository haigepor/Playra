import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/settings/modern_back_button.dart';

class SettingsPaneScope extends InheritedWidget {
  const SettingsPaneScope({
    super.key,
    required this.embedded,
    required this.showBackButton,
    required this.onBack,
    required super.child,
  });

  final bool embedded;
  final bool showBackButton;
  final VoidCallback onBack;

  static SettingsPaneScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();
  }

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) {
    return embedded != oldWidget.embedded ||
        showBackButton != oldWidget.showBackButton ||
        onBack != oldWidget.onBack;
  }
}

class SettingsDetailScaffold extends StatelessWidget {
  const SettingsDetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsPaneScope.of(context);
    final modern = ModernSettingsScope.isActiveOf(context);
    final PreferredSizeWidget appBar;

    if (scope != null && scope.embedded) {
      final paneLeading =
          leading ??
          ((scope.showBackButton ||
                  // 嵌套 push 不一定更新设置壳层 location，直接读取内层返回栈。
                  (RouterOutlet.of(context)?.canPop ?? false) ||
                  (ModalRoute.of(context)?.impliesAppBarDismissal ?? false))
              ? modern
                    ? ModernBackButton(onPressed: scope.onBack)
                    : BackButton(onPressed: scope.onBack)
              : null);
      appBar = AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: modern ? 52 : 64,
        titleSpacing: paneLeading == null
            ? 24
            : NavigationToolbar.kMiddleSpacing,
        leading: paneLeading,
        title: title,
        titleTextStyle: modern
            ? Theme.of(context).appBarTheme.titleTextStyle
            : Theme.of(context).textTheme.headlineSmall,
        actions: actions,
      );
    } else {
      appBar = SysAppBar(
        toolbarHeight: modern ? 52 : null,
        title: title,
        actions: actions,
        leading:
            leading ??
            (scope == null ? null : BackButton(onPressed: scope.onBack)),
      );
    }

    // Keep routed panes opaque during transitions.
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
