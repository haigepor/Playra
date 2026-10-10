import 'package:flutter/material.dart';
import 'package:kazumi/presentation/legacy/legacy_navigation.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';

class IndexPage extends StatefulWidget {
  const IndexPage({super.key, required this.location});

  final String location;

  @override
  State<IndexPage> createState() => _IndexPageState();
}

class _IndexPageState extends State<IndexPage> with WidgetsBindingObserver {
  @override
  Widget build(BuildContext context) {
    // 状态机必须位于样式选择之外，切换导航外观时保留当前标签与 outlet。
    return TabShell(
      location: widget.location,
      builder: (context, index, select, outlet) => InterfacePageHost(
        legacy: (_) => LegacyNavigation(
          selectedIndex: index,
          selectDestination: select,
          outlet: outlet,
        ),
        modern: (_) => ModernShell(
          selectedIndex: index,
          selectDestination: select,
          outlet: outlet,
        ),
      ),
    );
  }
}
