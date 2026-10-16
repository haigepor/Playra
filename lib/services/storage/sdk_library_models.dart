import 'dart:convert';
import 'package:kazumi/services/source/sdk_playback_models.dart';

/// 仅保存稳定身份和观看状态；直链、请求头、凭证不进入本地个人库。
class SdkWatchProgress {
  const SdkWatchProgress({
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.automatic = true,
    this.qualityCode,
  });
  final SdkEpisode episode;
  final Duration position, duration;
  final DateTime updatedAt;
  final bool automatic;
  final String? qualityCode;
  bool get completed =>
      duration > const Duration(seconds: 30) &&
      position >= duration - const Duration(seconds: 15);
  String get key => jsonEncode([episode.code, episode.identityKey]);
  String get positionLabel =>
      '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}';
  Map<String, dynamic> toJson() => {
    'number': episode.number,
    'name': episode.name,
    'code': episode.code,
    'reference': episode.reference,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'automatic': automatic,
    'qualityCode': qualityCode,
  };
  factory SdkWatchProgress.fromJson(Map data) => SdkWatchProgress(
    episode: SdkEpisode(
      number: data['number'] as int?,
      name: data['name'] as String,
      code: data['code'] as String,
      reference: data['reference'] as String?,
    ),
    position: Duration(
      // Web位运算会截成32位，不能用1<<50作为时间上限，否则读回进度会归零。
      milliseconds: (data['positionMs'] as int).clamp(0, 31536000000),
    ),
    duration: Duration(
      milliseconds: (data['durationMs'] as int).clamp(0, 31536000000),
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    automatic: data['automatic'] != false,
    qualityCode: data['qualityCode'] as String?,
  );
}

class SdkLibraryRecord {
  const SdkLibraryRecord({
    required this.providerId,
    required this.contentId,
    required this.title,
    this.cover = '',
    this.subtitle = '',
    this.isAnime = false,
    this.collectionType = 0,
    this.collectedAt,
    this.lastWatch,
    this.progresses = const {},
  });
  final String providerId, contentId, title, cover, subtitle;
  final bool isAnime;
  final int collectionType;
  final DateTime? collectedAt;
  final SdkWatchProgress? lastWatch;
  final Map<String, SdkWatchProgress> progresses;
  String get key => jsonEncode([providerId, contentId]);
  String get sourceName => switch (providerId) {
    'lumina' => '动漫 · Lumina',
    'miomedia' => isAnime ? '动漫备用 · MioMedia' : '影视 · MioMedia',
    _ => providerId,
  };
  String get progressLabel => lastWatch == null
      ? '尚无观看记录'
      : '${lastWatch!.episode.label} · ${lastWatch!.positionLabel}';
  SdkWatchProgress? progressFor(SdkEpisode episode) =>
      progresses[jsonEncode([episode.code, episode.identityKey])];
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'providerId': providerId,
    'contentId': contentId,
    'title': title,
    'cover': cover,
    'subtitle': subtitle,
    'isAnime': isAnime,
    'collectionType': collectionType,
    'collectedAt': collectedAt?.millisecondsSinceEpoch,
    'lastWatch': lastWatch?.toJson(),
    'progresses': progresses.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory SdkLibraryRecord.fromJson(Map data) {
    if (data['schemaVersion'] != 1 ||
        (data['providerId'] as String).isEmpty ||
        (data['contentId'] as String).isEmpty)
      throw const FormatException('Invalid SDK record');
    if ((data['collectionType'] as int? ?? 0) > 0 &&
        data['collectedAt'] is! int) {
      throw const FormatException('Invalid SDK collection time');
    }
    return SdkLibraryRecord(
      providerId: data['providerId'] as String,
      contentId: data['contentId'] as String,
      title: data['title'] as String,
      cover: data['cover'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      isAnime: data['isAnime'] == true,
      collectionType: (data['collectionType'] as int? ?? 0).clamp(0, 5),
      collectedAt: data['collectedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(data['collectedAt'] as int),
      lastWatch: data['lastWatch'] is Map
          ? SdkWatchProgress.fromJson(data['lastWatch'] as Map)
          : null,
      progresses: {
        for (final entry in (data['progresses'] as Map? ?? {}).entries)
          entry.key as String: SdkWatchProgress.fromJson(entry.value as Map),
      },
    );
  }
}
