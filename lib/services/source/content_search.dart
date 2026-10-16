import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'source_models.dart';
import 'source_resolve_config.dart';
import 'sdk_playback_provider.dart';

/// 展示频道与旧 anime/screen 来源领域分开，地区不参与频道划分。
enum ContentGroup {
  anime('动漫'),
  screen('影视'),
  comicDrama('漫剧'),
  series('剧集');

  const ContentGroup(this.label);
  final String label;
  static ContentGroup? fromKind(String kind) => switch (kind) {
    'anime' => anime,
    'movie' || 'variety' || 'documentary' => screen,
    'comicDrama' => comicDrama,
    'series' || 'tv' || 'shortDrama' => series,
    _ => null,
  };
}

class ContentQuery {
  const ContentQuery(this.keyword, {this.group, this.region = ''});
  final String keyword;
  final ContentGroup? group;
  final String region;
}

Set<String> contentRegions(String value) {
  final text = value.toUpperCase();
  final tokens = text.split(RegExp(r'[/,，;；\s]+')).toSet();
  final result = <String>{};
  for (final entry in const {
    'CN': ['CN', '中国', '大陆', '内地', '国产'],
    'HK': ['HK', '香港'],
    'TW': ['TW', '台湾'],
    'JP': ['JP', '日本'],
    'KR': ['KR', '韩国'],
    'US': ['US', '美国'],
    'GB': ['GB', '英国'],
    'TH': ['TH', '泰国'],
  }.entries) {
    if (tokens.contains(entry.key) || entry.value.skip(1).any(text.contains)) {
      result.add(entry.key);
    }
  }
  return result;
}

class ContentHit {
  const ContentHit({
    required this.providerId,
    required this.contentId,
    required this.title,
    required this.group,
    this.cover = '',
    this.year,
    this.edition,
    this.metadataId,
    this.aliases = const [],
    this.region = '',
  });
  final String providerId, contentId, title, cover, region;
  final ContentGroup? group;
  final int? year;
  final String? edition, metadataId;
  final List<String> aliases;
  String get key => '$providerId\u0000$contentId';
}

class ContentSearchPage {
  const ContentSearchPage(this.items, {required this.hasMore});
  final List<ContentHit> items;
  final bool hasMore;
}

class ContentEpisode {
  const ContentEpisode(this.id, this.title, {this.number});
  final String id, title;
  final int? number;
}

class ContentLine {
  const ContentLine(this.id, this.name, this.episodes);
  final String id, name;
  final List<ContentEpisode> episodes;
}

abstract class ContentSearchProvider {
  SdkPlaybackProvider? get sdkPlayback => null;
  String get id;
  String get origin => id;
  String get name;
  Set<ContentGroup> get groups;
  bool get canPlay => false;

  /// 展示优先级独立于网络返回顺序；默认保留现有来源顺序。
  int get priority => 0;
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  );
  Future<List<ContentLine>> lines(ContentHit hit, CancelToken cancel) async =>
      throw const SourceException('UNSUPPORTED', '来源未提供播放目录');
  Future<List<ContentEpisode>> episodes(
    ContentHit hit,
    ContentLine line,
    CancelToken cancel,
  ) async => line.episodes;
  Future<SourceResolvedMedia> resolve(
    ContentHit hit,
    ContentLine line,
    ContentEpisode episode,
    CancelToken cancel,
  ) async => throw const SourceException('UNSUPPORTED', '来源未提供播放解析');
  void dispose() {}
}

String contentTitleKey(String value) => value
    .toLowerCase()
    .replaceAllMapped(
      RegExp(r'[\uFF01-\uFF5E]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0),
    )
    .replaceAll(RegExp(r'\[(?:1080p|720p|高清|中字)\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

enum ContentMatch { identity, title, possible, conflict }

/// 只有身份或片名、类型、年份证据充分才聚合，稀疏同名保留为候选。
ContentMatch matchContent(ContentHit a, ContentHit b) {
  if (a.key == b.key) return ContentMatch.identity;
  if (a.group != null && b.group != null && a.group != b.group ||
      a.year != null && b.year != null && a.year != b.year ||
      a.edition != null && b.edition != null && a.edition != b.edition) {
    return ContentMatch.conflict;
  }
  if (a.metadataId != null && b.metadataId != null) {
    return a.metadataId == b.metadataId
        ? ContentMatch.identity
        : ContentMatch.conflict;
  }
  final names = [
    a.title,
    ...a.aliases,
  ].map(contentTitleKey).where((v) => v.isNotEmpty).toSet();
  if (![b.title, ...b.aliases].map(contentTitleKey).any(names.contains)) {
    return ContentMatch.conflict;
  }
  return a.group != null &&
          a.group == b.group &&
          a.year != null &&
          a.year == b.year
      ? ContentMatch.title
      : ContentMatch.possible;
}

class ContentWork {
  ContentWork(ContentHit first, {int Function(String)? providerPriority})
    : id = first.key,
      _hits = {first.key: first},
      _providerPriority = providerPriority ?? _defaultPriority;
  static int _defaultPriority(String _) => 0;
  final int Function(String) _providerPriority;
  final String id;
  final Map<String, ContentHit> _hits;
  List<ContentHit> get hits {
    final indexed = _hits.values.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final rank = _providerPriority(
        b.value.providerId,
      ).compareTo(_providerPriority(a.value.providerId));
      return rank == 0 ? a.key.compareTo(b.key) : rank;
    });
    return List.unmodifiable(indexed.map((e) => e.value));
  }

  ContentHit get primary => hits.first;
  String get title => primary.title;
  String get cover => hits
      .map((h) => h.cover)
      .firstWhere((v) => v.isNotEmpty, orElse: () => '');
  bool accepts(ContentHit hit) => _hits.values.every(
    (h) => switch (matchContent(h, hit)) {
      ContentMatch.identity || ContentMatch.title => true,
      _ => false,
    },
  );
  bool suggests(ContentHit hit) =>
      _hits.values.every((h) => matchContent(h, hit) != ContentMatch.conflict);
}

enum ContentProviderStatus {
  queued,
  searching,
  success,
  empty,
  failed,
  verificationRequired,
}

class ContentSearchSession extends ChangeNotifier {
  ContentSearchSession(
    Iterable<ContentSearchProvider> providers, {
    this.concurrency,
    this.timeout = const Duration(seconds: 20),
    this.batchTimeout = const Duration(seconds: 35),
    this.perOriginConcurrency,
    this.ownsProviders = true,
  }) : providers = List.unmodifiable(providers) {
    if (concurrency != null && concurrency! < 1 ||
        timeout <= Duration.zero ||
        batchTimeout <= Duration.zero ||
        perOriginConcurrency != null && perOriginConcurrency! < 1) {
      throw ArgumentError('Invalid search budget');
    }
    if (this.providers.map((p) => p.id).toSet().length !=
        this.providers.length) {
      throw ArgumentError('Duplicate provider identity');
    }
  }
  final List<ContentSearchProvider> providers;

  /// 默认同时发起全部选中来源；显式限制仅供受限调用方使用。
  final int? concurrency;
  final Duration timeout;
  final Duration batchTimeout;
  final int? perOriginConcurrency;
  final bool ownsProviders;
  final _works = <ContentWork>[];
  final statuses = <String, ContentProviderStatus>{};
  final errors = <String, String>{};
  final _pages = <String, int>{};
  final _more = <String, bool>{};
  ContentQuery? _query;
  CancelToken _cancel = CancelToken();
  int _generation = 0;
  bool _disposed = false, searching = false;
  List<ContentWork> get works {
    final indexed = _works.asMap().entries.toList();
    indexed.sort((a, b) {
      final rank = provider(
        b.value.primary.providerId,
      ).priority.compareTo(provider(a.value.primary.providerId).priority);
      return rank == 0 ? a.key.compareTo(b.key) : rank;
    });
    return List.unmodifiable(indexed.map((e) => e.value));
  }

  bool get hasProviders => statuses.isNotEmpty;
  bool get hasMore => _more.values.any((v) => v);
  int get failures => statuses.values
      .where(
        (s) =>
            s == ContentProviderStatus.failed ||
            s == ContentProviderStatus.verificationRequired,
      )
      .length;
  int get completed => statuses.values
      .where(
        (s) =>
            s != ContentProviderStatus.queued &&
            s != ContentProviderStatus.searching,
      )
      .length;
  ContentSearchProvider provider(String id) =>
      providers.firstWhere((p) => p.id == id);

  Future<void> submit(ContentQuery query) async {
    if (_disposed) return;
    _cancel.cancel('replaced');
    _cancel = CancelToken();
    final generation = ++_generation;
    _works.clear();
    statuses.clear();
    errors.clear();
    _pages.clear();
    _more.clear();
    _query = ContentQuery(
      query.keyword.trim(),
      group: query.group,
      region: query.region,
    );
    if (_query!.keyword.isEmpty || _query!.keyword.length > 300) {
      searching = false;
      notifyListeners();
      return;
    }
    final selected = providers
        .where((p) => query.group == null || p.groups.contains(query.group))
        .toList();
    for (final p in selected) {
      statuses[p.id] = ContentProviderStatus.queued;
    }
    await _fetch(selected, generation);
  }

  Future<void> loadMore() async {
    if (_disposed || searching || _query == null) return;
    await _fetch(
      providers.where((p) => _more[p.id] == true).toList(),
      _generation,
    );
  }

  Future<void> retry(String providerId) async {
    if (_disposed ||
        searching ||
        _query == null ||
        !statuses.containsKey(providerId)) {
      return;
    }
    await _fetch([provider(providerId)], _generation);
  }

  Future<void> _fetch(
    List<ContentSearchProvider> selected,
    int generation,
  ) async {
    if (_cancel.isCancelled) _cancel = CancelToken();
    final root = _cancel;
    bool current() =>
        !_disposed && generation == _generation && !root.isCancelled;
    searching = selected.isNotEmpty;
    notifyListeners();
    final queue = List<ContentSearchProvider>.of(selected);
    final activeOrigins = <String, int>{};
    var released = Completer<void>();
    final deadline = Timer(batchTimeout, () {
      if (!current()) return;
      for (final p in selected) {
        if (statuses[p.id] == ContentProviderStatus.queued ||
            statuses[p.id] == ContentProviderStatus.searching) {
          statuses[p.id] = ContentProviderStatus.failed;
          errors[p.id] = 'TIMEOUT';
        }
      }
      root.cancel('batch deadline');
      searching = false;
      notifyListeners();
    });
    Future<void> worker() async {
      while (current() && queue.isNotEmpty) {
        final index = queue.indexWhere(
          (p) =>
              perOriginConcurrency == null ||
              (activeOrigins[p.origin] ?? 0) < perOriginConcurrency!,
        );
        if (index < 0) {
          await Future.any([released.future, root.whenCancel]);
          continue;
        }
        final p = queue.removeAt(index);
        activeOrigins[p.origin] = (activeOrigins[p.origin] ?? 0) + 1;
        final active = CancelToken();
        unawaited(root.whenCancel.then((_) => active.cancel('session ended')));
        final page = (_pages[p.id] ?? 0) + 1;
        statuses[p.id] = ContentProviderStatus.searching;
        errors.remove(p.id);
        notifyListeners();
        try {
          // 取消/超时都释放搜索槽位；底层不能立即终止时仍丢弃迟到结果。
          final result =
              await Future.any<ContentSearchPage>([
                p.search(_query!, page, active),
                active.whenCancel.then(
                  (_) => throw const SourceException('CANCELLED', '检索已取消'),
                ),
              ]).timeout(
                timeout,
                onTimeout: () {
                  active.cancel('deadline');
                  throw const SourceException('TIMEOUT', '来源检索超时');
                },
              );
          if (!current()) return;
          for (final hit in result.items) {
            if (hit.providerId != p.id ||
                hit.contentId.isEmpty ||
                hit.title.trim().isEmpty ||
                _query!.group != null && hit.group != _query!.group ||
                _query!.region.isNotEmpty &&
                    !contentRegions(hit.region).contains(_query!.region)) {
              continue;
            }
            _upsert(hit);
          }
          _pages[p.id] = page;
          _more[p.id] = result.hasMore;
          statuses[p.id] = result.items.isEmpty
              ? ContentProviderStatus.empty
              : ContentProviderStatus.success;
        } catch (error) {
          if (!current()) return;
          final code = error is SourceException ? error.code : 'SOURCE_ERROR';
          errors[p.id] = code;
          statuses[p.id] = code == 'CHALLENGE_REQUIRED'
              ? ContentProviderStatus.verificationRequired
              : ContentProviderStatus.failed;
        } finally {
          activeOrigins[p.origin] = (activeOrigins[p.origin] ?? 1) - 1;
          if (!released.isCompleted) released.complete();
          released = Completer<void>();
        }
        if (current()) notifyListeners();
      }
    }

    await Future.wait(
      List.generate(
        selected.length.clamp(0, concurrency ?? selected.length),
        (_) => worker(),
      ),
    );
    deadline.cancel();
    if (current()) {
      searching = false;
      notifyListeners();
    }
  }

  void _upsert(ContentHit hit) {
    for (final work in _works) {
      if (work._hits.containsKey(hit.key)) {
        work._hits[hit.key] = hit;
        return;
      }
    }
    final matches = _works.where((work) => work.accepts(hit)).toList();
    // 无年份的同名结果不能把两个已知不同年份的作品桥接起来。
    if (matches.length == 1) {
      matches.single._hits[hit.key] = hit;
    } else {
      _works.add(
        ContentWork(hit, providerPriority: (id) => provider(id).priority),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancel.cancel('disposed');
    if (ownsProviders) {
      for (final p in providers) {
        p.dispose();
      }
    }
    super.dispose();
  }
}
