import 'package:kazumi/services/platform/android_abi.dart';
import 'package:kazumi/services/platform/platform_io.dart';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

class PlatformEnvironmentService {
  PlatformEnvironmentService._();

  static const _intentChannel = MethodChannel('com.predidit.kazumi/intent');

  static Future<bool> isRunningOnX11() async {
    if (!Platform.isLinux) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('isRunningOnX11');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check X11 environment: '${e.message}'.");
      return false;
    }
  }

  /// Android x86_64（模拟器）上 Vulkan 驱动普遍不可靠，gpu-next 会在
  /// 初始化阶段拖死宿主；渲染器选择据此退回 OpenGL。
  static bool get isAndroidX64Emulator => androidRunsOnX64;

  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    try {
      return await _intentChannel.invokeMethod('getAndroidSdkVersion');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to get Android SDK version: '${e.message}'.");
      return 0;
    }
  }
}
