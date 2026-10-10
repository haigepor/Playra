import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'interface_style.dart';
import 'modern/modern_theme.dart';

/// 路由只在这里选择呈现版本，两套页面不同时挂载。
class InterfacePageHost extends StatelessWidget {
  const InterfacePageHost({
    super.key,
    required this.legacy,
    required this.modern,
  });

  final WidgetBuilder legacy;
  final WidgetBuilder modern;

  @override
  Widget build(BuildContext context) {
    final style = context.watch<InterfaceStyleController>().style;
    final child = style == InterfaceStyle.modern
        ? Theme(data: modernTheme(Theme.of(context)), child: modern(context))
        : legacy(context);
    // 切换时释放旧页面的滚动/筛选状态，根模块的业务状态不受影响。
    return KeyedSubtree(key: ValueKey(style), child: child);
  }
}
