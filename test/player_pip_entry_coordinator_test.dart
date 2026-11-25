import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_item.dart';

void main() {
  testWidgets('PiP waits for native mode callback after successful request', (
    tester,
  ) async {
    var changes = 0;
    var entries = 0;
    final failures = <AndroidPipEntryFailure>[];
    final coordinator = AndroidPipEntryCoordinator(
      onChanged: () => changes++,
      onFailure: failures.add,
    );
    addTearDown(coordinator.dispose);
    await coordinator.request(
      isSupported: () async => true,
      prepare: () async {},
      enter: () async {
        entries++;
        return true;
      },
    );
    expect(coordinator.pending, isTrue);
    await coordinator.request(
      isSupported: () async => true,
      prepare: () async {},
      enter: () async {
        entries++;
        return true;
      },
    );
    expect(entries, 1);
    coordinator.confirmModeChanged();
    expect(coordinator.pending, isFalse);
    expect(changes, 2);
    await tester.pump(const Duration(seconds: 10));
    expect(failures, isEmpty);
  });

  for (final stage in [
    'unsupported',
    'check',
    'prepare',
    'enter',
    'rejected',
  ]) {
    testWidgets('PiP releases pending state on $stage failure', (tester) async {
      final failures = <AndroidPipEntryFailure>[];
      var changes = 0;
      final coordinator = AndroidPipEntryCoordinator(
        onChanged: () => changes++,
        onFailure: failures.add,
      );
      addTearDown(coordinator.dispose);
      await coordinator.request(
        isSupported: () async {
          if (stage == 'check') throw MissingPluginException('unavailable');
          return stage != 'unsupported';
        },
        prepare: () async {
          if (stage == 'prepare') throw StateError('update failure');
        },
        enter: () async {
          if (stage == 'enter') throw MissingPluginException('unavailable');
          return stage != 'rejected';
        },
      );
      expect(coordinator.pending, isFalse);
      expect(changes, 2);
      expect(failures, [
        stage == 'unsupported'
            ? AndroidPipEntryFailure.unsupported
            : AndroidPipEntryFailure.failed,
      ]);
      await tester.pump(const Duration(seconds: 10));
      expect(failures.length, 1);
    });
  }

  testWidgets('PiP timeout releases and ignores the older async request', (
    tester,
  ) async {
    final oldSupport = Completer<bool>();
    final newEntry = Completer<bool>();
    final failures = <AndroidPipEntryFailure>[];
    var enterCalls = 0;
    final coordinator = AndroidPipEntryCoordinator(
      onChanged: () {},
      onFailure: failures.add,
      timeout: const Duration(seconds: 1),
    );
    addTearDown(coordinator.dispose);
    final first = coordinator.request(
      isSupported: () => oldSupport.future,
      prepare: () async {},
      enter: () async {
        enterCalls++;
        return true;
      },
    );
    expect(coordinator.pending, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(coordinator.pending, isFalse);
    expect(failures, [AndroidPipEntryFailure.timeout]);
    final second = coordinator.request(
      isSupported: () async => true,
      prepare: () async {},
      enter: () {
        enterCalls++;
        return newEntry.future;
      },
    );
    await tester.pump();
    expect(coordinator.pending, isTrue);
    oldSupport.complete(true);
    await first;
    expect(enterCalls, 1);
    expect(coordinator.pending, isTrue);
    newEntry.complete(true);
    await second;
    expect(coordinator.pending, isTrue);
    coordinator.confirmModeChanged();
    expect(coordinator.pending, isFalse);
    expect(failures.length, 1);
  });

  testWidgets('PiP request can time out waiting for native mode callback', (
    tester,
  ) async {
    final failures = <AndroidPipEntryFailure>[];
    final coordinator = AndroidPipEntryCoordinator(
      onChanged: () {},
      onFailure: failures.add,
      timeout: const Duration(seconds: 1),
    );
    addTearDown(coordinator.dispose);
    await coordinator.request(
      isSupported: () async => true,
      prepare: () async {},
      enter: () async => true,
    );
    expect(coordinator.pending, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(coordinator.pending, isFalse);
    expect(failures, [AndroidPipEntryFailure.timeout]);
    coordinator.confirmModeChanged();
    expect(failures.length, 1);
  });

  testWidgets('disposing PiP cancels timeout and ignores late replies', (
    tester,
  ) async {
    final support = Completer<bool>();
    final failures = <AndroidPipEntryFailure>[];
    var changes = 0;
    final coordinator = AndroidPipEntryCoordinator(
      onChanged: () => changes++,
      onFailure: failures.add,
      timeout: const Duration(seconds: 1),
    );
    final request = coordinator.request(
      isSupported: () => support.future,
      prepare: () async {},
      enter: () async => true,
    );
    coordinator.dispose();
    await tester.pump(const Duration(seconds: 2));
    support.complete(true);
    await request;
    expect(coordinator.pending, isFalse);
    expect(changes, 1);
    expect(failures, isEmpty);
  });

  testWidgets('negative native mode callback releases pending request', (
    tester,
  ) async {
    final failures = <AndroidPipEntryFailure>[];
    final coordinator = AndroidPipEntryCoordinator(
      onChanged: () {},
      onFailure: failures.add,
    );
    addTearDown(coordinator.dispose);
    await coordinator.request(
      isSupported: () async => true,
      prepare: () async {},
      enter: () async => true,
    );
    coordinator.rejectModeChanged();
    expect(coordinator.pending, isFalse);
    expect(failures, [AndroidPipEntryFailure.failed]);
    await tester.pump(const Duration(seconds: 10));
    expect(failures.length, 1);
  });

  testWidgets('PiP failure while backgrounded re-evaluates pause once', (
    tester,
  ) async {
    var backgrounded = true;
    var pauses = 0;
    final prefetch = <bool>[];
    late AndroidPipEntryCoordinator pip;
    final background = BackgroundPlaybackCoordinator(
      shouldSuspend: () => backgrounded && !pip.pending,
      setPrefetchSuspended: (value) async {
        prefetch.add(value);
      },
      pause: () async {
        pauses++;
      },
    );
    pip = AndroidPipEntryCoordinator(
      onChanged: () {},
      onFailure: (_) => unawaited(background.suspend()),
      timeout: const Duration(seconds: 1),
    );
    addTearDown(pip.dispose);
    addTearDown(background.dispose);
    final support = Completer<bool>();
    final request = pip.request(
      isSupported: () => support.future,
      prepare: () async {},
      enter: () async => true,
    );
    await background
        .suspend(); // The paused event was suppressed while pending.
    expect(prefetch, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(prefetch, [true]);
    expect(pauses, 1);
    await background
        .suspend(); // Duplicate lifecycle events do not pause twice.
    expect(pauses, 1);
    backgrounded = false;
    await background.resume();
    support.complete(true);
    await request;
    expect(prefetch, [true, false]);
  });

  testWidgets('resuming invalidates an undelivered background pause', (
    tester,
  ) async {
    var backgrounded = true;
    var pauses = 0;
    final prefetch = <bool>[];
    final background = BackgroundPlaybackCoordinator(
      shouldSuspend: () => backgrounded,
      setPrefetchSuspended: (value) async {
        prefetch.add(value);
      },
      pause: () async {
        pauses++;
      },
    );
    addTearDown(background.dispose);
    final suspend = background.suspend();
    backgrounded = false;
    final resume = background.resume();
    await suspend;
    await resume;
    expect(prefetch, [true, false]);
    expect(pauses, 0);
  });

  testWidgets('late background pause completion never resuspends prefetch', (
    tester,
  ) async {
    var backgrounded = true;
    final pauseCompleter = Completer<void>();
    final prefetch = <bool>[];
    final background = BackgroundPlaybackCoordinator(
      shouldSuspend: () => backgrounded,
      setPrefetchSuspended: (value) async {
        prefetch.add(value);
      },
      pause: () => pauseCompleter.future,
    );
    addTearDown(background.dispose);
    final suspend = background.suspend();
    await tester.pump();
    backgrounded = false;
    await background.resume();
    pauseCompleter.complete();
    await suspend;
    expect(prefetch, [true, false]);
  });

  group('visible PiP video geometry', () {
    const viewport = Size(1000, 1000);
    const video = Size(1920, 1080);
    test('contain reports the centered letterbox-free video area', () {
      expect(
        visiblePipVideoRect(
          viewport: viewport,
          video: video,
          fit: BoxFit.contain,
        ),
        const Rect.fromLTRB(0, 218.75, 1000, 781.25),
      );
    });
    test('cover and fill report the clipped viewport', () {
      for (final fit in [BoxFit.cover, BoxFit.fill]) {
        expect(
          visiblePipVideoRect(viewport: viewport, video: video, fit: fit),
          const Rect.fromLTWH(0, 0, 1000, 1000),
        );
      }
    });
    test('4:3 uses centered frame even if video size is unavailable', () {
      for (final source in [video, Size.zero]) {
        expect(
          visiblePipVideoRect(
            viewport: viewport,
            video: source,
            fit: BoxFit.fill,
            frameAspectRatio: 4 / 3,
          ),
          const Rect.fromLTRB(0, 125, 1000, 875),
        );
      }
    });
    test('empty viewport has no visible rectangle', () {
      expect(
        visiblePipVideoRect(
          viewport: Size.zero,
          video: video,
          fit: BoxFit.contain,
        ),
        Rect.zero,
      );
    });
  });
}
