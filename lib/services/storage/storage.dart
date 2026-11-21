import 'dart:async';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/favorite_storage.dart';
import 'package:kazumi/services/storage/history_storage.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

export 'favorite_storage.dart';
export 'history_storage.dart';
export 'settings_keys.dart';

/// 统一本地持久化入口。
///
/// 管理设置 (setting)、播放历史 (playback_history) 与收藏 (favorites) Box。
class GStorage {
  static late Box<dynamic> _setting;
  static late Box<dynamic> _history;
  static late Box<dynamic> _favorites;

  static Future<void> init() async {
    _setting = await Hive.openBox<dynamic>('setting');
    _history = await Hive.openBox<dynamic>(HistoryStorage.boxName);
    _favorites = await Hive.openBox<dynamic>(FavoriteStorage.boxName);
    KazumiLogger().i('Storage: settings, history and favorites boxes opened');
  }

  static Box<dynamic> get settings => _setting;
  static Box<dynamic> get history => _history;
  static Box<dynamic> get favorites => _favorites;

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
    return _setting
        .watch()
        .where((event) => names.contains(event.key))
        .map((_) {});
  }

  static Future<void> close() async {
    await Future.wait<void>([
      _setting.close(),
      _history.close(),
      _favorites.close(),
    ]);
  }
}
