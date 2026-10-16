import 'dart:ffi';
import 'dart:io';

bool get luminaSupported {
  // 当前未交付 iOS 本地引擎；即使影视配置了远端地址，也不展示未验收的 Lumina。
  if (Platform.isIOS) return false;
  if (Platform.isAndroid) {
    return const [Abi.androidArm64, Abi.androidX64].contains(Abi.current());
  }
  // 桌面 APP 使用管理员配置的服务。
  return const String.fromEnvironment('PLAYRA_SOURCE_RUNTIME_URL').isNotEmpty;
}
