import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Single playback progress record.
class HistoryRecord {
  const HistoryRecord({
    required this.sourceId,
    required this.mediaId,
    required this.title,
    required this.cover,
    required this.roadCode,
    required this.roadName,
    required this.episode,
    required this.episodeTitle,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final String sourceId;
  final String mediaId;
  final String title;
  final String cover;
  final String roadCode;
  final String roadName;
  final int episode;
  final String episodeTitle;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  String get id => '${sourceId}_$mediaId';

  double get progress {
    if (durationMs <= 0) return 0.0;
    final p = positionMs / durationMs;
    return p.clamp(0.0, 1.0);
  }

  String get formattedPosition =>
      _formatDuration(Duration(milliseconds: positionMs));

  String get formattedProgress {
    final pos = formattedPosition;
    if (durationMs <= 0) return pos;
    final dur = _formatDuration(Duration(milliseconds: durationMs));
    return '$pos / $dur';
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
    'sourceId': sourceId,
    'mediaId': mediaId,
    'title': title,
    'cover': cover,
    'roadCode': roadCode,
    'roadName': roadName,
    'episode': episode,
    'episodeTitle': episodeTitle,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory HistoryRecord.fromMap(Map<dynamic, dynamic> map) {
    return HistoryRecord(
      sourceId: map['sourceId'] as String? ?? '',
      mediaId: map['mediaId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      cover: map['cover'] as String? ?? '',
      roadCode: map['roadCode'] as String? ?? '',
      roadName: map['roadName'] as String? ?? '',
      episode: (map['episode'] as num?)?.toInt() ?? 1,
      episodeTitle: map['episodeTitle'] as String? ?? '',
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Service managing playback history persistence.
abstract final class HistoryStorage {
  static const String boxName = 'playback_history';

  static Box<dynamic> get _box => GStorage.history;

  static ValueListenable<Box<dynamic>> listenable() => _box.listenable();

  static HistoryRecord? get(String sourceId, String mediaId) {
    try {
      final key = '${sourceId}_$mediaId';
      final raw = _box.get(key);
      if (raw is Map) return HistoryRecord.fromMap(raw);
    } catch (e) {
      KazumiLogger().w(
        'HistoryStorage: failed to read $sourceId:$mediaId',
        error: e,
      );
    }
    return null;
  }

  static Future<void> save(HistoryRecord record) async {
    try {
      await _box.put(record.id, record.toMap());
    } catch (e) {
      KazumiLogger().e(
        'HistoryStorage: failed to save record ${record.id}',
        error: e,
      );
    }
  }

  static List<HistoryRecord> getAll({int limit = 100}) {
    try {
      final list = <HistoryRecord>[];
      for (final key in _box.keys) {
        final raw = _box.get(key);
        if (raw is Map) {
          list.add(HistoryRecord.fromMap(raw));
        }
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (list.length > limit) return list.sublist(0, limit);
      return list;
    } catch (e) {
      KazumiLogger().w('HistoryStorage: failed to get all history', error: e);
      return const [];
    }
  }

  static Future<void> delete(String sourceId, String mediaId) async {
    final key = '${sourceId}_$mediaId';
    await _box.delete(key);
  }

  static Future<void> clearAll() async {
    await _box.clear();
  }
}
