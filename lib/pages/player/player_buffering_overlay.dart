import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:media_kit/media_kit.dart';

/// Shared loading surface for native anime and film playback.
class PlayerBufferingOverlay extends StatefulWidget {
  const PlayerBufferingOverlay({
    super.key,
    required this.player,
    required this.buffering,
    required this.resolving,
    this.resolvingLabel,
  });

  final Player? player;
  final bool buffering;
  final bool resolving;
  final String? resolvingLabel;

  @override
  State<PlayerBufferingOverlay> createState() => _PlayerBufferingOverlayState();
}

class _PlayerBufferingOverlayState extends State<PlayerBufferingOverlay> {
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _percentageSubscription;
  bool _buffering = false;
  double? _percentage;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bindPlayer();
  }

  double? _validPercentage(double value) =>
      !kIsWeb && value.isFinite && value > 0 && value <= 100 ? value : null;

  void _bindPlayer() {
    final generation = ++_generation;
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_percentageSubscription?.cancel());
    _bufferingSubscription = null;
    _percentageSubscription = null;
    _percentage = null;
    final player = widget.player;
    _buffering = player?.state.buffering ?? widget.buffering;
    if (player == null) return;
    if (_buffering) {
      final initial = _validPercentage(player.state.bufferingPercentage);
      // 100% 可能来自上一轮缓冲，重建时等待本轮事件，避免显示过期进度。
      _percentage = initial == 100 ? null : initial;
    }
    bool current() => mounted && generation == _generation;
    _bufferingSubscription = player.stream.buffering.listen((value) {
      if (!current() || value == _buffering) return;
      setState(() {
        _buffering = value;
        _percentage = null;
      });
    });
    _percentageSubscription = player.stream.bufferingPercentage.listen((value) {
      if (!current() || !_buffering) return;
      final percentage = _validPercentage(value);
      if (_percentage == percentage) return;
      setState(() => _percentage = percentage);
    });
  }

  @override
  void didUpdateWidget(PlayerBufferingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _bindPlayer();
    } else if (widget.player == null) {
      _buffering = widget.buffering;
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_percentageSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.resolving && !_buffering) return const SizedBox.shrink();
    // 百分比是播放器当前起播缓冲目标的进度，不是整部视频已下载的比例。
    final progress = widget.resolving ? null : _percentage;
    final label = widget.resolving
        ? widget.resolvingLabel ?? '正在准备播放'
        : progress == null
        ? '正在缓冲'
        : '缓冲 ${progress.round()}%';
    final tokens = PlayraTokens.of(context);
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC11141C),
            borderRadius: BorderRadius.circular(PlayraRadius.card),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 16,
                    child: progress == null && PlayraMotion.reduceOf(context)
                        ? Icon(
                            Icons.hourglass_top_rounded,
                            size: 16,
                            color: tokens.primary,
                          )
                        : CircularProgressIndicator(
                            value: progress == null ? null : progress / 100,
                            strokeWidth: 2,
                            color: tokens.primary,
                          ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
