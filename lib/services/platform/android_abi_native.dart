import 'dart:ffi' show Abi;

import 'package:kazumi/services/platform/platform_io.dart';

/// Android x86_64 进程基本只出现在模拟器（雷电、蓝叠、Google x86 镜像）上。
/// 雷电的 Vulkan HAL 在 mpv gpu-next 初始化时会直接把虚拟机打崩，因此渲染器
/// 选择逻辑需要按 ABI 退回 OpenGL。
bool get androidRunsOnX64 {
  if (!Platform.isAndroid) {
    return false;
  }
  return Abi.current() == Abi.androidX64;
}
