import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
import 'package:synchronized/synchronized.dart';
import 'package:kazumi/services/player/native_player_access_native.dart';

class PendingVideoOutput extends Fake implements AndroidVideoController {
  @override
  final wid = ValueNotifier<int?>(null);
  @override
  final lock = Lock();
  @override
  StreamSubscription<VideoParams>? get videoParamsSubscription => null;
  final entered = Completer<void>();
  final finishSurfaceUpdate = Completer<void>();
  final events = <String>[];
  bool playerDisposed = false;

  @override
  Future<void> widListener() => lock.synchronized(() async {
    if (!entered.isCompleted) entered.complete();
    await finishSurfaceUpdate.future;
    if (playerDisposed) throw StateError('seek after disposal');
    events.add('seek');
  });
}

class PendingVideoController extends Fake implements VideoController {
  PendingVideoController(PlatformVideoController output) {
    platform.complete(output);
  }
  @override
  final platform = Completer<PlatformVideoController>();
}

void main() {
  test(
    'surface seek finishes before disposal and later surfaces cannot seek',
    () async {
      final output = PendingVideoOutput();
      addTearDown(output.wid.dispose);
      output.wid.addListener(output.widListener);
      output.wid.value = 1;
      await output.entered.future;
      var prepared = false;
      final prepare = prepareVideoOutputDisposal(
        PendingVideoController(output),
      ).then((_) => prepared = true);
      await Future<void>.delayed(Duration.zero);
      expect(prepared, isFalse);
      output.wid.value = 2;
      output.finishSurfaceUpdate.complete();
      await prepare;
      output.playerDisposed = true;
      output.events.add('dispose');
      output.wid.value = 3;
      await Future<void>.delayed(Duration.zero);
      expect(output.events, ['seek', 'dispose']);
    },
  );
}
