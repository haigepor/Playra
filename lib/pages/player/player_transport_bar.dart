import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

class PlayerTransportBar extends StatelessWidget {
  const PlayerTransportBar({
    super.key,
    required this.compact,
    required this.playPause,
    required this.nextEpisode,
    required this.progressBuilder,
    required this.timeLabel,
    required this.timeBesideProgress,
    required this.controls,
    required this.fullscreen,
  });

  final bool compact;
  final Widget playPause;
  final Widget nextEpisode;
  final Widget Function(TimeLabelLocation location) progressBuilder;
  final Widget timeLabel;
  final bool timeBesideProgress;
  final Widget controls;
  final Widget fullscreen;

  @override
  Widget build(BuildContext context) => compact
      ? Row(
          children: [
            playPause,
            Expanded(child: progressBuilder(TimeLabelLocation.none)),
            Padding(padding: const EdgeInsets.only(left: 6), child: timeLabel),
            fullscreen,
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(child: progressBuilder(TimeLabelLocation.none)),
                  if (timeBesideProgress) ...[
                    const SizedBox(width: 10),
                    timeLabel,
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  playPause,
                  nextEpisode,
                  if (!timeBesideProgress)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: timeLabel,
                    ),
                  Expanded(child: controls),
                  fullscreen,
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        );
}
