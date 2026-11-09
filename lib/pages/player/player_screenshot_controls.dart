import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';

class PlayerScreenshotControls extends StatelessWidget {
  const PlayerScreenshotControls({
    super.key,
    required this.controller,
    required this.onCapture,
    required this.onReview,
  });
  final PlayerScreenshotController controller;
  final VoidCallback onCapture;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayraIconButton(
          tooltip: '截取当前画面',
          onPressed: controller.busy ? null : onCapture,
          icon: controller.capturing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PlayraMedia.foreground,
                  ),
                )
              : const Icon(Icons.photo_camera_outlined, color: PlayraMedia.foreground),
        ),
        if (controller.candidates.isNotEmpty)
          PlayraIconButton(
            tooltip: '挑选截图 · ${controller.candidates.length} 张',
            onPressed: controller.saving ? null : onReview,
            icon: Badge.count(
              count: controller.candidates.length,
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              textColor: Theme.of(context).colorScheme.onSecondaryContainer,
              child: const Icon(Icons.photo_library_outlined, color: PlayraMedia.foreground),
            ),
          ),
      ],
    ),
  );
}
