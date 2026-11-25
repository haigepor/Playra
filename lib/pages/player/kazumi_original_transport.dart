import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

// Adapted from Kazumi's GPL-3.0 player_transport_bar.dart at commit
// 906b144fbc6abb40b83bccf86354ba1751c316e6:
// https://github.com/Predidit/Kazumi/blob/906b144fbc6abb40b83bccf86354ba1751c316e6/lib/pages/player/player_transport_bar.dart
// Layout and breakpoint adaptations are specific to Playra. The supplied
// widgets own their callbacks, enabled state and accessibility semantics.

enum KazumiTimeLabelPlacement {
  aboveProgress,
  besideProgress,
  afterPlaybackButtons;

  static KazumiTimeLabelPlacement forViewport(
    Size viewport, {
    required bool desktop,
  }) {
    if (desktop) return afterPlaybackButtons;
    if (viewport.longestSide == 0) return aboveProgress;
    final sideLabels =
        viewport.shortestSide >= 600 &&
        viewport.shortestSide / viewport.longestSide >= 9 / 16;
    return sideLabels ? besideProgress : aboveProgress;
  }
}

/// Kazumi's transport layout using Playra's progress-builder contract.
///
/// The caller supplies working controls; this widget never creates feature
/// buttons or handles safe-area insets. Its parent should provide a SafeArea.
class KazumiOriginalTransport extends StatelessWidget {
  const KazumiOriginalTransport({
    super.key,
    required this.compact,
    required this.playPause,
    required this.nextEpisode,
    required this.progressBuilder,
    required this.timeLabel,
    required this.timePlacement,
    required this.controls,
    required this.fullscreen,
  });

  final bool compact;
  final Widget playPause;
  final Widget nextEpisode;
  final Widget Function(TimeLabelLocation location) progressBuilder;
  final Widget timeLabel;
  final KazumiTimeLabelPlacement timePlacement;
  final Widget controls;
  final Widget fullscreen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The original one-line compact layout can overflow at 320dp or when
      // text is enlarged. Split it without shrinking touch targets.
      final stacked =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(12) >= 16;
      if (compact && !stacked) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
          child: Row(
            children: [
              playPause,
              const SizedBox(width: 6),
              Expanded(child: progressBuilder(TimeLabelLocation.none)),
              const SizedBox(width: 10),
              timeLabel,
              const SizedBox(width: 4),
              fullscreen,
            ],
          ),
        );
      }
      if (compact) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Align(
                  alignment: Alignment.center,
                  heightFactor: 1,
                  child: progressBuilder(TimeLabelLocation.none),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
              child: IconTheme.merge(
                data: const IconThemeData(size: 22),
                child: Row(
                  children: [
                    playPause,
                    const SizedBox(width: 2),
                    Expanded(child: timeLabel),
                    fullscreen,
                  ],
                ),
              ),
            ),
          ],
        );
      }
      if (stacked) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: Align(
                  alignment: Alignment.center,
                  heightFactor: 1,
                  child: progressBuilder(TimeLabelLocation.none),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: timeLabel,
              ),
              Row(
                children: [playPause, nextEpisode, const Spacer(), fullscreen],
              ),
              controls,
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (timePlacement == KazumiTimeLabelPlacement.aboveProgress)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 4),
              child: timeLabel,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 26),
              child: Align(
                alignment: Alignment.center,
                heightFactor: 1,
                child: progressBuilder(
                  timePlacement == KazumiTimeLabelPlacement.besideProgress
                      ? TimeLabelLocation.sides
                      : TimeLabelLocation.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
            child: Row(
              children: [
                playPause,
                nextEpisode,
                if (timePlacement ==
                    KazumiTimeLabelPlacement.afterPlaybackButtons)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: timeLabel,
                  ),
                Expanded(child: controls),
                fullscreen,
              ],
            ),
          ),
        ],
      );
    },
  );
}
