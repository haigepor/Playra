import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

class RouteErrorPage extends StatelessWidget {
  const RouteErrorPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // 已适配的设置子树沿用现有错误呈现，避免扩大本轮样式范围。
    if (ModernSettingsScope.isActiveOf(context)) return _legacy(context);
    return InterfacePageHost(
      legacy: _legacy,
      modern: (_) => ModernSecondaryScope(
        child: Scaffold(
          body: SecondaryFailureView(
            title: '无法打开页面',
            message: message,
            action: () => context.navigate('/tab/popular/'),
          ),
        ),
      ),
    );
  }

  Widget _legacy(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('Kazumi'),
      body: GeneralErrorWidget(
        title: '无法打开页面',
        errMsg: message,
        actions: [
          StateActionButton(
            onPressed: () => context.navigate('/tab/popular/'),
            icon: Icons.home_outlined,
            text: '返回首页',
          ),
        ],
      ),
    );
  }
}
