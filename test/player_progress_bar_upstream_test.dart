import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_progress_bar.dart';

void main() {
  Widget buildBar({
    Duration total = const Duration(seconds: 100),
    bool sideLabels = false,
    double scale = 1,
    required VoidCallback onStart,
    required ValueChanged<Duration> onUpdate,
    required ValueChanged<bool> onEnd,
    required ValueChanged<Duration> onSeek,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 48,
            child: PlayerProgressBar(
              progress: const Duration(seconds: 25),
              buffered: const Duration(seconds: 50),
              total: total,
              sideLabels: sideLabels,
              onDragStart: onStart,
              onDragUpdate: onUpdate,
              onDragEnd: onEnd,
              onSeek: onSeek,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('drag previews and commits once; cancel closes without commit', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      buildBar(
        onStart: () => events.add('start'),
        onUpdate: (value) => events.add('update:${value.inSeconds}'),
        onEnd: (cancelled) => events.add('end:$cancelled'),
        onSeek: (_) => events.add('semantic-seek'),
      ),
    );
    final bar = find.byType(PlayerProgressBar);
    final rect = tester.getRect(bar);
    final first = await tester.startGesture(
      Offset(rect.left + 30, rect.center.dy),
    );
    await first.moveTo(Offset(rect.left + 220, rect.center.dy));
    await tester.pump();
    await first.up();
    await tester.pump();
    expect(events.first, 'start');
    expect(events.where((e) => e.startsWith('update:')), isNotEmpty);
    expect(events.last, 'end:false');
    expect(events.where((e) => e == 'end:false'), hasLength(1));
    events.clear();
    final second = await tester.startGesture(rect.center);
    await tester.pump();
    await second.cancel();
    await tester.pump();
    expect(events.first, 'start');
    expect(events.last, 'end:true');
    expect(events.where((e) => e.startsWith('end:')), hasLength(1));
  });

  testWidgets('unknown duration has no seek actions or pointer drag', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final events = <String>[];
    await tester.pumpWidget(
      buildBar(
        total: Duration.zero,
        onStart: () => events.add('start'),
        onUpdate: (_) => events.add('update'),
        onEnd: (_) => events.add('end'),
        onSeek: (_) => events.add('seek'),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('播放进度'));
    expect(node.value, '时长未知');
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.increase),
      isFalse,
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.decrease),
      isFalse,
    );
    await tester.tap(find.byType(PlayerProgressBar));
    expect(events, isEmpty);
    semantics.dispose();
  });

  testWidgets('accessibility adjusts by five percent at large text scale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Duration? sought;
    await tester.pumpWidget(
      buildBar(
        scale: 2,
        sideLabels: true,
        onStart: () {},
        onUpdate: (_) {},
        onEnd: (_) {},
        onSeek: (value) => sought = value,
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('播放进度'));
    expect(node.value, '25%');
    // The test view's owner, not the binding's root owner, owns this node.
    // ignore: deprecated_member_use
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.increase,
    );
    expect(sought, const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('removing an active drag reports cancellation once', (
    tester,
  ) async {
    final ends = <bool>[];
    await tester.pumpWidget(
      buildBar(
        onStart: () {},
        onUpdate: (_) {},
        onEnd: ends.add,
        onSeek: (_) {},
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PlayerProgressBar)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(ends, [true]);
    await gesture.cancel();
  });
}
