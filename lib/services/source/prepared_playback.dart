/// 页面内的短期解析结果。持有地址不代表媒体已打开或已通过首帧验收。
class PreparedPlayback {
  PreparedPlayback({
    required this.providerId,
    required this.contentId,
    required this.lineCode,
    required this.episodeIdentity,
    required this.resolvedAt,
    required Map<dynamic, dynamic> media,
    this.qualityCode,
    this.ttl = const Duration(seconds: 30),
  }) : media = Map<String, dynamic>.unmodifiable({
         for (final entry in media.entries)
           if (entry.key is String) entry.key as String: entry.value,
         if (media['headers'] is Map)
           'headers': Map<String, String>.unmodifiable({
             for (final entry in (media['headers'] as Map).entries)
               if (entry.key is String && entry.value is String)
                 entry.key as String: entry.value as String,
           }),
       });

  final String providerId, contentId, lineCode, episodeIdentity;
  final String? qualityCode;
  final DateTime resolvedAt;
  final Duration ttl;
  final Map<String, dynamic> media;

  DateTime? get expiresAt {
    final value = media['expiresAt'];
    if (value is String) return DateTime.tryParse(value);
    if (value is num && value.isFinite && value > 0) {
      final milliseconds = value < 100000000000 ? value * 1000 : value;
      if (milliseconds <= 8640000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt());
      }
    }
    return null;
  }

  bool isFresh(DateTime now) {
    final age = now.difference(resolvedAt);
    final expiry = expiresAt;
    return !age.isNegative &&
        age < ttl &&
        (expiry == null || expiry.isAfter(now.add(const Duration(seconds: 3))));
  }

  bool matches({
    required String providerId,
    required String contentId,
    required String lineCode,
    required String episodeIdentity,
    String? qualityCode,
  }) =>
      this.providerId == providerId &&
      this.contentId == contentId &&
      this.lineCode == lineCode &&
      this.episodeIdentity == episodeIdentity &&
      this.qualityCode == qualityCode;
}
