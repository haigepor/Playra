import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/services/player/playback_start_position.dart';

class _Stream extends Fake implements PlayerStream {
  final updates = StreamController<Duration>.broadcast();
  @override
  Stream<Duration> get duration => updates.stream;
}

class _Player extends Fake implements Player {
  @override
  PlayerState state = const PlayerState();
  @override
  final _Stream stream = _Stream();
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration value) async => seeks.add(value);
}

void main() {
  test(
    'HLS history waits for metadata and seeks to its stored offset',
    () async {
      final player = _Player();
      final restoring = restorePlaybackStart(
        player,
        const Duration(seconds: 31),
        isCurrent: () => true,
      );
      expect(player.seeks, isEmpty);
      player.stream.updates.add(const Duration(minutes: 24));
      await restoring;
      expect(player.seeks, [const Duration(seconds: 31)]);
      await player.stream.updates.close();
    },
  );

  test(
    'late metadata from an old selection cannot seek after switching',
    () async {
      final player = _Player();
      var current = true;
      final restoring = restorePlaybackStart(
        player,
        const Duration(seconds: 31),
        isCurrent: () => current,
      );
      current = false;
      player.stream.updates.add(const Duration(minutes: 24));
      await restoring;
      expect(player.seeks, isEmpty);
      await player.stream.updates.close();
    },
  );

  test(
    'ready metadata restores immediately but rejects out of bounds history',
    () async {
      final player = _Player()
        ..state = const PlayerState(duration: Duration(seconds: 60));
      await restorePlaybackStart(
        player,
        const Duration(seconds: 31),
        isCurrent: () => true,
      );
      await restorePlaybackStart(
        player,
        const Duration(seconds: 60),
        isCurrent: () => true,
      );
      expect(player.seeks, [const Duration(seconds: 31)]);
      await player.stream.updates.close();
    },
  );

  test(
    'metadata timeout does not leak a later seek or unhandled error',
    () async {
      final player = _Player();
      await restorePlaybackStart(
        player,
        const Duration(seconds: 31),
        isCurrent: () => true,
        budget: const Duration(milliseconds: 5),
      );
      player.stream.updates.add(const Duration(minutes: 24));
      expect(player.seeks, isEmpty);
      await player.stream.updates.close();
    },
  );
}
