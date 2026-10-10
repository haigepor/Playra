import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import '../widgets/modern_page_scaffold.dart';

class ModernLibraryPage extends StatefulWidget {
  const ModernLibraryPage({super.key, required this.controller});
  final CollectController controller;

  @override
  State<ModernLibraryPage> createState() => _ModernLibraryPageState();
}

class _ModernLibraryPageState extends State<ModernLibraryPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadCollectibles();
  }

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final entries = widget.controller.collectibles.toList();
      return ModernPageScaffold(
        title: '我的追番',
        children: [
          ModernSection(
            title: '${entries.length} 部收藏',
            description: '切换界面时，收藏和观看记录会一直保留。',
          ),
          if (entries.isEmpty)
            const ModernSection(
              title: '还没有收藏',
              description: '搜索感兴趣的番剧，在详情页添加到追番。',
            ),
          for (final entry in entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(
                  entry.bangumiItem.nameCn.isEmpty
                      ? entry.bangumiItem.name
                      : entry.bangumiItem.nameCn,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.pushNamed('/info/', arguments: entry.bangumiItem),
              ),
            ),
        ],
      );
    },
  );
}
