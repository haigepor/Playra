import 'package:kazumi/services/platform/platform_io.dart';

import 'package:flutter/material.dart';
import 'package:kazumi/presentation/interface_style.dart';
import 'package:kazumi/services/platform/platform_paths.dart';

import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

class StorageErrorPage extends StatelessWidget {
  const StorageErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 存储失败时控制器尚未创建，直接使用局部主题，不能读取 GStorage。
    return InterfaceStyleController.supportsPlatform(Theme.of(context).platform)
        ? ModernSecondaryScope(child: Builder(builder: _page))
        : _page(context);
  }

  Widget _page(BuildContext context) {
    final modern = ModernSecondaryScope.isActiveOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(modern ? '启动遇到问题' : '内部错误')),
      body: FutureBuilder<Directory>(
        future: getApplicationSupportDirectory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final path = snapshot.data?.path ?? '未知路径';
            if (modern) {
              return SecondaryFailureView(
                title: '无法初始化本地存储',
                message: '应用暂时无法读取本地数据，请退出后检查存储权限与可用空间。',
                details: '当前存储位置：\n$path\n\n可在退出后删除该目录以重置本地存储，此操作会清除本地数据。',
                actionLabel: '退出程序',
                actionIcon: LucideIcons.logOut,
                action: () => exit(0),
              );
            }
            return GeneralErrorWidget(
              title: '无法初始化本地存储',
              icon: Icons.storage_rounded,
              errMsg: '当前存储位置：\n$path\n\n可在退出后删除该目录以重置本地存储，此操作会清除本地数据。',
              actions: [
                StateActionButton(
                  onPressed: () {
                    exit(0);
                  },
                  text: '退出程序',
                  icon: Icons.close_rounded,
                ),
              ],
            );
          } else {
            return const Center(child: LoadingIndicator());
          }
        },
      ),
    );
  }
}
