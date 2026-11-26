/// CliCli implementation of [MediaSource].
///
/// Covers browse/search/detail/qualities and the full rewarded-ad gate that
/// `resolve/exchange` requires. Play URLs are valid for ~20s, so they are
/// resolved on demand and never cached.
library;

import '../core/media_models.dart';
import '../core/media_source.dart';
import 'clicli_api.dart';
import 'clicli_client.dart';
import 'clicli_config.dart';
import 'clicli_models.dart';

class CliCliSource implements MediaSource {
  CliCliSource({CliCliClient? client, CliCliApi? api})
    : _client = client ?? CliCliClient() {
    _api = api ?? CliCliApi(_client);
  }

  final CliCliClient _client;
  late final CliCliApi _api;
  final TtlCache _cache = TtlCache();

  String? _placementIdCache;
  bool _devicePass = false;
  DateTime? _devicePassUntil;
  static const Duration _devicePassTtl = Duration(minutes: 10);

  static const List<String> _adEvents = <String>[
    'load',
    'start',
    'first_quartile',
    'midpoint',
    'third_quartile',
    'complete',
  ];

  @override
  String get id => CliCliConfig.sourceId;

  @override
  String get displayName => CliCliConfig.sourceName;

  @override
  MediaSourceCapabilities get capabilities => const MediaSourceCapabilities(
    search: true,
    categories: true,
    qualitySelection: true,
    adGate: true,
    danmaku: false,
  );

  @override
  Future<void> warmUp() async {
    await Future.wait<void>(<Future<void>>[
      loadHome().then((_) {}, onError: (_) {}),
      loadCategories().then((_) {}, onError: (_) {}),
      // 首次播放还要先拿广告投放位，提前一次可以省掉一个往返。
      _placementId().then((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Future<HomeFeed> loadHome({int page = 1}) => loadChannelHome('', page: page);

  @override
  Future<HomeFeed> loadChannelHome(String categoryId, {int page = 1}) {
    return _cache.fetch<HomeFeed>(
      'home:$categoryId:$page',
      const Duration(minutes: 2),
      () async {
        final modulesFuture = _read(
          () => _api.modules(categoryId: categoryId, page: page),
        );
        // Banners are decorative: a failure here must not blank the feed.
        final bannersFuture = _read(() => _api.banners(categoryId: categoryId))
            .then(
              (data) => bannersFromData(data),
              onError: (_) => const <MediaBanner>[],
            );
        final data = await modulesFuture;
        final banners = await bannersFuture;
        return HomeFeed(
          banners: banners,
          sections: homeFeedFromModules(data).sections,
        );
      },
    );
  }

  @override
  Future<List<MediaCategory>> loadCategories() {
    return _cache.fetch<List<MediaCategory>>(
      'categories',
      const Duration(hours: 1),
      () async {
        final data = await _read(() => _api.allTypes());
        return categoriesFromTypes(data);
      },
    );
  }

  @override
  Future<MediaPage> browse({
    required String categoryId,
    int page = 1,
    String sort = '',
    String billing = '',
  }) {
    return _cache.fetch<MediaPage>(
      'browse:$categoryId:$sort:$billing:$page',
      const Duration(minutes: 1),
      () async {
        final data = await _read(
          () => _api.categoryVideos(
            categoryId: categoryId,
            page: page,
            sort: switch (sort) {
              'hot' => 'hottest',
              'new' => 'latest',
              _ => sort,
            },
            billing: billing,
          ),
        );
        return mediaPageFromVideos(data);
      },
    );
  }

  @override
  Future<MediaPage> search(String keyword, {int page = 1}) {
    final term = keyword.trim();
    if (term.isEmpty) {
      return Future<MediaPage>.value(const MediaPage(items: <MediaItem>[]));
    }
    return _cache.fetch<MediaPage>(
      'search:$term:$page',
      const Duration(minutes: 3),
      () async {
        final data = await _read(() => _api.search(term, page: page));
        return mediaPageFromVideos(data);
      },
    );
  }

  @override
  Future<MediaDetail> loadDetail(String mediaId) {
    return _cache.fetch<MediaDetail>(
      'detail:$mediaId',
      const Duration(minutes: 2),
      () async {
        final detailFuture = _read(() => _api.videoDetail(mediaId));
        final episodesFuture = _read(() => _api.episodes(mediaId));
        final data = await detailFuture;
        final episodes = await episodesFuture;
        final video = data['video'];
        if (video is! Map) {
          throw const MediaSourceException(
            MediaSourceErrorKind.notFound,
            '作品不存在或已下架',
          );
        }
        return mediaDetailFromVideo(
          Map<String, dynamic>.from(video),
          episodes: episodes,
        );
      },
    );
  }

  @override
  Future<List<MediaQuality>> loadQualities({
    required String mediaId,
    required String roadCode,
    required int episode,
  }) async {
    final options = await _episodeOptions(mediaId, roadCode, episode);
    return options.qualities;
  }

  @override
  Future<void> prefetchPlayback({
    required String mediaId,
    required String roadCode,
    required int episode,
  }) async {
    try {
      await _episodeOptions(mediaId, roadCode, episode);
    } catch (_) {
      // 预热只是省一个往返；失败时下一次真实解析会重新请求。
    }
  }

  @override
  Future<MediaPlaybackSource> resolvePlayback({
    required String mediaId,
    required String roadCode,
    required int episode,
    String? quality,
  }) async {
    // An entitled account may not need an ad token. Only request one after
    // the server explicitly reports the ad gate.
    var options = await _episodeOptions(mediaId, roadCode, episode);
    var adToken = '';
    var selected = _pickQuality(options.qualities, quality);
    final automatic = quality == null || quality.isEmpty;
    var fellBack = false;

    var adRetries = 0;
    while (true) {
      try {
        final exchanged = await _read(
          () => _api.exchange(
            videoId: mediaId,
            code: roadCode,
            episode: episode,
            quality: selected.id,
            exchangeToken: options.exchangeToken,
            adToken: adToken,
          ),
        );
        final source = playbackSourceFromExchange(exchanged);
        if (source.url.isNotEmpty) return source;
        throw const MediaSourceException(
          MediaSourceErrorKind.notFound,
          '播放凭证未下发 playUrl',
        );
      } on MediaSourceException catch (error) {
        if (automatic &&
            !fellBack &&
            _is4k(selected.id) &&
            (error.kind == MediaSourceErrorKind.vipRequired ||
                error.kind == MediaSourceErrorKind.notFound ||
                error.code == 4206)) {
          final fallback = options.qualities.where(
            (q) => q.id.toLowerCase() == '1080p',
          );
          if (fallback.isEmpty) rethrow;
          selected = fallback.first;
          fellBack = true;
          adRetries = 0;
        } else if ((error.code == 4031 ||
                error.kind == MediaSourceErrorKind.adRequired) &&
            adRetries++ == 0) {
          // A consumed ad token must never be reused.
        } else {
          rethrow;
        }
        _cache.invalidate(_optionsKey(mediaId, roadCode, episode));
        options = await _episodeOptions(mediaId, roadCode, episode);
        adToken =
            error.code == 4031 || error.kind == MediaSourceErrorKind.adRequired
            ? await _obtainAdToken()
            : '';
      }
    }
  }

  String _optionsKey(String mediaId, String roadCode, int episode) =>
      'options:$mediaId:$roadCode:$episode';

  /// quality list + exchangeToken for one episode, cached briefly.
  ///
  /// The token stays valid for several minutes, so caching it makes retries and
  /// quality switches skip a round trip; play URLs are still minted per call.
  Future<_EpisodePlaybackOptions> _episodeOptions(
    String mediaId,
    String roadCode,
    int episode,
  ) {
    return _cache.fetch<_EpisodePlaybackOptions>(
      _optionsKey(mediaId, roadCode, episode),
      const Duration(minutes: 2),
      () async {
        final data = await _read(
          () => _api.qualities(
            videoId: mediaId,
            code: roadCode,
            episode: episode,
          ),
        );
        final qualities = qualitiesFromData(data);
        if (qualities.isEmpty) {
          throw const MediaSourceException(
            MediaSourceErrorKind.protocol,
            '该线路没有可用清晰度',
          );
        }
        final exchangeToken = _stringOf(data['exchangeToken']);
        if (exchangeToken.isEmpty) {
          throw const MediaSourceException(
            MediaSourceErrorKind.protocol,
            '缺少播放凭证 exchangeToken',
          );
        }
        return _EpisodePlaybackOptions(
          qualities: qualities,
          exchangeToken: exchangeToken,
        );
      },
    );
  }

  @override
  void invalidateCache() {
    _cache.clear();
    _placementIdCache = null;
    _devicePass = false;
    _devicePassUntil = null;
  }

  @override
  Future<void> dispose() async {
    _cache.clear();
    _client.close();
  }

  // ------------------------------------------------------------------ gate

  Future<String> _obtainAdToken() async {
    const slotCode = CliCliConfig.playerPreRollSlot;
    final placementId = await _placementId();

    // 设备已直通（shouldShow=false）时，签名只是再确认一次；短 TTL 内直接
    // claim。claim 拿不到 token 就自动回退到完整流程，不会卡死。
    final passUntil = _devicePassUntil;
    if (_devicePass && passUntil != null && passUntil.isAfter(DateTime.now())) {
      final quickToken = await _claimAdToken(
        slotCode: slotCode,
        placementId: placementId,
      );
      if (quickToken.isNotEmpty) return quickToken;
      _devicePass = false;
      _devicePassUntil = null;
    }

    final config = await _read(
      () => _api.adConfig(slotCode: slotCode, placementId: placementId),
    );
    final nonce = _stringOf(config['nonce']);
    if (nonce.isEmpty) {
      throw const MediaSourceException(
        MediaSourceErrorKind.adRequired,
        '广告配置缺少 nonce',
      );
    }
    final sessionId = _api.newSessionId();
    final signatureData = await _read(
      () => _api.adSignature(
        adSessionId: sessionId,
        slotCode: slotCode,
        slotId: placementId,
      ),
    );
    final signature = _stringOf(signatureData['signature']);
    final shouldShow = signatureData['shouldShow'];
    // `shouldShow:false / denyReason:"device_pass"` means the device has
    // already been cleared for this slot: no ad session is issued and
    // claimReward hands out the adToken directly (verified live).
    if (signature.isNotEmpty && shouldShow != false) {
      for (final event in _adEvents) {
        await _read(
          () => _api.reportAdEvent(
            clientTs: _api.nowMs,
            duration: event == 'complete' ? 15 : 0,
            eventType: event,
            nonce: nonce,
            signature: signature,
            slotCode: slotCode,
          ),
        );
      }
    }
    final claim = await _read(
      () => _api.claimReward(nonce: nonce, slotCode: slotCode),
    );
    var token = _stringOf(claim['adToken']);
    if (token.isEmpty && signature.isEmpty) {
      // Some devices are asked for a signature on the first claim only;
      // refetch the config so the next attempt carries a fresh nonce.
      throw const MediaSourceException(
        MediaSourceErrorKind.adRequired,
        '广告奖励未发放 adToken',
        retryable: true,
      );
    }
    if (token.isEmpty) {
      throw const MediaSourceException(
        MediaSourceErrorKind.adRequired,
        '广告奖励未发放 adToken',
      );
    }
    if (shouldShow == false) {
      _devicePass = true;
      _devicePassUntil = DateTime.now().add(_devicePassTtl);
    }
    return token;
  }

  /// Fresh nonce + claim, skipping the ad signature. Only valid while the
  /// device is known to be cleared for this slot.
  Future<String> _claimAdToken({
    required String slotCode,
    required String placementId,
  }) async {
    final config = await _read(
      () => _api.adConfig(slotCode: slotCode, placementId: placementId),
    );
    final nonce = _stringOf(config['nonce']);
    if (nonce.isEmpty) return '';
    final claim = await _read(
      () => _api.claimReward(nonce: nonce, slotCode: slotCode),
    );
    return _stringOf(claim['adToken']);
  }

  Future<String> _placementId() async {
    final cached = _placementIdCache;
    if (cached != null) return cached;
    final data = await _read(() => _api.adSlots());
    final slots = data['slots'];
    var placementId = '';
    if (slots is List) {
      for (final slot in slots) {
        if (slot is! Map) continue;
        if (_stringOf(slot['slotCode']) != CliCliConfig.playerPreRollSlot) {
          continue;
        }
        placementId = _stringOf(slot['placementId']).isEmpty
            ? _stringOf(slot['slotId'])
            : _stringOf(slot['placementId']);
        break;
      }
    }
    _placementIdCache = placementId;
    return placementId;
  }

  bool _is4k(String id) =>
      const <String>{'4k', '2160p', 'uhd'}.contains(id.toLowerCase());

  MediaQuality _pickQuality(List<MediaQuality> qualities, String? requested) {
    if (requested != null && requested.isNotEmpty) {
      for (final quality in qualities) {
        if (quality.id == requested) return quality;
      }
    }
    for (final quality in qualities) {
      if (_is4k(quality.id)) return quality;
    }
    for (final preferred in const <String>['1080p', '720p', '540p']) {
      for (final quality in qualities) {
        if (quality.id == preferred && !quality.vipOnly) return quality;
      }
    }
    for (final quality in qualities) {
      if (!quality.vipOnly) return quality;
    }
    return qualities.first;
  }

  /// Reads retry once on transport errors; writes are handled by the caller.
  Future<T> _read<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on MediaSourceException catch (error) {
      if (!error.retryable) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return load();
    }
  }
}

class _EpisodePlaybackOptions {
  const _EpisodePlaybackOptions({
    required this.qualities,
    required this.exchangeToken,
  });

  final List<MediaQuality> qualities;
  final String exchangeToken;
}

String _stringOf(Object? value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}
