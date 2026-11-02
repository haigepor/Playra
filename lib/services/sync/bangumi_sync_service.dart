import 'package:flutter/foundation.dart';
import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'package:kazumi/services/storage/storage.dart';

/// 旧同步设置保持可读；已移除凭据验证、远端读写和自动同步。
class BangumiSyncService extends ChangeNotifier {
  BangumiSyncService._();
  static final _instance = BangumiSyncService._();
  factory BangumiSyncService() => _instance;
  String get username => '';
  bool get initialized => false;
  bool get isConnecting => false;
  String? get lastError => null;
  void resetForTesting() {}
  Never _removed() =>
      throw const SourceException('SOURCE_REMOVED', 'Bangumi 数据源已移除');
  Future<void> ping() async => _removed();
  Future<void> saveToken(String value) async => _removed();
  Future<void> setEnabled(bool enabled) async {
    if (enabled) _removed();
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
    notifyListeners();
  }

  Future<bool> syncCollectibleWhenIdle(int bangumiId, int localType) async =>
      false;
  Future<void> syncCollectibles({
    void Function(String message, int current, int total)? onProgress,
  }) async => _removed();
  static String describeError(Object error) => 'Bangumi 数据源已移除，个人记录继续保留在本地';
}
