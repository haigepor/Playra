import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Single favorite record.
class FavoriteRecord {
  const FavoriteRecord({
    required this.sourceId,
    required this.mediaId,
    required this.title,
    required this.cover,
    this.category = '',
    this.subtitle = '',
    required this.updatedAt,
  });

  final String sourceId;
  final String mediaId;
  final String title;
  final String cover;
  final String category;
  final String subtitle;
  final DateTime updatedAt;

  String get id => '${sourceId}_$mediaId';

  /// Old detail saves could contain aliases in this field; only expose a
  /// recognizable episode status on cards and management rows.
  String get statusText =>
      RegExp(r'^(?:更新至|全\s*\d|共\s*\d|连载|已完结|完结)').hasMatch(subtitle.trim())
      ? subtitle.trim()
      : '';

  Map<String, dynamic> toMap() => {
    'sourceId': sourceId,
    'mediaId': mediaId,
    'title': title,
    'cover': cover,
    'category': category,
    'subtitle': subtitle,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory FavoriteRecord.fromMap(Map<dynamic, dynamic> map) {
    return FavoriteRecord(
      sourceId: map['sourceId'] as String? ?? '',
      mediaId: map['mediaId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      cover: map['cover'] as String? ?? '',
      category: map['category'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Service managing user favorites (追番).
abstract final class FavoriteStorage {
  static const String boxName = 'favorites';

  static Box<dynamic> get _box => GStorage.favorites;

  static ValueListenable<Box<dynamic>> listenable() => _box.listenable();

  static bool isFavorite(String sourceId, String mediaId) {
    final key = '${sourceId}_$mediaId';
    return _box.containsKey(key);
  }

  static FavoriteRecord? get(String sourceId, String mediaId) {
    try {
      final key = '${sourceId}_$mediaId';
      final raw = _box.get(key);
      if (raw is Map) return FavoriteRecord.fromMap(raw);
    } catch (e) {
      KazumiLogger().w(
        'FavoriteStorage: failed to read $sourceId:$mediaId',
        error: e,
      );
    }
    return null;
  }

  static Future<bool> toggle(FavoriteRecord record) async {
    final key = record.id;
    if (_box.containsKey(key)) {
      await _box.delete(key);
      return false;
    } else {
      await _box.put(key, record.toMap());
      return true;
    }
  }

  static Future<void> remove(String sourceId, String mediaId) async {
    final key = '${sourceId}_$mediaId';
    await _box.delete(key);
  }

  static List<FavoriteRecord> getAll() {
    try {
      final list = <FavoriteRecord>[];
      for (final key in _box.keys) {
        final raw = _box.get(key);
        if (raw is Map) {
          list.add(FavoriteRecord.fromMap(raw));
        }
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (e) {
      KazumiLogger().w(
        'FavoriteStorage: failed to get all favorites',
        error: e,
      );
      return const [];
    }
  }

  static Future<void> clearAll() async {
    await _box.clear();
  }
}
