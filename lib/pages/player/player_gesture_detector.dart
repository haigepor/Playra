import 'package:flutter/widgets.dart';

class PlayerGestureDetector extends StatefulWidget {
  const PlayerGestureDetector({
    super.key,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    this.onAdjust,
    required this.onAdjustmentEnd,
  });

  final VoidCallback onSeekStart;
  final void Function(double delta, bool cancelPending) onSeekUpdate;
  final void Function(bool cancelled) onSeekEnd;
  final void Function(bool left, double deltaFraction)? onAdjust;
  final VoidCallback onAdjustmentEnd;

  @override
  State<PlayerGestureDetector> createState() => _PlayerGestureDetectorState();
}

class _PlayerGestureDetectorState extends State<PlayerGestureDetector> {
  bool? _cancelPending;
  bool _left = false;

  void _endSeek({bool cancelled = false}) {
    final cancelPending = _cancelPending;
    if (cancelPending == null) return;
    _cancelPending = null;
    widget.onSeekEnd(cancelled || cancelPending);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isAtEdge(Offset position) =>
            position.dx <= 0 ||
            position.dy <= 0 ||
            position.dx >= constraints.maxWidth ||
            position.dy >= constraints.maxHeight;

        return Listener(
          behavior: HitTestBehavior.translucent,
          // Flutter reports pointer cancellation as onEnd for accepted drags.
          onPointerCancel: (_) => _endSeek(cancelled: true),
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              _cancelPending = isAtEdge(details.localPosition);
              widget.onSeekStart();
            },
            onHorizontalDragUpdate: (details) {
              final wasCancelPending = _cancelPending;
              if (wasCancelPending == null) return;
              final cancelPending = isAtEdge(details.localPosition);
              final delta = cancelPending || wasCancelPending
                  ? 0.0
                  : details.delta.dx;
              _cancelPending = cancelPending;
              widget.onSeekUpdate(delta, cancelPending);
            },
            onHorizontalDragEnd: (_) => _endSeek(),
            onVerticalDragDown: widget.onAdjust == null
                ? null
                : (d) => _left = d.localPosition.dx < constraints.maxWidth / 2,
            onVerticalDragUpdate: widget.onAdjust == null
                ? null
                : (d) => widget.onAdjust!(
                    _left,
                    d.delta.dy / constraints.maxHeight,
                  ),
            onVerticalDragEnd: widget.onAdjust == null
                ? null
                : (_) => widget.onAdjustmentEnd(),
            onVerticalDragCancel: widget.onAdjust == null
                ? null
                : widget.onAdjustmentEnd,
          ),
        );
      },
    );
  }
}
