import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'storage.dart';

import 'sdk_library_models.dart';
export 'sdk_library_models.dart';

/// 新身份使用独立Box，不修改Bangumi历史/收藏及其同步协议。
class SdkLibraryStore extends ChangeNotifier {
  SdkLibraryStore({
    required Box<String> box,
    required bool Function() privateMode,
  }) : _box = box,
       _privateMode = privateMode;
  SdkLibraryStore._shared()
    : _box = null,
      _privateMode = (() => GStorage.getSetting(SettingsKeys.privateMode));
  static final shared = SdkLibraryStore._shared();
  final Box<String>? _box;
  final bool Function() _privateMode;
  Box<String>? get _storage => _box ?? GStorage.sdkLibrary;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  List<SdkLibraryRecord> get records {
    final result = <SdkLibraryRecord>[];
    for (final raw in _storage?.values ?? <String>[]) {
      try {
        result.add(SdkLibraryRecord.fromJson(jsonDecode(raw) as Map));
      } catch (_) {
        /* 单条损坏不掩盖其他记录；不自动清库。 */
      }
    }
    return result;
  }

  List<SdkLibraryRecord> get histories =>
      records.where((r) => r.lastWatch != null).toList()..sort(
        (a, b) => b.lastWatch!.updatedAt.compareTo(a.lastWatch!.updatedAt),
      );
  List<SdkLibraryRecord> get collections =>
      records.where((r) => r.collectionType > 0).toList()
        ..sort((a, b) => b.collectedAt!.compareTo(a.collectedAt!));
  SdkLibraryRecord? get(String provider, String content) {
    final raw = _storage?.get(jsonEncode([provider, content]));
    if (raw == null) return null;
    try {
      return SdkLibraryRecord.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(Future<void> Function(Box<String>) operation) {
    final next = _tail.then((_) async {
      final box = _storage;
      if (box == null || !box.isOpen)
        throw StateError('SDK_STORAGE_UNAVAILABLE');
      await operation(box);
      await box.flush();
      if (!_disposed) notifyListeners();
    });
    // 写入失败反馈给调用者，但不能阻塞之后的重试。
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> collect({
    required String providerId,
    required SdkVideo video,
    required int type,
  }) => _write((box) async {
    if (type < 0 || type > 5) throw ArgumentError.value(type);
    final old = get(providerId, video.id);
    final record = SdkLibraryRecord(
      providerId: providerId,
      contentId: video.id,
      title: video.title,
      cover: video.cover,
      subtitle: video.subtitle,
      isAnime: video.isAnime,
      collectionType: type,
      collectedAt: type == 0 ? null : DateTime.now(),
      lastWatch: old?.lastWatch,
      progresses: old?.progresses ?? {},
    );
    if (type == 0 && record.lastWatch == null) {
      await box.delete(record.key);
    } else {
      await box.put(record.key, jsonEncode(record.toJson()));
    }
  });
  Future<void> changeCollection(SdkLibraryRecord record, int type) => collect(
    providerId: record.providerId,
    video: _StoredVideo(record),
    type: type,
  );
  Future<void> record({
    required String providerId,
    required SdkVideo video,
    required SdkEpisode episode,
    required Duration position,
    required Duration duration,
    required bool automatic,
    String? qualityCode,
  }) => _write((box) async {
    if (_privateMode() || position.isNegative || duration <= Duration.zero)
      return;
    final old = get(providerId, video.id);
    final watch = SdkWatchProgress(
      episode: episode,
      position: position > duration ? duration : position,
      duration: duration,
      updatedAt: DateTime.now(),
      automatic: automatic,
      qualityCode: qualityCode,
    );
    final record = SdkLibraryRecord(
      providerId: providerId,
      contentId: video.id,
      title: video.title,
      cover: video.cover,
      subtitle: video.subtitle,
      isAnime: video.isAnime,
      collectionType: old?.collectionType ?? 0,
      collectedAt: old?.collectedAt,
      lastWatch: watch,
      progresses: {...?old?.progresses, watch.key: watch},
    );
    await box.put(record.key, jsonEncode(record.toJson()));
  });
  Future<void> deleteHistory(String provider, String content) =>
      _write((box) async {
        final old = get(provider, content);
        if (old == null) return;
        if (old.collectionType == 0) {
          await box.delete(old.key);
          return;
        }
        final data = old.toJson()
          ..['lastWatch'] = null
          ..['progresses'] = <String, dynamic>{};
        await box.put(old.key, jsonEncode(data));
      });
  Future<void> clearHistory() => _write((box) async {
    for (final old in histories) {
      if (old.collectionType == 0) {
        await box.delete(old.key);
      } else {
        final data = old.toJson()
          ..['lastWatch'] = null
          ..['progresses'] = <String, dynamic>{};
        await box.put(old.key, jsonEncode(data));
      }
    }
  });
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _StoredVideo extends SdkVideoData {
  _StoredVideo(this.record)
    : super(id: record.contentId, title: record.title, cover: record.cover);
  final SdkLibraryRecord record;
  @override
  bool get isAnime => record.isAnime;
  @override
  String get subtitle => record.subtitle;
}
