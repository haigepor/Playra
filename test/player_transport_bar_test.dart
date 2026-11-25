import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_transport_bar.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('compact transport exposes next episode at text scale $scale', (
      tester,
    ) async {
      var nextCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 320,
                  child: PlayerTransportBar(
                    compact: true,
                    playPause: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.pause),
                    ),
                    nextEpisode: IconButton(
                      tooltip: '下一集',
                      onPressed: () => nextCount++,
                      icon: const Icon(Icons.skip_next),
                    ),
                    progressBuilder: (_) => const Placeholder(),
                    timeLabel: const Text('12:00 / 24:00'),
                    timeBesideProgress: false,
                    controls: const SizedBox.shrink(),
                    fullscreen: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.fullscreen),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('下一集'));
      expect(nextCount, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
