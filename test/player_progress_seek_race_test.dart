import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_item.dart';

class Harness {
  Object player = Object();
  bool playing = true;
  int revision = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int pendingSeeks = 0;
  int maxPendingSeeks = 0;
  final seekTargets = <Duration>[];
  final seekCompleters = <Completer<void>>[];
  Duration position = Duration.zero;
  Future<void>? pendingPause;
  late final coordinator = ProgressSeekCoordinator<int>(
    pause: () {
      pauseCount++;
      playing = false;
      return ++revision;
    },
    pauseCompleted: (_) => pendingPause ?? Future<void>.value(),
    resume: (lease) async {
      if (lease == revision) {
        resumeCount++;
        playing = true;
        revision++;
      }
    },
    seek: (target) async {
      seekTargets.add(target);
      pendingSeeks++;
      if (pendingSeeks > maxPendingSeeks) maxPendingSeeks = pendingSeeks;
      final done = Completer<void>();
      seekCompleters.add(done);
      await done.future;
      pendingSeeks--;
    },
    setPosition: (value) => position = value,
    isCurrentPlayer: (value) => identical(value, player),
  );

  void start() => coordinator.begin(
    player,
    position,
    playing: playing,
    wantsPlayback: playing,
  );
  void userPause() {
    revision++;
    playing = false;
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('consecutive drags share pause and serialize in-flight seeks', () async {
    final h = Harness();
    h.start();
    h.coordinator.update(const Duration(seconds: 10));
    final first = h.coordinator.end(cancelled: false);
    await tick();
    expect(h.seekTargets, [const Duration(seconds: 10)]);
    h.start();
    h.coordinator.update(const Duration(seconds: 20));
    final second = h.coordinator.end(cancelled: false);
    await tick();
    expect(h.pauseCount, 1);
    expect(h.seekTargets, hasLength(1));
    h.seekCompleters.first.complete();
    await first;
    await tick();
    expect(h.seekTargets, [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ]);
    expect(h.resumeCount, 0);
    h.seekCompleters.last.complete();
    await second;
    expect(h.maxPendingSeeks, 1);
    expect(h.resumeCount, 1);
    expect(h.playing, isTrue);
  });

  test('second drag during pending pause preserves playing intent', () async {
    final h = Harness();
    final pause = Completer<void>();
    h.pendingPause = pause.future;
    h.start();
    h.coordinator.update(const Duration(seconds: 10));
    final first = h.coordinator.end(cancelled: false);
    await tick();
    h.start();
    h.coordinator.update(const Duration(seconds: 20));
    final second = h.coordinator.end(cancelled: false);
    pause.complete();
    await first;
    await tick();
    expect(h.pauseCount, 1);
    expect(h.seekTargets, [const Duration(seconds: 20)]);
    h.seekCompleters.single.complete();
    await second;
    expect(h.playing, isTrue);
    expect(h.resumeCount, 1);
  });

  test('screenshot holds drag pause until sheet closes', () async {
    final h = Harness();
    h.start();
    h.coordinator.update(const Duration(seconds: 10));
    final overlay = h.coordinator.acquireOverlay(
      h.player,
      playing: h.playing,
      wantsPlayback: h.playing,
    )!;
    final ended = h.coordinator.end(cancelled: false);
    await tick();
    h.seekCompleters.single.complete();
    await ended;
    expect(h.playing, isFalse);
    expect(h.resumeCount, 0);
    await h.coordinator.releaseOverlay(overlay, canResume: () => true);
    expect(h.playing, isTrue);
    expect(h.resumeCount, 1);
    expect(h.pauseCount, 1);
  });

  test('closing screenshot during seek waits for seek before resume', () async {
    final h = Harness();
    h.start();
    h.coordinator.update(const Duration(seconds: 10));
    final overlay = h.coordinator.acquireOverlay(
      h.player,
      playing: h.playing,
      wantsPlayback: h.playing,
    )!;
    final ended = h.coordinator.end(cancelled: false);
    await tick();
    final closed = h.coordinator.releaseOverlay(overlay, canResume: () => true);
    await tick();
    expect(h.resumeCount, 0);
    h.seekCompleters.single.complete();
    await Future.wait([ended, closed]);
    expect(h.resumeCount, 1);
  });

  test('deferred resume rechecks sheet eligibility after seek', () async {
    final h = Harness();
    var allowed = true;
    h.start();
    final overlay = h.coordinator.acquireOverlay(
      h.player,
      playing: h.playing,
      wantsPlayback: h.playing,
    )!;
    h.coordinator.update(const Duration(seconds: 10));
    final ended = h.coordinator.end(cancelled: false);
    await tick();
    final closed = h.coordinator.releaseOverlay(
      overlay,
      canResume: () => allowed,
    );
    allowed = false;
    h.seekCompleters.single.complete();
    await Future.wait([ended, closed]);
    expect(h.resumeCount, 0);
  });

  test('sheet closes before drag ends without early resume', () async {
    final h = Harness();
    h.start();
    final overlay = h.coordinator.acquireOverlay(
      h.player,
      playing: h.playing,
      wantsPlayback: h.playing,
    )!;
    await h.coordinator.releaseOverlay(overlay, canResume: () => true);
    expect(h.resumeCount, 0);
    h.coordinator.update(const Duration(seconds: 10));
    final ended = h.coordinator.end(cancelled: false);
    await tick();
    h.seekCompleters.single.complete();
    await ended;
    expect(h.resumeCount, 1);
  });

  for (final change in ['pause', 'replace', 'disallowed']) {
    test('screenshot closure respects $change', () async {
      final h = Harness();
      h.start();
      final overlay = h.coordinator.acquireOverlay(
        h.player,
        playing: h.playing,
        wantsPlayback: h.playing,
      )!;
      final ended = h.coordinator.end(cancelled: true);
      await ended;
      if (change == 'pause') h.userPause();
      if (change == 'replace') {
        h.player = Object();
        h.revision++;
      }
      await h.coordinator.releaseOverlay(
        overlay,
        canResume: () => change != 'disallowed',
      );
      expect(h.resumeCount, 0);
    });
  }

  test(
    'user pause during consecutive drags defeats shared resume lease',
    () async {
      final h = Harness();
      h.start();
      h.coordinator.update(const Duration(seconds: 10));
      final first = h.coordinator.end(cancelled: false);
      await tick();
      h.start();
      h.userPause();
      h.coordinator.update(const Duration(seconds: 20));
      final second = h.coordinator.end(cancelled: false);
      h.seekCompleters.first.complete();
      await first;
      await tick();
      h.seekCompleters.last.complete();
      await second;
      expect(h.resumeCount, 0);
      expect(h.playing, isFalse);
    },
  );

  test(
    'replacement suppresses stale completion and does not overlap seeks',
    () async {
      final h = Harness();
      h.start();
      h.coordinator.update(const Duration(seconds: 10));
      final first = h.coordinator.end(cancelled: false);
      await tick();
      h.player = Object();
      h.revision++; // Replacing the player invalidates the old lease.
      h.playing = true;
      h.start();
      h.coordinator.update(const Duration(seconds: 30));
      final second = h.coordinator.end(cancelled: false);
      await tick();
      expect(h.seekTargets, hasLength(1));
      h.seekCompleters.first.complete();
      await first;
      await tick();
      expect(h.seekTargets.last, const Duration(seconds: 30));
      h.seekCompleters.last.complete();
      await second;
      expect(h.maxPendingSeeks, 1);
      expect(h.pauseCount, 2);
      expect(h.resumeCount, 1);
    },
  );
}
