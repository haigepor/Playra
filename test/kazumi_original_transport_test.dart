import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/kazumi_original_transport.dart';

void main() {
  test('placement follows original viewport rules', () {
    expect(
      KazumiTimeLabelPlacement.forViewport(
        const Size(320, 640),
        desktop: false,
      ),
      KazumiTimeLabelPlacement.aboveProgress,
    );
    expect(
      KazumiTimeLabelPlacement.forViewport(
        const Size(800, 600),
        desktop: false,
      ),
      KazumiTimeLabelPlacement.besideProgress,
    );
    expect(
      KazumiTimeLabelPlacement.forViewport(const Size(800, 450), desktop: true),
      KazumiTimeLabelPlacement.afterPlaybackButtons,
    );
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact $size at scale $scale retains safe actions', (
        tester,
      ) async {
        var plays = 0;
        var fullscreens = 0;
        var seeks = 0;
        TimeLabelLocation? location;
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(bottom: 20),
              ),
              child: Scaffold(
                body: SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: KazumiOriginalTransport(
                      compact: true,
                      playPause: IconButton(
                        tooltip: '播放',
                        onPressed: () => plays++,
                        icon: const Icon(Icons.play_arrow),
                      ),
                      nextEpisode: IconButton(
                        tooltip: '下一集',
                        onPressed: () {},
                        icon: const Icon(Icons.skip_next),
                      ),
                      progressBuilder: (value) {
                        location = value;
                        return TextButton(
                          onPressed: () => seeks++,
                          child: const Text('进度'),
                        );
                      },
                      timeLabel: const Text('12:00 / 24:00'),
                      timePlacement: KazumiTimeLabelPlacement.aboveProgress,
                      controls: const Text('不存在的功能'),
                      fullscreen: IconButton(
                        tooltip: '全屏',
                        onPressed: () => fullscreens++,
                        icon: const Icon(Icons.fullscreen),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(location, TimeLabelLocation.none);
        expect(find.text('不存在的功能'), findsNothing);
        expect(find.byTooltip('下一集'), findsNothing); // Original compact layout.
        await tester.tap(find.byTooltip('播放'));
        await tester.tap(find.byTooltip('全屏'));
        await tester.tap(find.text('进度'));
        expect([plays, fullscreens, seeks], [1, 1, 1]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('wide layout uses side labels and forwards provided controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var next = 0;
    TimeLabelLocation? location;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KazumiOriginalTransport(
            compact: false,
            playPause: const SizedBox(width: 48, height: 48),
            nextEpisode: IconButton(
              tooltip: '下一集',
              onPressed: () => next++,
              icon: const Icon(Icons.skip_next),
            ),
            progressBuilder: (value) {
              location = value;
              return const SizedBox(height: 48);
            },
            timeLabel: const Text('12:00 / 24:00'),
            timePlacement: KazumiTimeLabelPlacement.besideProgress,
            controls: const Text('控制'),
            fullscreen: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );
    expect(location, TimeLabelLocation.sides);
    expect(find.text('控制'), findsOneWidget);
    await tester.tap(find.byTooltip('下一集'));
    expect(next, 1);
    expect(tester.takeException(), isNull);
  });
}
