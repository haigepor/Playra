import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';
import 'package:kazumi/pages/settings/danmaku/danmaku_shield_settings.dart';

final danmakuModule = createModule(
  path: '/danmaku',
  register: (c) {
    c
      ..route(
        '/',
        child: (_, _) => const SourceUnavailablePage(feature: '在线弹幕'),
      )
      ..route('/shield', child: (_, _) => const DanmakuShieldSettings());
  },
);
