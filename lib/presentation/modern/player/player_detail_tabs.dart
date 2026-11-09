import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

/// TabController remains responsible for swipe and route synchronization.
class PlayerDetailTabs extends StatelessWidget {
  const PlayerDetailTabs({
    super.key,
    required this.controller,
    this.disableAnimations = false,
  });
  final TabController controller;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final tabs = PlayraTabBar(
      controller: controller,
      tabs: const [
        Tab(text: '详情'),
        Tab(text: '讨论'),
        Tab(text: '评价'),
      ],
    );
    return disableAnimations
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: tabs,
          )
        : tabs;
  }
}
