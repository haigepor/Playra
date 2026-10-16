import 'package:dio/dio.dart';
import '../sdk_playback_models.dart';
import '../sdk_playback_provider.dart';
import '../source_models.dart' show SourceException;
import 'lumina_service.dart';

class LuminaPlaybackProvider extends SdkPlaybackProvider {
  LuminaPlaybackProvider(this.service, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final LuminaService service;
  final DateTime Function() _now;
  final _materials = <String, ({DateTime at, Map<String, dynamic> result})>{};
  final _qualities = <String, ({DateTime at, List<SdkQuality> items})>{};
  @override
  String get id => 'lumina';
  @override
  String get name => 'Lumina';
  @override
  bool get supportsQualities => true;
  @override
  String get automaticQualityLabel => '自动（4K 优先）';
  @override
  int qualityPreference(SdkQuality quality) => switch (quality.height) {
    2160 => 30000,
    1080 => 20000,
    _ => quality.height ?? 0,
  };

  String _key(String id, String code, String part) =>
      '$id\u0000$code\u0000$part';

  int? _height(Map media) {
    final explicit =
        SdkQuality.resolution(media['height']) ??
        SdkQuality.resolution(media['resolution']);
    if (explicit != null) return explicit;
    // SDK 的真实 desc/title 合成为“4K 超清 / 1080P 高清”，只认明确档位。
    final token = RegExp(
      r'\b(?:[48]k|\d{3,5}p)\b',
      caseSensitive: false,
    ).firstMatch('${media['name'] ?? ''}');
    return token == null ? null : SdkQuality.resolution(token[0]);
  }

  List<Map<String, dynamic>> _medias(Map<String, dynamic> result) => [
    for (final raw
        in result['medias'] is List
            ? result['medias'] as List
            : [result['media']])
      if (raw is Map && raw['url'] is String) Map<String, dynamic>.from(raw),
  ];

  List<SdkQuality> _describe(Map<String, dynamic> result) {
    final distinct = <String, SdkQuality>{};
    for (final media in _medias(result)) {
      final height = _height(media),
          code = height == null ? 'unknown' : '${height}p';
      distinct.putIfAbsent(
        code,
        () => SdkQuality(code, height: height, name: '${media['name'] ?? ''}'),
      );
    }
    return distinct.values.toList();
  }

  Future<Map<String, dynamic>> _resolve(
    String id,
    String code,
    SdkEpisode episode,
    CancelToken? cancel,
  ) async {
    if (episode.reference == null || episode.code != code) {
      throw const SourceException('INVALID_REFERENCE', '动漫剧集引用无效');
    }
    final known = await episodes(id, code, cancel: cancel);
    if (known.where((e) => e.reference == episode.reference).length != 1) {
      throw const SourceException('IDENTITY_MISMATCH', '动漫剧集不属于当前目录');
    }
    return service.play(id, code, episode.reference!, cancel: cancel);
  }

  @override
  Future<List<SdkQuality>> qualitiesForEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    CancelToken? cancel,
  }) async {
    final key = _key(id, code, episode.identityKey), cached = _qualities[key];
    if (cached != null &&
        _now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.items;
    }
    final result = await _resolve(id, code, episode, cancel);
    if (result['status'] != 'ready') return const [];
    final items = _describe(result);
    _qualities[key] = (at: _now(), items: items);
    // 预解析只在页面内短暂复用；消费后丢弃直链，失效重试必须重新取凭证。
    _materials[key] = (at: _now(), result: result);
    if (_qualities.length > 16) _qualities.remove(_qualities.keys.first);
    if (_materials.length > 8) _materials.remove(_materials.keys.first);
    return items;
  }

  @override
  // 页面资料刷新必须重新取 parts；同一轮的分线路查询继续复用服务目录缓存。
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) {
    _materials.removeWhere((key, _) => key.startsWith('$id\u0000'));
    _qualities.removeWhere((key, _) => key.startsWith('$id\u0000'));
    return service.detail(id, cancel: cancel, refresh: true);
  }

  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async {
    final video = await service.detail(id, cancel: cancel);
    final lines = video.parts.where((p) => p.play == code).toList();
    return lines.length == 1 ? lines.single.episodes : const [];
  }

  @override
  Future<Map<String, dynamic>> playEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    final part = episode.reference;
    if (part == null || episode.code != code) {
      throw const SourceException('INVALID_REFERENCE', '动漫剧集引用无效');
    }
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    final key = _key(id, code, part), cached = _materials.remove(key);
    final result =
        cached != null &&
            _now().difference(cached.at) < const Duration(seconds: 27)
        ? cached.result
        : await _resolve(id, code, episode, cancel);
    if (result['status'] != 'ready') return result;
    final materials = _medias(result);
    if (materials.isEmpty) {
      return {'status': 'unavailable', 'error': 'INVALID_MEDIA'};
    }
    final descriptions = _describe(result);
    _qualities[key] = (at: _now(), items: descriptions);
    if (_qualities.length > 16) _qualities.remove(_qualities.keys.first);
    Map<String, dynamic>? selected;
    if (quality != null) {
      selected = materials
          .where(
            (m) =>
                (_height(m) == null ? 'unknown' : '${_height(m)}p') == quality,
          )
          .firstOrNull;
    } else {
      materials.sort(
        (a, b) => qualityPreference(
          SdkQuality('', height: _height(b)),
        ).compareTo(qualityPreference(SdkQuality('', height: _height(a)))),
      );
      selected = materials.first;
    }
    if (selected == null) {
      return {'status': 'unavailable', 'error': 'QUALITY_UNAVAILABLE'};
    }
    return {
      ...result,
      'media': selected,
      'selection': {'videoId': id, 'code': code, 'episodeRef': part},
    };
  }

  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    final matches = (await episodes(
      id,
      code,
      cancel: cancel,
    )).where((e) => e.number == episode).toList();
    if (matches.length != 1) {
      throw const SourceException('INVALID_REFERENCE', '缺少唯一真实动漫剧集');
    }
    return playEpisode(
      id,
      code,
      matches.single,
      quality: quality,
      cancel: cancel,
    );
  }
}
