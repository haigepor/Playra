/// 红果短剧的播放提供方（SdkPlaybackProvider）。
///
/// 目录只有一条线（红果官方源）；清晰度来自 video_model 的各清晰度流。
/// 加密分集在 media map 里带回 decryptionKey，由播放器经 mpv 的
/// demuxer-lavf-o 注入解密。
///
/// 自动画质即最高画质：coordinator 按 [SdkPlaybackProvider.qualityPreference]
/// （= height）降序尝试档位；本方 [playEpisode] 在 quality 为空时同样取
/// 最高档，档位查询失败时不静默降档。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../sdk_playback_models.dart';
import '../sdk_playback_provider.dart';
import '../source_models.dart';
import 'hongguo_client.dart';
import 'hongguo_models.dart';

/// resolvePlayback 结果的短效缓存窗口。prepare（画质探测）与 playEpisode
/// 共享同一次解析，避免同一集一秒内两次上游调用；URL 本身约 6h 有效，
/// 缓存只是去抖动，不是长效材料。
const Duration _resolveCacheTtl = Duration(seconds: 90);

class HongguoPlaybackProvider extends SdkPlaybackProvider {
  HongguoPlaybackProvider(this.client);

  final HongguoClient client;

  @override
  String get id => 'hongguo';

  @override
  String get name => '红果短剧';

  @override
  bool get supportsQualities => true;

  @override
  String get automaticQualityLabel => '自动（最高画质）';

  /// 单一线路：官方源。
  static const String _lineCode = 'main';

  final Map<String, (HongguoPlayback, HongguoContentKey?, DateTime)> _resolveCache =
      {};

  Future<(HongguoSeries, List<HongguoEpisode>)> _fetchDetail(
    String id, {
    CancelToken? cancel,
  }) {
    return client.getSeries(id, cancel: cancel);
  }

  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async {
    final (series, _) = await _fetchDetail(id, cancel: cancel);
    return SdkVideoData(
      id: id,
      title: series.title,
      categoryName: '短剧',
      cover: series.coverUrl,
      poster: series.coverUrl,
      description: series.description,
      lines: [SdkLine(_lineCode, '红果')],
      singleMovie: false,
    );
  }

  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async {
    if (code != _lineCode) {
      throw const SourceException('UNKNOWN_SOURCE', '线路不存在或已下架');
    }
    final (_, episodes) = await _fetchDetail(id, cancel: cancel);
    if (episodes.isEmpty) {
      throw const SourceException('UPSTREAM_LIMIT', '上游未返回分集');
    }
    return [
      // reference（episode id）是唯一选集身份；vid_index 是真实集号。
      for (final episode in episodes)
        SdkEpisode(
          number: episode.number,
          name: episode.title,
          code: code,
          reference: episode.id,
        ),
    ];
  }

  Future<(HongguoPlayback, HongguoContentKey?)> _resolve(
    String reference, {
    CancelToken? cancel,
  }) async {
    final cached = _resolveCache[reference];
    if (cached != null) {
      final (pb, key, at) = cached;
      if (DateTime.now().difference(at) < _resolveCacheTtl) {
        return (pb, key);
      }
      _resolveCache.remove(reference);
    }
    final result = await client.resolvePlayback(reference, cancel: cancel);
    _resolveCache[reference] = (result.$1, result.$2, DateTime.now());
    // 防御性收敛：只缓存活跃的几集，避免长会话膨胀。
    while (_resolveCache.length > 6) {
      _resolveCache.remove(_resolveCache.keys.first);
    }
    return result;
  }

  @override
  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) async {
    final matches = (await episodes(id, code, cancel: cancel))
        .where((entry) => entry.number == episode)
        .toList();
    if (matches.length != 1) return const [];
    return qualitiesForEpisode(id, code, matches.single, cancel: cancel);
  }

  @override
  Future<List<SdkQuality>> qualitiesForEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    CancelToken? cancel,
  }) async {
    final reference = episode.reference;
    if (reference == null || reference.isEmpty) return const [];
    final (pb, _) = await _resolve(reference, cancel: cancel);
    return _qualitiesOf(pb);
  }

  List<SdkQuality> _qualitiesOf(HongguoPlayback pb) {
    final qualities = <SdkQuality>[];
    for (final stream in pb.streams) {
      final height = SdkQuality.resolution(stream.definition) ??
          SdkQuality.resolution(stream.height);
      qualities.add(SdkQuality(
        stream.definition,
        name: stream.definition,
        height: height,
      ));
    }
    return qualities;
  }

  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    final matches = (await episodes(id, code, cancel: cancel))
        .where((entry) => entry.number == episode)
        .toList();
    if (matches.length != 1) {
      throw const SourceException('INVALID_REFERENCE', '缺少唯一对应剧集');
    }
    return playEpisode(
      id,
      code,
      matches.single,
      quality: quality,
      cancel: cancel,
    );
  }

  @override
  Future<Map<String, dynamic>> playEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    if (code != _lineCode) {
      throw const SourceException('UNKNOWN_SOURCE', '线路不存在或已下架');
    }
    final reference = episode.reference;
    if (reference == null || reference.isEmpty) {
      throw const SourceException('INVALID_REFERENCE', '选集令牌缺失');
    }
    final (pb, key) = await _resolve(reference, cancel: cancel);
    if (pb.streams.isEmpty) {
      return {'status': 'unavailable', 'error': 'UPSTREAM_LIMIT'};
    }
    final stream = _pickStream(pb, quality);
    if (stream == null) {
      return {'status': 'unavailable', 'error': 'UPSTREAM_LIMIT'};
    }
    if (kDebugMode) {
      debugPrint(
        'HONGGUO play ep=$reference requested=${quality ?? 'auto'} '
        'chosen=${stream.definition} h=${stream.height}',
      );
    }
    return {
      'status': 'ready',
      'media': {
        'url': stream.url.isNotEmpty ? stream.url : stream.backupUrl,
        if (key != null && key.hex.isNotEmpty) 'decryptionKey': key.hex,
        // URL 签名约 6 小时有效；prepared 复用走 expiresAt 判定。
        if (pb.expiresAt > 0)
          'expiresAt':
              DateTime.fromMillisecondsSinceEpoch(pb.expiresAt * 1000)
                  .toIso8601String(),
      },
      'selection': {
        'videoId': id,
        'code': code,
        'episodeRef': episode.identityKey,
      },
    };
  }

  /// [quality] 为空（自动）时取最高档；请求了明确档位却缺失时返回 null，
  /// 绝不静默降档（与 coordinator 的“明确偏好交实际解析校验”一致）。
  HongguoStream? _pickStream(HongguoPlayback pb, String? quality) {
    final playable = pb.streams.where((s) => s.url.isNotEmpty).toList();
    if (playable.isEmpty) return null;
    if (quality == null || quality.isEmpty) {
      playable.sort((a, b) => b.height.compareTo(a.height));
      return playable.first;
    }
    for (final stream in playable) {
      if (stream.definition == quality) return stream;
    }
    return null;
  }

  @override
  void invalidatePlayback(String id, String code, SdkEpisode episode) {
    // 播放地址被拒（403/410）时丢掉该集的缓存解析，下一次重取。
    final reference = episode.reference;
    if (reference != null && reference.isNotEmpty) {
      _resolveCache.remove(reference);
    }
  }
}
