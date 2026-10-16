import 'package:dio/dio.dart';
import '../runtime/source_runtime.dart';
import '../source_models.dart' show SourceException;
import 'lumina_models.dart';
export 'lumina_models.dart';

typedef LuminaRequest =
    Future<Map<String, dynamic>> Function(
      String operation,
      Map<String, dynamic> payload,
      CancelToken? cancel,
    );

class LuminaService {
  LuminaService({LuminaRequest? request, SourceRuntimeClient? runtime})
    : _request = request,
      _runtime = runtime ?? (request == null ? SourceRuntimeClient() : null);
  final LuminaRequest? _request;
  final SourceRuntimeClient? _runtime;
  final _details = <String, ({DateTime at, LuminaVideo video})>{};
  final _catalogs =
      <String, ({DateTime at, int size, Map<String, dynamic> data})>{};
  void clearCatalogCache() => _catalogs.clear();
  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> payload, {
    CancelToken? cancel,
  }) async {
    final result =
        await (_request?.call(operation, payload, cancel) ??
            _runtime!.callLumina(
              operation,
              payload: payload,
              cancelToken: cancel,
            ));
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    if (result['data'] is! Map) {
      throw const SourceException('PARSE_ERROR', '动漫来源数据格式异常');
    }
    return Map<String, dynamic>.from(result['data'] as Map);
  }

  Future<List<LuminaChannel>> channels({CancelToken? cancel}) async {
    final data = await call('channels', const {}, cancel: cancel);
    return [
      for (final raw
          in data['channels'] is List ? data['channels'] as List : const [])
        if (raw is Map && luminaText(raw['id']).isNotEmpty)
          LuminaChannel.fromJson(raw),
    ];
  }

  Future<List<LuminaBanner>> banners(
    String channelId, {
    CancelToken? cancel,
  }) async {
    final data = await call('banners', {
      'channelId': channelId,
    }, cancel: cancel);
    return [
      for (final raw
          in data['banners'] is List ? data['banners'] as List : const [])
        if (raw is Map &&
            RegExp(r'^\d{1,64}$').hasMatch(luminaText(raw['videoId'])))
          LuminaBanner.fromJson(raw),
    ];
  }

  Future<LuminaPage> catalog(
    String channelId, {
    int page = 1,
    int size = 24,
    String sort = 'weight',
    bool refresh = false,
    CancelToken? cancel,
  }) async {
    final key = '$channelId|$page|$sort';
    final cached = _catalogs[key];
    // 同频道首屏包含榜单所需的前十条；仅缓存目录，播放凭证和直链仍现取现用。
    if (!refresh &&
        cached != null &&
        cached.size >= size &&
        (page == 1 || cached.size == size) &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 1) &&
        cancel?.isCancelled != true) {
      return LuminaPage.fromJson(
        {
          ...cached.data,
          'videos': (cached.data['videos'] as List? ?? const [])
              .take(size)
              .toList(),
        },
        page: page,
        size: size,
      );
    }
    final data = await call('catalog', {
      'channelId': channelId,
      'pageIndex': page,
      'pageSize': size,
      'sort': sort,
    }, cancel: cancel);
    if (_catalogs.length >= 12) _catalogs.remove(_catalogs.keys.first);
    _catalogs[key] = (at: DateTime.now(), size: size, data: data);
    return LuminaPage.fromJson(data, page: page, size: size);
  }

  Future<LuminaPage> search(
    String keyword, {
    int page = 1,
    int size = 20,
    CancelToken? cancel,
  }) async => LuminaPage.fromJson(
    await call('search', {
      'keyword': keyword.trim(),
      'pageIndex': page,
      'pageSize': size,
    }, cancel: cancel),
    page: page,
    size: size,
  );
  Future<LuminaVideo> detail(
    String id, {
    CancelToken? cancel,
    bool refresh = false,
  }) async {
    final cached = _details[id];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.video;
    }
    final data = await call('detail', {'videoId': id}, cancel: cancel);
    if (data['video'] is! Map) {
      throw const SourceException('PARSE_ERROR', '作品资料格式异常');
    }
    final parts = [
      for (final raw
          in data['parts'] is List ? data['parts'] as List : const [])
        if (raw is Map && luminaText(raw['play']).isNotEmpty)
          LuminaPart.fromJson(raw),
    ];
    final video = LuminaVideo.fromJson(data['video'] as Map, parts: parts);
    if (video.id != id) {
      throw const SourceException('IDENTITY_MISMATCH', '作品资料身份不符');
    }
    _details[id] = (at: DateTime.now(), video: video);
    if (_details.length > 32) _details.remove(_details.keys.first);
    return video;
  }

  Future<Map<String, dynamic>> play(
    String id,
    String code,
    String part, {
    CancelToken? cancel,
  }) => call('play', {
    'videoId': id,
    'playFormat': code,
    'part': part,
  }, cancel: cancel);
  void dispose() {
    _details.clear();
    _catalogs.clear();
    _runtime?.dispose();
  }
}
