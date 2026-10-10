import 'package:kazumi/services/storage/storage.dart';
import 'package:flutter/foundation.dart';

enum BangumiAcceleration {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current => switch (GStorage.getSetting(
    SettingsKeys.bangumiAcceleration,
  )) {
    'direct' => direct,
    'ech' => kIsWeb ? direct : ech,
    'mirror' => mirror,
    _ => GStorage.getSetting(SettingsKeys.enableBangumiProxy) ? mirror : direct,
  };

  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };
}
