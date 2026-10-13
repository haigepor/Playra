import 'dart:async';
import 'dart:convert';
import 'source_profile.dart';

/// 本地覆盖与统计独立于规则，远程更新不会覆盖用户选择。
class SourcePolicy {
  SourcePolicy();
  static final shared = SourcePolicy();
  final Map<String, Map<String, dynamic>> _preferences = {};
  final Map<String, List<Map<String, dynamic>>> _samples = {};
  Future<void> Function(String json)? persist;
  String environment = 'default';
  String Function()? environmentProvider;
  Future<void> _writeTail = Future.value();

  void restore(String json) {
    final data = jsonDecode(json) as Map;
    _preferences.clear();
    _samples.clear();
    for (final e in (data['preferences'] as Map? ?? const {}).entries) {
      if (e.key is String && e.value is Map) {
        _preferences[e.key as String] = Map<String, dynamic>.from(
          e.value as Map,
        );
      }
    }
    for (final e in (data['samples'] as Map? ?? const {}).entries) {
      if (e.key is String && e.value is List) {
        _samples[e.key as String] = (e.value as List)
            .whereType<Map>()
            .take(12)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
      }
    }
  }

  bool enabled(String id) => _preferences[id]?['enabled'] != false;
  SourceProfile profile(String id, Map<String, dynamic> rule) {
    final declared = SourceProfile.fromJson(rule);
    final override = _preferences[id]?['domains'];
    return override is List
        ? SourceProfile.fromJson({
            'sourceConfig': {
              'domains': override,
              'contentGroups': declared.contentGroups,
              if (declared.adapterKind == 'http') 'resolveApi': {},
            },
          })
        : declared;
  }

  Future<void> configure(
    String id, {
    bool? enabled,
    List<String>? domains,
  }) async {
    final previous = _preferences[id];
    final updated = <String, dynamic>{
      ...?previous,
      'enabled': ?enabled,
      'domains': ?domains,
    };
    _preferences[id] = updated;
    try {
      await flush();
    } catch (_) {
      // 较早的保存失败不能回滚后来已经提交的人工设置。
      if (identical(_preferences[id], updated)) {
        if (previous == null) {
          _preferences.remove(id);
        } else {
          _preferences[id] = previous;
        }
      }
      rethrow;
    }
  }

  String _key(String id, String version) =>
      '${environmentProvider?.call() ?? environment}|$id|$version';
  void record(
    String id,
    String version, {
    required bool success,
    required int elapsedMs,
  }) {
    final list = _samples.putIfAbsent(_key(id, version), () => []);
    list.insert(0, {
      'ok': success,
      'ms': elapsedMs.clamp(0, 180000),
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    if (list.length > 12) list.removeRange(12, list.length);
    if (_samples.length > 128) _samples.remove(_samples.keys.first);
    // 统计持久化失败不影响播放结果；下次正常写入会再次保存。
    unawaited(flush().catchError((Object _) {}));
  }

  List<Map<String, dynamic>> _recent(String id, String version) {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    return (_samples[_key(id, version)] ?? [])
        .where(
          (s) => s['at'] is int && (s['at'] as int) >= cutoff && s['ms'] is num,
        )
        .toList();
  }

  double score(String id, String version) {
    final list = _recent(id, version);
    if (list.isEmpty) return 10000;
    final successes = list.where((s) => s['ok'] == true).toList();
    if (successes.isEmpty) return 60000;
    final weighted =
        successes.fold<double>(
          0,
          (sum, s) => sum + (s['ms'] as num).toDouble(),
        ) /
        successes.length;
    return weighted +
        (list.length - successes.length) / list.length * 30000 +
        1500 / successes.length;
  }

  bool coolingDown(String id, String version) {
    final recent = _recent(id, version);
    return recent.length >= 3 &&
        recent.take(3).every((s) => s['ok'] == false) &&
        DateTime.now().millisecondsSinceEpoch - (recent.first['at'] as int) <
            const Duration(minutes: 2).inMilliseconds;
  }

  String? summary(String id, String version) {
    final list = _recent(id, version).where((s) => s['ok'] == true).toList();
    if (list.isEmpty) return null;
    final mean =
        list.fold<num>(0, (sum, s) => sum + (s['ms'] as num)) / list.length;
    return '近期启动 ${(mean / 1000).toStringAsFixed(1)} 秒';
  }

  Future<void> flush() {
    final writer = persist;
    if (writer == null) return Future.value();
    final json = jsonEncode({'preferences': _preferences, 'samples': _samples});
    final result = _writeTail
        .catchError((Object _) {})
        .then((_) => writer(json));
    _writeTail = result;
    return result;
  }
}
