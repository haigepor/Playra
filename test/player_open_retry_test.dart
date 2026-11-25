import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';

void main() {
  test('resume seek is not progress, but subsequent movement is', () {
    final progress = PlayerStartupProgress(const Duration(seconds: 60));
    expect(progress.observe(Duration.zero), isFalse);
    expect(progress.observe(const Duration(seconds: 60)), isFalse);
    expect(progress.observe(const Duration(seconds: 60)), isFalse);
    expect(progress.observe(const Duration(milliseconds: 60500)), isTrue);
  });

  test('playback can advance when resume seek is ignored', () {
    final progress = PlayerStartupProgress(const Duration(seconds: 60));
    expect(progress.observe(Duration.zero), isFalse);
    expect(progress.observe(const Duration(milliseconds: 500)), isTrue);
  });

  test('short resume seek is not playback', () {
    final progress = PlayerStartupProgress(const Duration(seconds: 1));
    expect(progress.observe(Duration.zero), isFalse);
    expect(progress.observe(const Duration(seconds: 1)), isFalse);
    expect(progress.observe(const Duration(milliseconds: 1200)), isTrue);
  });

  test('initially paused open can retry while staying paused', () async {
    var opens = 0;
    var failures = 0;
    var playing = false;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      // This means a new user pause, not the original paused preference.
      isPaused: () => false,
      delay: () async {},
      reopen: () async {
        opens++;
        playing = false;
      },
      onFailure: () => failures++,
    );
    expect(gate.request('timeout'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(opens, 1);
    expect(playing, isFalse);
    expect(failures, 0);
  });

  test('pause or replacement during reopen suppresses async failure', () async {
    for (final replace in [false, true]) {
      final opening = Completer<void>();
      var current = true;
      var paused = false;
      var failures = 0;
      final gate = PlayerOpenRetryGate(
        isCurrent: () => current,
        withinWindow: () => true,
        hasProgress: () => false,
        isPaused: () => paused,
        delay: () async {},
        reopen: () => opening.future,
        onFailure: () => failures++,
      );
      expect(gate.request('timeout'), isTrue);
      await Future<void>.delayed(Duration.zero);
      if (replace) {
        current = false;
      } else {
        paused = true;
      }
      opening.completeError(StateError('failed to open'));
      await Future<void>.delayed(Duration.zero);
      expect(failures, 0);
    }
  });

  test(
    'terminal startup errors mark failure before reporting and only once',
    () {
      var reports = 0;
      late PlayerOpenRetryGate gate;
      gate = PlayerOpenRetryGate(
        isCurrent: () => true,
        withinWindow: () => true,
        hasProgress: () => false,
        isPaused: () => false,
        reopen: () async {},
        onFailure: () => fail('direct failure should use the mapped callback'),
      );
      gate.reportTerminalFailure(() {
        expect(gate.failureReported, isTrue);
        reports++;
      });
      gate.reportTerminalFailure(() => reports++);
      expect(reports, 1);
      expect(gate.request('connection reset'), isTrue);
    },
  );

  test('paused startup defers non-transient format errors until play', () {
    var paused = true;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => paused,
      reopen: () async => fail('fatal format errors must not retry'),
      onFailure: () => failures++,
    );
    expect(gate.request('failed to recognize file format'), isTrue);
    expect(failures, 0);
    expect(gate.failureReported, isFalse);
    paused = false;
    gate.intentChanged(paused: false);
    expect(failures, 1);
    expect(gate.failureReported, isTrue);
  });

  test('failed reopen while paused is reported on play', () async {
    final opening = Completer<void>();
    var paused = false;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => paused,
      delay: () async {},
      reopen: () => opening.future,
      onFailure: () => failures++,
    );
    expect(gate.request('timeout'), isTrue);
    await Future<void>.delayed(Duration.zero);
    paused = true;
    gate.intentChanged(paused: true);
    opening.completeError(StateError('failed to open'));
    await Future<void>.delayed(Duration.zero);
    expect(failures, 0);
    paused = false;
    gate.intentChanged(paused: false);
    expect(failures, 1);
  });

  test('pause during delay defers the error until explicit play', () async {
    final delay = Completer<void>();
    var paused = false;
    var opens = 0;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => paused,
      delay: () => delay.future,
      reopen: () async => opens++,
      onFailure: () => failures++,
    );
    expect(gate.request('timeout'), isTrue);
    paused = true;
    gate.intentChanged(paused: true);
    delay.complete();
    await Future<void>.delayed(Duration.zero);
    expect(opens, 0);
    expect(failures, 0);
    paused = false;
    gate.intentChanged(paused: false);
    expect(failures, 1);
    gate.intentChanged(paused: false);
    expect(failures, 1);
  });

  test('reopen completion reapplies latest pause then play intent', () async {
    final opened = Completer<void>();
    var paused = false;
    var revision = 0;
    var playing = false;
    final intent = PlayerRetryIntentSynchronizer(
      isCurrent: () => true,
      isPaused: () => paused,
      revision: () => revision,
      play: () async {
        playing = true;
      },
      pause: () async {
        playing = false;
      },
    );
    final reopening = () async {
      await opened.future;
      playing = false; // native open(play: false) completed
      await intent.reconcile();
    }();
    paused = true;
    revision++;
    playing = false;
    paused = false;
    revision++;
    playing = true; // user play can complete before open
    opened.complete();
    await reopening;
    expect(playing, isTrue);
  });

  test('reconciliation handles changed intent and stale player', () async {
    final firstCommand = Completer<void>();
    var paused = false;
    var current = true;
    var revision = 0;
    var plays = 0;
    var pauses = 0;
    final intent = PlayerRetryIntentSynchronizer(
      isCurrent: () => current,
      isPaused: () => paused,
      revision: () => revision,
      play: () async {
        plays++;
        await firstCommand.future;
      },
      pause: () async {
        pauses++;
      },
    );
    final syncing = intent.reconcile();
    paused = true;
    revision++;
    firstCommand.complete();
    await syncing;
    expect(plays, 1);
    expect(pauses, 1);
    current = false;
    await intent.reconcile();
    expect(pauses, 1);
  });

  test('startup transient errors coalesce and retry once', () async {
    final delay = Completer<void>();
    var opens = 0;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => false,
      delay: () => delay.future,
      reopen: () async => opens++,
      onFailure: () => failures++,
    );
    expect(gate.request('connection reset'), isTrue);
    expect(gate.request('connection reset'), isTrue);
    delay.complete();
    await Future<void>.delayed(Duration.zero);
    expect(opens, 1);
    expect(failures, 0);
  });

  test(
    'recovered playback is never reopened at the original position',
    () async {
      final delay = Completer<void>();
      var progressed = false;
      var opens = 0;
      var failures = 0;
      final gate = PlayerOpenRetryGate(
        isCurrent: () => true,
        withinWindow: () => true,
        hasProgress: () => progressed,
        isPaused: () => false,
        delay: () => delay.future,
        reopen: () async => opens++,
        onFailure: () => failures++,
      );
      expect(gate.request('timeout'), isTrue);
      progressed = true;
      delay.complete();
      await Future<void>.delayed(Duration.zero);
      expect(opens, 0);
      expect(failures, 0);
    },
  );

  test('user pause during the delay is not undone', () async {
    final delay = Completer<void>();
    var paused = false;
    var opens = 0;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => paused,
      delay: () => delay.future,
      reopen: () async => opens++,
      onFailure: () => failures++,
    );
    expect(gate.request('timeout'), isTrue);
    paused = true;
    delay.complete();
    await Future<void>.delayed(Duration.zero);
    expect(opens, 0);
    expect(failures, 0);
    expect(gate.request('timeout'), isTrue);
  });

  test('a replaced player is never reopened or notified', () async {
    final delay = Completer<void>();
    var current = true;
    var opens = 0;
    var failures = 0;
    final gate = PlayerOpenRetryGate(
      isCurrent: () => current,
      withinWindow: () => true,
      hasProgress: () => false,
      isPaused: () => false,
      delay: () => delay.future,
      reopen: () async => opens++,
      onFailure: () => failures++,
    );
    expect(gate.request('connection reset'), isTrue);
    current = false;
    delay.complete();
    await Future<void>.delayed(Duration.zero);
    expect(opens, 0);
    expect(failures, 0);
  });

  test(
    'reopen exceptions are bounded and handled without leaking raw data',
    () async {
      var opens = 0;
      var failures = 0;
      final gate = PlayerOpenRetryGate(
        isCurrent: () => true,
        withinWindow: () => true,
        hasProgress: () => false,
        isPaused: () => false,
        delay: () async {},
        reopen: () async {
          opens++;
          throw StateError('failed to open https://example.test/?token=secret');
        },
        onFailure: () => failures++,
      );
      expect(gate.request('failed to open'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(opens, 2);
      expect(failures, 1);
      expect(gate.request('failed to open'), isTrue);
      expect(failures, 1);
    },
  );

  test(
    'error during reopen is retried only within the two-attempt budget',
    () async {
      var opens = 0;
      var failures = 0;
      late PlayerOpenRetryGate gate;
      gate = PlayerOpenRetryGate(
        isCurrent: () => true,
        withinWindow: () => true,
        hasProgress: () => false,
        isPaused: () => false,
        delay: () async {},
        reopen: () async {
          opens++;
          gate.request('timeout');
        },
        onFailure: () => failures++,
      );
      expect(gate.request('timeout'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(opens, 2);
      expect(failures, 1);
    },
  );

  test('only eligible startup errors are retried', () {
    final gate = PlayerOpenRetryGate(
      isCurrent: () => true,
      withinWindow: () => false,
      hasProgress: () => false,
      isPaused: () => false,
      reopen: () async {},
      onFailure: () {},
    );
    expect(gate.request('timeout'), isFalse);
    expect(gate.request('invalid format'), isFalse);
  });
}
