import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';

/// The embedded video stage stays rectangular, including before playback.
class SdkPlaybackHero extends StatelessWidget {
  const SdkPlaybackHero({
    super.key,
    required this.cover,
    required this.backdrop,
    required this.title,
    required this.episodeLabel,
    this.onPlay,
  });
  final String cover, backdrop, title, episodeLabel;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => ColoredBox(
      color: PlayraMedia.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backdrop.isNotEmpty)
            NetworkImgLayer(
              src: backdrop,
              width: bounds.maxWidth,
              height: bounds.maxHeight,
              fit: BoxFit.cover,
              type: 'bg',
              borderRadius: BorderRadius.zero,
            )
          else if (cover.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: NetworkImgLayer(
                src: cover,
                fallbackTitle: title,
                width: bounds.maxHeight * .7,
                height: bounds.maxHeight,
                fit: BoxFit.contain,
                borderRadius: BorderRadius.zero,
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [PlayraMedia.scrimStrong, PlayraMedia.scrimSoft],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(PlayraSpace.lg),
              child: onPlay == null
                  ? Semantics(
                      liveRegion: true,
                      child: Text(
                        episodeLabel,
                        style: const TextStyle(
                          color: PlayraMedia.foreground,
                          fontSize: PlayraType.label,
                        ),
                      ),
                    )
                  : PlayraButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        episodeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
