import 'dart:async';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

export 'settings_keys.dart';

/// 空壳项目的最小持久化入口。
///
/// 只保留设置 Box。收藏、历史、下载、搜索历史等业务 Box 随旧 schema 移除；
/// 新业务需要持久化时在这里显式新增 Box，不要复用旧模型。
class GStorage {
  static late Box<dynamic> _setting;

  static Future<void> init() async {
    _setting = await Hive.openBox<dynamic>('setting');
    KazumiLogger().i('Storage: settings box opened');
  }

  static Box<dynamic> get settings => _setting;

  static T getSetting<T>(
    SettingKey<T> key, {
    SettingContext context = const SettingContext(),
  }) {
    final raw = _setting.get(key.name);
    if (raw is T) return raw;
    return key.resolveDefault(context);
  }

  static Future<void> putSetting<T>(SettingKey<T> key, T value) {
    return _setting.put(key.name, value);
  }

  static List<String> getStringListSettingByName(
    String key, {
    List<String> defaultValue = const [],
  }) {
    final stored = _setting.get(key);
    if (stored is List) return stored.whereType<String>().toList();
    return defaultValue;
  }

  static Future<void> putStringListSettingByName(
    String key,
    List<String> value,
  ) {
    return _setting.put(key, value);
  }

  static Stream<void> watchSettings(List<SettingKey<dynamic>> keys) {
    final names = keys.map((key) => key.name).toSet();
    return _setting.watch().where((event) => names.contains(event.key)).map(
      (_) {},
    );
  }

  static Future<void> close() async {
    await _setting.close();
  }
}
