import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import '../widgets/modern_page_scaffold.dart';

class ModernCalendarPage extends StatelessWidget {
  const ModernCalendarPage({super.key});

  @override
  Widget build(BuildContext context) => ModernPageScaffold(
    title: '放送日历',
    children: [
      ModernSection(
        title: '安排你的追番时间',
        description: '新版日历布局正在设计。完整时间表目前可以在旧版界面查看。',
        child: OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('选择页面样式'),
          onPressed: () => context.pushNamed('/settings/interface'),
        ),
      ),
      const ModernSection(title: '本周放送', description: '这里将展示日期导航、当日更新和追番状态。'),
    ],
  );
}
