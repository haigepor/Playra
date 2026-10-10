import 'package:media_kit/media_kit.dart';

/// 浏览器播放器由 HTML video 管理缓存与硬解，不接受 MPV 属性和 GLSL 命令。
class BrowserPlayerProperties {
  Future<void> get waitForPlayerInitialization async {}
  Future<void> get waitForVideoControllerInitializationIfAttached async {}
  Future<void> setProperty(String name, String value) async {}
  Future<void> command(List<String> command) async {}
}

BrowserPlayerProperties nativePlayerAccess(Player player) =>
    BrowserPlayerProperties();
