import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';

void main() {
  PlayerController controller() =>
      PlayerController(ShaderAssetService(), AudioController());

  test(
    'temporary pause resumes once only if no newer user intent exists',
    () async {
      final player = controller();
      final lease = player.pauseTemporarily();
      await lease.completed;
      expect(player.playback.startupSuspended, isTrue);
      await player.resumeTemporaryPause(lease);
      expect(player.playback.startupSuspended, isFalse);
      await player.pause();
      await player.resumeTemporaryPause(lease);
      expect(player.playback.startupSuspended, isTrue);
    },
  );

  test(
    'user pause while an overlay is open invalidates its resume lease',
    () async {
      final player = controller();
      final lease = player.pauseTemporarily();
      final userPause = player.pause();
      await Future.wait([lease.completed, userPause]);
      await player.resumeTemporaryPause(lease);
      expect(player.playback.startupSuspended, isTrue);
    },
  );

  test('temporary pause lease cannot be used by another player', () async {
    final first = controller();
    final second = controller();
    final lease = first.pauseTemporarily();
    await lease.completed;
    await second.pause();
    await second.resumeTemporaryPause(lease);
    expect(second.playback.startupSuspended, isTrue);
  });

  test('new play intent runs after an in-flight pause and wins', () async {
    final gate = PlayerPlaybackIntentQueue();
    final paused = Completer<void>();
    final events = <String>[];
    final first = gate.submit(
      isCurrent: () => true,
      command: () async {
        events.add('pause-start');
        await paused.future;
        events.add('pause-end');
      },
      onApplied: () => events.add('pause-state'),
    );
    await Future<void>.delayed(Duration.zero);
    final second = gate.submit(
      isCurrent: () => true,
      command: () async => events.add('play-native'),
      onApplied: () => events.add('play-state'),
    );
    paused.complete();
    await Future.wait([first, second]);
    expect(events, ['pause-start', 'pause-end', 'play-native', 'play-state']);
  });

  test('queued stale commands are skipped', () async {
    final gate = PlayerPlaybackIntentQueue();
    final current = Completer<void>();
    final events = <String>[];
    final first = gate.submit(
      isCurrent: () => true,
      command: () => current.future,
      onApplied: () => events.add('first-state'),
    );
    await Future<void>.delayed(Duration.zero);
    final stale = gate.submit(
      isCurrent: () => true,
      command: () async => events.add('stale-native'),
      onApplied: () => events.add('stale-state'),
    );
    final last = gate.submit(
      isCurrent: () => true,
      command: () async => events.add('last-native'),
      onApplied: () => events.add('last-state'),
    );
    current.complete();
    await Future.wait([first, stale, last]);
    expect(events, ['last-native', 'last-state']);
  });

  test('replacement suppresses obsolete completion', () async {
    final gate = PlayerPlaybackIntentQueue();
    final pending = Completer<void>();
    var current = true;
    var applied = false;
    final task = gate.submit(
      isCurrent: () => current,
      command: () => pending.future,
      onApplied: () => applied = true,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete();
    await task;
    expect(applied, isFalse);
  });

  test('failed command does not strand a later intent', () async {
    final gate = PlayerPlaybackIntentQueue();
    var applied = false;
    await gate.submit(
      isCurrent: () => true,
      command: () async => throw StateError('native failure'),
      onApplied: () => fail('failed command must not update state'),
    );
    await gate.submit(
      isCurrent: () => true,
      command: () async {},
      onApplied: () => applied = true,
    );
    expect(applied, isTrue);
  });

  test(
    'shutdown invalidation prevents an in-flight stale state write',
    () async {
      final gate = PlayerPlaybackIntentQueue();
      final pending = Completer<void>();
      var applied = false;
      final task = gate.submit(
        isCurrent: () => true,
        command: () => pending.future,
        onApplied: () => applied = true,
      );
      await Future<void>.delayed(Duration.zero);
      gate.invalidate();
      pending.complete();
      await task;
      expect(applied, isFalse);
    },
  );
}
