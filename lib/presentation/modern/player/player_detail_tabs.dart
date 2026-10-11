import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 三个稳定标签使用短横线；动画只移动指示器，不缩放文字。
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
    final colors = Theme.of(context).colorScheme;
    final height = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) + 26,
    );
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 3;
          return SizedBox(
            height: height + 3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Semantics(
                            selected: controller.index == i,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: Size(48, height),
                                foregroundColor: controller.index == i
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                                shape: const RoundedRectangleBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                              onPressed: () => controller.animateTo(
                                i,
                                duration:
                                    disableAnimations ||
                                        MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                              ),
                              child: Text(
                                ['详情', '讨论', '评价'][i],
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: controller.index == i
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: .5, color: colors.outline),
                ),
                Positioned(
                  bottom: 0,
                  left: (controller.animation!.value + .5) * width - 10,
                  child: Container(
                    width: 20,
                    height: 3,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
