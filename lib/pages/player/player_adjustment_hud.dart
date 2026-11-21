import 'package:flutter/material.dart';
import 'package:kazumi/utils/format.dart';

enum PlayerAdjustmentHudType { brightness, volume }

const _accent = Color(0xffc5b2ff);
const _digits = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

class _GestureFeedback extends StatelessWidget {
  const _GestureFeedback({
    required this.child,
    required this.visible,
    required this.disableAnimations,
  });
  final Widget child;
  final bool visible;
  final bool disableAnimations;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSwitcher(
      duration: Duration(milliseconds: disableAnimations ? 0 : 110),
      child: visible
          ? Material(
              color: const Color(0xe817171d),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: child,
              ),
            )
          : const SizedBox.shrink(),
    ),
  );
}

class PlayerAdjustmentHud extends StatelessWidget {
  const PlayerAdjustmentHud({
    super.key,
    required this.visible,
    required this.type,
    required this.value,
    this.disableAnimations = false,
  });
  final bool visible;
  final PlayerAdjustmentHudType type;
  final double value;
  final bool disableAnimations;
  @override
  Widget build(BuildContext context) {
    final volume = type == PlayerAdjustmentHudType.volume;
    final level = (volume ? value / 100 : value).clamp(0.0, 1.0);
    return _GestureFeedback(
      visible: visible,
      disableAnimations: disableAnimations,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            volume
                ? (level == 0
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined)
                : Icons.light_mode_outlined,
            size: 19,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            volume ? '音量' : '亮度',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: LinearProgressIndicator(
              value: level,
              minHeight: 3,
              color: _accent,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: 9),
          Text('${(level * 100).round()}%', style: _digits),
        ],
      ),
    );
  }
}

class PlayerSeekHud extends StatelessWidget {
  const PlayerSeekHud({
    super.key,
    required this.visible,
    required this.currentPosition,
    required this.playerPosition,
    required this.duration,
    required this.direction,
    this.cancelPending = false,
    this.disableAnimations = false,
  });
  final bool visible, cancelPending, disableAnimations;
  final Duration currentPosition, playerPosition, duration;
  final int direction;
  @override
  Widget build(BuildContext context) {
    final delta = (currentPosition - playerPosition).inSeconds;
    final forward = delta == 0 ? direction >= 0 : delta > 0;
    return _GestureFeedback(
      visible: visible,
      disableAnimations: disableAnimations,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                cancelPending
                    ? Icons.undo_rounded
                    : forward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: _accent,
                size: 20,
              ),
              const SizedBox(width: 7),
              Text(
                durationToString(currentPosition),
                style: _digits.copyWith(fontSize: 18),
              ),
              Text(
                ' / ${durationToString(duration)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Text(
            cancelPending ? '松开取消' : '${forward ? '+' : '−'}${delta.abs()} 秒',
            style: const TextStyle(color: _accent, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class PlayerSpeedHud extends StatelessWidget {
  const PlayerSpeedHud({
    super.key,
    required this.visible,
    required this.speed,
    this.disableAnimations = false,
  });
  final bool visible, disableAnimations;
  final double speed;
  @override
  Widget build(BuildContext context) => _GestureFeedback(
    visible: visible,
    disableAnimations: disableAnimations,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.fast_forward_rounded, color: _accent, size: 19),
        const SizedBox(width: 6),
        Text('$speed×', style: _digits),
        const SizedBox(width: 8),
        const Text(
          '松手恢复',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );
}
