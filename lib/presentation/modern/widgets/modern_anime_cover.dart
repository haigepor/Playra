import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

/// 日历与追番共用封面比例和评分样式，评分仅在有投票时展示。
class ModernAnimeCover extends StatelessWidget {
  const ModernAnimeCover({
    super.key,
    required this.src,
    required this.score,
    required this.votes,
    this.showRating = true,
    this.hovered = false,
  });

  final String src;
  final double score;
  final int votes;
  final bool showRating, hovered;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 82,
    height: 122,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedScale(
            scale: hovered ? 1.035 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: NetworkImgLayer(
              src: src,
              width: 82,
              height: 122,
              borderRadius: BorderRadius.zero,
            ),
          ),
          if (showRating && score > 0 && votes > 0)
            Positioned(
              left: 5,
              bottom: 5,
              child: Semantics(
                label: '评分 ${score.toStringAsFixed(1)}',
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xe6222630),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.star,
                          size: 10,
                          color: Color(0xffffd484),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          score.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xffffd484),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
