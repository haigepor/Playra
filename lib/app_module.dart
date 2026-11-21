import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/playback_demo_page.dart';
import 'package:kazumi/shell/shell_page.dart';

/// 空壳路由：只保留主界面与播放器演示。
///
/// 新页面按业务模块注册到此处；数据源不在这里登记。
final appModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const ShellPage(),
        transition: TransitionType.none,
      )
      ..route(
        '/player',
        child: (context, state) => const PlaybackDemoPage(),
        transition: TransitionType.material,
      );
  },
);

void navigateToPlayer(BuildContext context) {
  context.pushNamed('/player');
}

final appNavigatorKey = rootNavigatorKey;
