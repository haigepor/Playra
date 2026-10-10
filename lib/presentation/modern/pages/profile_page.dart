import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import '../widgets/modern_page_scaffold.dart';

class ModernProfilePage extends StatelessWidget {
  const ModernProfilePage({super.key});

  @override
  Widget build(BuildContext context) => ModernPageScaffold(
    title: '我的空间',
    children: [
      ModernSection(
        title: '让追番更合心意',
        description: '新版界面处于预览阶段，可以随时切回旧版。',
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.palette_outlined),
          label: const Text('切换页面样式'),
          onPressed: () => context.pushNamed('/settings/interface'),
        ),
      ),
      for (final item in const [
        (Icons.widgets_outlined, '组件实验室', '/ui/components'),
        (Icons.history, '观看历史', '/settings/history/'),
        (Icons.download_outlined, '离线缓存', '/settings/download/'),
        (Icons.extension_outlined, '播放规则', '/settings/plugin/'),
        (Icons.sync, '数据同步', '/settings/sync'),
        (Icons.settings_outlined, '全部设置', '/settings/'),
      ])
        Card(
          child: ListTile(
            leading: Icon(item.$1),
            title: Text(item.$2),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(item.$3),
          ),
        ),
    ],
  );
}
