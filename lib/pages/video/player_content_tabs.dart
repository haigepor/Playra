import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:flutter/material.dart';

class PlayerContentTabs extends StatelessWidget {
  const PlayerContentTabs({
    super.key,
    required this.controller,
    required this.onEpisodesSelected,
  });

  final TabController controller;
  final VoidCallback onEpisodesSelected;

  @override
  Widget build(BuildContext context) {
    return PlayraTabBar(
      controller: controller,
      onTap: (index) {
        if (index == 0) onEpisodesSelected();
      },
      tabs: const [
        Tab(text: '选集'),
        Tab(text: '评论'),
      ],
    );
  }
}
