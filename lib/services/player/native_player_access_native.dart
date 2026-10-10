import 'package:media_kit/media_kit.dart';

NativePlayer nativePlayerAccess(Player player) =>
    player.platform as NativePlayer;
