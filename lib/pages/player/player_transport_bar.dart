import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

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
      label: '播放进度',
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
  Widget build(BuildContext context) {
    if (compact && MediaQuery.textScalerOf(context).scale(12) >= 16) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 44, child: progressBuilder(TimeLabelLocation.none)),
          Row(
            children: [
              playPause,
              nextEpisode,
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: timeLabel,
                ),
              ),
              fullscreen,
            ],
          ),
        ],
      );
    }
    return compact
        ? Row(
            children: [
              playPause,
              Expanded(child: progressBuilder(TimeLabelLocation.none)),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: timeLabel,
              ),
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
}
