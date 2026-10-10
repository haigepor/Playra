import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/services/storage/storage.dart';
import '../interface_style.dart';

class InterfaceStyleTile extends StatelessWidget {
  const InterfaceStyleTile({super.key});

  Future<void> _change(BuildContext context, InterfaceStyle next) async {
    final controller = context.read<InterfaceStyleController>();
    final current = context.routeState(listen: false).uri.path;
    final returnTo = current.startsWith('/tab/')
        ? current
        : GStorage.getSetting(SettingsKeys.defaultStartupPage);
    try {
      final changed = await controller.setStyle(next);
      // 清除旧的页面栈，避免返回键重新进入切换前的页面；根服务继续运行。
      if (changed && context.mounted) {
        context.navigate(returnTo);
      }
    } catch (_) {
      if (context.mounted) {
        KazumiDialog.showToast(message: '页面样式保存失败，请重试', context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InterfaceStyleController>();
    return SettingsDropdownTile<InterfaceStyle>(
      leading: Icons.layers_outlined,
      title: const Text('页面样式'),
      description: const Text('新版为预览界面，切换后保留收藏、历史和下载；当前页面会重新打开'),
      value: controller.style,
      enabled: !controller.isSaving,
      options: {for (final style in InterfaceStyle.values) style: style.label},
      onChanged: (value) => _change(context, value),
    );
  }
}
