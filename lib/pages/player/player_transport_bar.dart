import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

enum PlayerTimeLabelPlacement {
  aboveProgress,
  besideProgress,
  afterPlaybackButtons;

  static PlayerTimeLabelPlacement forViewport(
    Size viewport, {
    required bool desktop,
  }) {
    if (desktop) return afterPlaybackButtons;
    final hasRoomForSideLabels =
        viewport.shortestSide >= 600 &&
        viewport.shortestSide / viewport.longestSide >= 9 / 16;
    return hasRoomForSideLabels ? besideProgress : aboveProgress;
  }
}

/// ProgressBar 的位置更新只重绘画面；由当前播放状态更新读屏值。
class PlayerProgressSemantics extends StatelessWidget {
  const PlayerProgressSemantics({
    super.key,
    required this.progress,
    required this.total,
    required this.onSeek,
    required this.child,
  });

  final Duration progress, total;
  final ValueChanged<Duration> onSeek;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = total.inMilliseconds;
    final current = duration > 0
        ? progress.inMilliseconds.clamp(0, duration)
        : 0;
    // 与进度条原有读屏操作保持一致，每次前进或后退总时长的 5%。
    final step = (duration * .05).round();
    String percentage(int value) => '${(value / duration * 100).round()}%';
    final forward = (current + step).clamp(0, duration > 0 ? duration : 0);
    final backward = (current - step).clamp(0, duration > 0 ? duration : 0);
    return Semantics(
      slider: true,
      value: duration > 0 ? percentage(current) : '时长未知',
      increasedValue: duration > 0 ? percentage(forward) : null,
      decreasedValue: duration > 0 ? percentage(backward) : null,
      onIncrease: duration > 0
          ? () => onSeek(Duration(milliseconds: forward))
          : null,
      onDecrease: duration > 0
          ? () => onSeek(Duration(milliseconds: backward))
          : null,
      child: ExcludeSemantics(child: child),
    );
  }
}

class PlayerTransportBar extends StatelessWidget {
  const PlayerTransportBar({
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
  final PlayerTimeLabelPlacement timePlacement;
  final Widget controls;
  final Widget fullscreen;

  @override
  Widget build(BuildContext context) => compact
      ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.lg),
              child: Semantics(
                container: true,
                label: '播放进度',
                child: SizedBox(
                  height: 44,
                  child: progressBuilder(TimeLabelLocation.none),
                ),
              ),
            ),
            Row(
              children: [
                playPause,
                nextEpisode,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.sm),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: timeLabel,
                    ),
                  ),
                ),
                fullscreen,
              ],
            ),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timePlacement == PlayerTimeLabelPlacement.aboveProgress)
              Padding(
                padding: const EdgeInsets.only(left: PlayraSpace.md, bottom: PlayraSpace.md),
                child: timeLabel,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
              child: Semantics(
                container: true,
                label: '播放进度',
                child: progressBuilder(
                  timePlacement == PlayerTimeLabelPlacement.besideProgress
                      ? TimeLabelLocation.sides
                      : TimeLabelLocation.none,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
              child: Row(
                children: [
                  playPause,
                  nextEpisode,
                  if (timePlacement ==
                      PlayerTimeLabelPlacement.afterPlaybackButtons)
                    Padding(
                      padding: const EdgeInsets.only(left: PlayraSpace.md),
                      child: timeLabel,
                    ),
                  Expanded(child: controls),
                  fullscreen,
                ],
              ),
            ),
            if (timePlacement != PlayerTimeLabelPlacement.aboveProgress)
              const SizedBox(height: PlayraSpace.compact),
          ],
        );
}
