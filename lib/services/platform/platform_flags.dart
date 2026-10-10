import 'dart:io' as native;
import 'package:flutter/foundation.dart';

/// 浏览器宿主系统不等于原生运行时，防止误调用桌面/手机插件。
class Platform {
  static bool get isWindows => !kIsWeb && native.Platform.isWindows;
  static bool get isLinux => !kIsWeb && native.Platform.isLinux;
  static bool get isMacOS => !kIsWeb && native.Platform.isMacOS;
  static bool get isAndroid => !kIsWeb && native.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && native.Platform.isIOS;
  static String get pathSeparator =>
      kIsWeb ? '/' : native.Platform.pathSeparator;
  static Map<String, String> get environment =>
      kIsWeb ? const {} : native.Platform.environment;
}
