import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/shell/placeholder_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: '日历',
    ),
    NavigationDestination(
      icon: Icon(Icons.bookmark_outline),
      selectedIcon: Icon(Icons.bookmark),
      label: '追番',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppBrand.name),
        actions: [
          IconButton(
            tooltip: '播放器演示',
            onPressed: () => context.pushNamed('/player'),
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          PlaceholderPage(
            title: '发现',
            description: '新数据源接入后，这里承载首页推荐、分类和搜索入口。当前保持空壳，不请求任何来源。',
            icon: Icons.explore_outlined,
            action: FilledButton.icon(
              onPressed: () => context.pushNamed('/player'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('打开播放器演示'),
            ),
          ),
          const PlaceholderPage(
            title: '日历',
            description: '待新来源提供排期能力后接入。',
            icon: Icons.calendar_month_outlined,
          ),
          const PlaceholderPage(
            title: '追番',
            description: '本地个人库 schema 已重置，等待新数据模型接入。',
            icon: Icons.bookmark_outline,
          ),
          const PlaceholderPage(
            title: '我的',
            description: '播放设置、网络代理和主题入口将在这里重新实现。',
            icon: Icons.person_outline,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }
}
