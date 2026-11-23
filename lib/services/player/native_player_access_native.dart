import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// The pinned media-kit revision exposes no public surface-queue teardown API.
// Keep the Android-specific compatibility access isolated in this adapter.
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';

NativePlayer nativePlayerAccess(Player player) =>
    player.platform as NativePlayer;

/// The pinned Android controller seeks after each surface change. Detach new
/// events and drain its queue while the native player is still usable.
Future<void> prepareVideoOutputDisposal(VideoController? controller) async {
  if (controller == null) return;
  final platform = await controller.platform.future;
  if (platform is! AndroidVideoController) return;
  platform.wid.removeListener(platform.widListener);
  await platform.videoParamsSubscription?.cancel();
  await platform.lock.synchronized(() async {});
}
