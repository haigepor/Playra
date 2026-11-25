import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/player/web_player_surface.dart';

/// Readable on both light and dark video frames without relying on a box.
const playerSubtitleStyle = TextStyle(
  color: PlayraMedia.foreground,
  fontSize: PlayraType.title,
  decoration: TextDecoration.none,
  fontWeight: FontWeight.w600,
  shadows: [
    Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black),
    Shadow(offset: Offset(-1, -1), blurRadius: 4, color: Colors.black),
  ],
);

class PlayerItemSurface extends StatefulWidget {
  const PlayerItemSurface({
    super.key,
    required this.playerController,
    this.onNext,
    this.onDanmaku,
  });

  final PlayerController playerController;
  final VoidCallback? onNext, onDanmaku;

  @override
  State<PlayerItemSurface> createState() => _PlayerItemSurfaceState();
}

class _PlayerItemSurfaceState extends State<PlayerItemSurface> {
  @override
  Widget build(BuildContext context) {
    final playerController = widget.playerController;
    return Observer(
      builder: (context) {
        if (playerController.playback.loading ||
            playerController.playback.videoController == null) {
          return Container(
            color: PlayraMedia.canvas,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final aspectRatioMode = playerController.panel.aspectRatioMode;
        final Widget video = kIsWeb
            ? WebPlayerSurface(
                controller: playerController.playback.videoController!,
                fit: aspectRatioMode.fit,
                onNext: widget.onNext,
                onDanmaku: widget.onDanmaku,
              )
            : Video(
                controller: playerController.playback.videoController!,
                controls: NoVideoControls,
                pauseUponEnteringBackgroundMode: false,
                fit: aspectRatioMode.fit,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: playerSubtitleStyle,
                  textAlign: TextAlign.center,
                  padding: const EdgeInsets.all(PlayraSpace.xxl),
                ),
              );

        final frameAspectRatio = aspectRatioMode.frameAspectRatio;
        if (frameAspectRatio == null) {
          return video;
        }
        return AspectRatio(aspectRatio: frameAspectRatio, child: video);
      },
    );
  }
}
