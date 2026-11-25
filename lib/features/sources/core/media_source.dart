/// Multi-source contracts: one interface per content provider, one registry.
library;

import 'media_models.dart';

/// What a source can actually do. The UI reads this instead of guessing from
/// the source id.
class MediaSourceCapabilities {
  const MediaSourceCapabilities({
    this.search = true,
    this.categories = true,
    this.qualitySelection = true,
    this.adGate = false,
    this.requiresLogin = false,
    this.danmaku = false,
  });

  final bool search;
  final bool categories;
  final bool qualitySelection;

  /// The play URL is gated behind a rewarded-ad session.
  final bool adGate;

  /// Browsing works anonymously but playback needs a token.
  final bool requiresLogin;
  final bool danmaku;
}

enum MediaSourceErrorKind {
  network,
  protocol,
  authentication,
  vipRequired,
  adRequired,
  expired,
  notFound,
  unsupported,
  cancelled,
  unknown,
}

class MediaSourceException implements Exception {
  const MediaSourceException(
    this.kind,
    this.message, {
    this.code,
    this.retryable = false,
    this.cause,
  });

  final MediaSourceErrorKind kind;
  final String message;
  final int? code;
  final bool retryable;
  final Object? cause;

  @override
  String toString() =>
      'MediaSourceException(${kind.name}${code == null ? '' : ' $code'}: $message)';
}

/// One content provider.
///
/// Implementations are stateless from the UI's point of view: every method is
/// safe to call concurrently and returns normalized models only.
abstract class MediaSource {
  /// Stable machine id, e.g. `clicli`.
  String get id;

  /// User-facing name.
  String get displayName;

  MediaSourceCapabilities get capabilities;

  /// Warm caches / negotiate sessions ahead of the first screen.
  Future<void> warmUp() async {}

  /// Drop cached browse data; called by pull-to-refresh.
  void invalidateCache() {}

  Future<HomeFeed> loadHome({int page = 1});

  /// Load a channel-specific home feed (banners + curated modules).
  /// Defaults to [loadHome] for sources that do not split feeds by category.
  Future<HomeFeed> loadChannelHome(String categoryId, {int page = 1}) =>
      loadHome(page: page);

  Future<List<MediaCategory>> loadCategories();

  Future<MediaPage> browse({
    required String categoryId,
    int page = 1,
    String sort = '',
    String billing = '',
  });

  Future<MediaPage> search(String keyword, {int page = 1});

  Future<MediaDetail> loadDetail(String mediaId);

  /// Available qualities for one episode of one road.
  Future<List<MediaQuality>> loadQualities({
    required String mediaId,
    required String roadCode,
    required int episode,
  });

  /// Resolve a directly playable URL. The returned URL may be short-lived
  /// (CliCli: ~20s), so call this immediately before handing it to the player.
  Future<MediaPlaybackSource> resolvePlayback({
    required String mediaId,
    required String roadCode,
    required int episode,
    String? quality,
  });

  /// Warm whatever the next [resolvePlayback] needs (quality list, exchange
  /// token) without minting a play URL. Failures are swallowed: the real
  /// resolve runs the same requests again.
  Future<void> prefetchPlayback({
    required String mediaId,
    required String roadCode,
    required int episode,
  }) async {}

  Future<void> dispose() async {}
}

/// Source registry. Later playback providers register next to CliCli without
/// touching the UI.
class MediaSourceRegistry {
  MediaSourceRegistry({Iterable<MediaSource> sources = const []}) {
    for (final source in sources) {
      register(source);
    }
  }

  final Map<String, MediaSource> _sources = <String, MediaSource>{};

  void register(MediaSource source) => _sources[source.id] = source;

  MediaSource? maybeById(String id) => _sources[id];

  MediaSource byId(String id) {
    final source = _sources[id];
    if (source == null) {
      throw MediaSourceException(
        MediaSourceErrorKind.notFound,
        'source "$id" is not registered',
      );
    }
    return source;
  }

  List<MediaSource> get all => List<MediaSource>.unmodifiable(_sources.values);

  bool get isEmpty => _sources.isEmpty;

  MediaSource? get primary {
    final list = all;
    return list.isEmpty ? null : list.first;
  }
}

/// Tiny TTL cache with in-flight de-duplication.
///
/// Two screens asking for the same feed at the same time share one request.
class TtlCache {
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  Future<T> fetch<T>(
    String key,
    Duration ttl,
    Future<T> Function() loader,
  ) {
    final now = DateTime.now();
    final hit = _entries[key];
    if (hit != null && hit.expiresAt.isAfter(now)) {
      return hit.value.then((value) => value as T);
    }
    final future = loader();
    _entries[key] = _CacheEntry(future, now.add(ttl));
    return future.then(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        _entries.remove(key);
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  void invalidate(String prefix) {
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clear() => _entries.clear();
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final Future<Object?> value;
  final DateTime expiresAt;
}
