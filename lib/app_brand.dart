import 'package:flutter/foundation.dart';

/// 显示品牌与安装标识分离，升级时保留现有设备身份和数据。
abstract final class AppBrand {
  static const name = 'Playra';
  static const repositoryUrl = 'https://github.com/haigepor/Playra';
  static const releasesUrl = '$repositoryUrl/releases';
  static const latestReleaseApi =
      'https://api.github.com/repos/haigepor/Playra/releases/latest';
  static const upstreamUrl = 'https://github.com/Predidit/Kazumi';
  static const tagPrefix = 'playra/v';

  static String? releaseVersion(String tag) {
    if (!tag.startsWith(tagPrefix)) return null;
    final version = tag.substring(tagPrefix.length);
    return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ? version : null;
  }
}

abstract final class AppBuildPolicy {
  // 正式版默认关闭；诊断包可显式开启，菜单和路由共用此开关。
  static const developerTools =
      !kReleaseMode ||
      bool.fromEnvironment('PLAYRA_DIAGNOSTICS', defaultValue: false);
}
