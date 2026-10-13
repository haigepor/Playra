import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/source_models.dart';

class MioHomeController extends ChangeNotifier {
  MioHomeController(this.service);
  final MioMediaService service;
  static const kinds = [
    MioKind.movie,
    MioKind.series,
    MioKind.variety,
    MioKind.comicDrama,
  ];
  final Map<MioKind, List<MioVideo>> items = {};
  final Map<MioKind, String> categoryIds = {};
  // 提供的 SDK hot_rank_probe.py 已核验；运行时实际元数据可更新同名绑定。
  final Map<String, String> namedCategoryIds = {
    '国产动漫': '317182403456872448',
    '日本动漫': '317182402894835712',
    '动漫电影': '317182404551585792',
  };
  final Map<String, MioRanking?> rankings = {};
  final Set<String> rankLoading = {}, rankFailed = {};
  final Map<String, CancelToken> _rankRequests = {};
  final Map<MioKind, int> pages = {};
  final Map<MioKind, String> genreSelections = {};
  final Map<MioKind, int> featuredOffsets = {};
  final Set<MioKind> loading = {}, failed = {}, more = {};
  final Map<MioKind, String> failureCodes = {};
  final Map<MioKind, CancelToken> _requests = {};
  CancelToken? _discovery;
  Future<void>? _bootstrap;
  bool discovering = false, discoveryFailed = false, _disposed = false;
  final Set<String> _known = {};
  int _generation = 0;

  static const _sharedFailures = {
    'UPSTREAM_UNAVAILABLE',
    'UPSTREAM_PERMISSION_DENIED',
    'UPSTREAM_NETWORK_UNREACHABLE',
    'UPSTREAM_CONNECTION_REFUSED',
    'UPSTREAM_CONNECTION_RESET',
    'UPSTREAM_DNS_ERROR',
    'SDK_RESOURCE_MISSING',
    'TIMEOUT',
    'RUNTIME_UNAVAILABLE',
    'RUNTIME_ERROR',
    'IDENTITY_ERROR',
  };

  // 只展示运行层的安全错误码，不把异常详情、凭据或响应体带入界面。
  static String _failureCode(Object error) {
    final code = error is SourceException ? error.code : 'RUNTIME_ERROR';
    return RegExp(r'^[A-Z_]{1,64}$').hasMatch(code) ? code : 'RUNTIME_ERROR';
  }

  String failureMessage(MioKind kind) {
    final code = failureCodes[kind];
    if (code == null) return '内容加载失败';
    final reason = switch (code) {
      'UPSTREAM_UNAVAILABLE' => '无法连接内容服务，请检查网络',
      'UPSTREAM_PERMISSION_DENIED' => '内容连接被系统拒绝，请检查应用联网权限',
      'UPSTREAM_NETWORK_UNREACHABLE' => '当前网络无法到达内容服务',
      'UPSTREAM_CONNECTION_REFUSED' => '内容服务拒绝连接，请稍后重试',
      'UPSTREAM_CONNECTION_RESET' => '内容服务连接中断，请稍后重试',
      'UPSTREAM_DNS_ERROR' => '内容服务地址解析失败',
      'SDK_RESOURCE_MISSING' => '内置 SDK 资源缺失，请更新应用',
      'TIMEOUT' => '内容请求超时，请稍后重试',
      'RUNTIME_UNAVAILABLE' => '内置 SDK 无法启动',
      'RUNTIME_ERROR' => '内置 SDK 请求失败',
      'IDENTITY_ERROR' => '本地设备身份读取失败',
      'DECRYPT_ERROR' => '内容响应解析失败',
      _ => '内容加载失败',
    };
    return '$reason（$code）';
  }

  static const genreOrder = [
    '动作',
    '喜剧',
    '爱情',
    '科幻',
    '悬疑',
    '犯罪',
    '剧情',
    '恐怖',
    '惊悚',
    '冒险',
    '战争',
    '奇幻',
    '动画',
    '纪录片',
    '家庭',
    '古装',
    '武侠',
    '真人秀',
    '音乐',
    '舞蹈',
    '脱口秀',
    '竞技',
    '访谈',
  ];

  List<String> genres(MioKind kind) {
    final available = {
      for (final video in items[kind] ?? <MioVideo>[]) ...video.genres,
    };
    return genreOrder.where(available.contains).toList();
  }

  void selectGenre(MioKind kind, String genre) {
    if (_disposed || (genre.isNotEmpty && !genres(kind).contains(genre))) {
      return;
    }
    genreSelections[kind] = genre;
    featuredOffsets[kind] = 0;
    notifyListeners();
  }

  List<MioVideo> filtered(MioKind kind) {
    final genre = genreSelections[kind] ?? '';
    return (items[kind] ?? <MioVideo>[])
        .where((video) => genre.isEmpty || video.genres.contains(genre))
        .toList();
  }

  List<MioVideo> rated(MioKind kind) =>
      filtered(
          kind,
        ).where((video) => video.score.isFinite && video.score > 0).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  MioVideo? featured(MioKind kind) {
    final pool = filtered(kind);
    if (pool.isEmpty) return null;
    // 优先来源明确推荐项；其后用原始评分筛选，不能宣称为七天热度。
    pool.sort((a, b) {
      final preference = (b.recommended ? 1 : 0).compareTo(
        a.recommended ? 1 : 0,
      );
      return preference != 0
          ? preference
          : (b.score.isFinite ? b.score : 0).compareTo(
              a.score.isFinite ? a.score : 0,
            );
    });
    return pool[(featuredOffsets[kind] ?? 0) % pool.length];
  }

  void shuffleFeatured(MioKind kind) {
    if (_disposed) return;
    featuredOffsets[kind] = (featuredOffsets[kind] ?? 0) + 1;
    notifyListeners();
  }

  Future<void> bootstrap({bool force = false}) {
    if (_bootstrap != null) return _bootstrap!;
    if (!force && categoryIds.isNotEmpty) return Future.value();
    return _bootstrap = _discover().whenComplete(() => _bootstrap = null);
  }

  void _ingest(Iterable<MioVideo> videos) {
    for (final video in videos) {
      if (video.categoryId.isNotEmpty && video.categoryName.isNotEmpty) {
        namedCategoryIds[video.categoryName] = video.categoryId;
      }
      final kind = video.kind;
      if (!kinds.contains(kind)) continue;
      if (video.categoryId.isNotEmpty) {
        final preferred = switch (kind) {
          MioKind.movie => '电影大全',
          MioKind.series => '剧集大全',
          MioKind.variety => '综艺节目',
          _ => '漫剧',
        };
        if (!categoryIds.containsKey(kind) || video.categoryName == preferred) {
          categoryIds[kind] = video.categoryId;
        }
      }
      if (_known.add(video.identity)) {
        items.putIfAbsent(kind, () => []).add(video);
      }
    }
  }

  Future<void> _discover() async {
    if (_disposed) return;
    discovering = true;
    discoveryFailed = false;
    final generation = ++_generation;
    for (final request in _requests.values) {
      request.cancel();
    }
    _requests.clear();
    loading.clear();
    failed.clear();
    failureCodes.clear();
    _discovery?.cancel();
    final cancel = _discovery = CancelToken();
    notifyListeners();
    var successes = 0;
    String? catalogFailure, configFailure;
    Future<void> catalog() async {
      try {
        final result = await service.catalog(size: 50, cancel: cancel);
        if (_disposed || generation != _generation) return;
        _ingest(result.items);
        successes++;
        notifyListeners();
      } catch (error) {
        catalogFailure = _failureCode(error);
        /* 目录和热搜独立失败，保留已到达的分类证据。 */
      }
    }

    Future<void> config() async {
      try {
        final data = await service.call('searchConfig', {}, cancel: cancel);
        final hot = data['hotSearchData'];
        final entries = hot is Map && hot['items'] is List
            ? hot['items'] as List
            : const [];
        final videos = <MioVideo>[];
        for (final entry in entries) {
          if (entry is! Map || entry['video'] is! Map) continue;
          try {
            videos.add(
              MioVideo.fromJson(
                Map<String, dynamic>.from(entry['video'] as Map),
              ),
            );
          } on FormatException {
            continue;
          }
        }
        if (_disposed || generation != _generation) return;
        _ingest(videos);
        successes++;
        notifyListeners();
      } catch (error) {
        configFailure = _failureCode(error);
        /* 不让一个慢接口成为其他栏目显示的前置条件。 */
      }
    }

    await Future.wait([catalog(), config()]);
    if (_disposed || generation != _generation) return;
    // 两个独立入口同时遇到相同的运行/网络错误时，分类搜索也无法恢复连接。
    // 空目录或单接口失败仍继续发现分类，避免误伤原有的搜索兜底。
    if (successes == 0 &&
        catalogFailure == configFailure &&
        _sharedFailures.contains(catalogFailure)) {
      failed.addAll(kinds);
      for (final kind in kinds) {
        failureCodes[kind] = catalogFailure!;
      }
      discovering = false;
      discoveryFailed = true;
      notifyListeners();
      return;
    }
    for (final kind in List.of(categoryIds.keys)) {
      unawaited(load(kind, reset: true));
    }
    // 默认首页和热搜可能只有动漫。只查缺失类的首屏，分类仍由真实元数据决定。
    // 两个发现任务各自等待其目录加载，避免挤满 Python 的四个运行名额。
    final pending = kinds
        .where((kind) => !categoryIds.containsKey(kind))
        .toList();
    var cursor = 0;
    Future<void> discoverMissing() async {
      while (cursor < pending.length &&
          !_disposed &&
          generation == _generation) {
        final kind = pending[cursor++];
        try {
          final result = await service.search(kind.label, cancel: cancel);
          if (_disposed || generation != _generation) return;
          _ingest(result.items.where((video) => video.kind == kind));
          successes++;
          notifyListeners();
          if (categoryIds.containsKey(kind)) await load(kind, reset: true);
        } catch (error) {
          if (!_disposed && generation == _generation && !cancel.isCancelled) {
            failed.add(kind);
            failureCodes[kind] = _failureCode(error);
            notifyListeners();
          }
        }
      }
    }

    await Future.wait([discoverMissing(), discoverMissing()]);
    if (_disposed || generation != _generation) return;
    discovering = false;
    discoveryFailed = successes == 0;
    notifyListeners();
  }

  Future<void> load(MioKind kind, {bool reset = false}) async {
    if (_disposed || loading.contains(kind)) return;
    final id = categoryIds[kind];
    if (id == null) {
      await bootstrap(force: true);
      return;
    }
    if (!reset && !more.contains(kind)) return;
    final page = reset ? 1 : (pages[kind] ?? 0) + 1;
    final cancel = _requests[kind] = CancelToken();
    final generation = _generation;
    loading.add(kind);
    failed.remove(kind);
    failureCodes.remove(kind);
    notifyListeners();
    try {
      final result = await service.catalog(
        categoryId: id,
        page: page,
        cancel: cancel,
      );
      if (_disposed || generation != _generation || cancel.isCancelled) return;
      final previous = reset
          ? <String, MioVideo>{}
          : {for (final v in items[kind] ?? <MioVideo>[]) v.identity: v};
      for (final v in result.items.where(
        (v) => v.kind == kind && v.categoryId == id,
      )) {
        previous[v.identity] = v;
      }
      items[kind] = previous.values.toList();
      pages[kind] = page;
      if (result.hasMore) {
        more.add(kind);
      } else {
        more.remove(kind);
      }
    } catch (error) {
      if (!_disposed && generation == _generation && !cancel.isCancelled) {
        failed.add(kind);
        failureCodes[kind] = _failureCode(error);
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading.remove(kind);
        _requests.remove(kind);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _discovery?.cancel();
    for (final cancel in _requests.values) {
      cancel.cancel();
    }
    for (final cancel in _rankRequests.values) {
      cancel.cancel();
    }
    super.dispose();
  }

  Future<void> loadRanking(String id, {bool refresh = false}) async {
    if (_disposed ||
        (!refresh &&
            (rankLoading.contains(id) ||
                rankings.containsKey(id) ||
                rankFailed.contains(id)))) {
      return;
    }
    _rankRequests[id]?.cancel();
    final cancel = _rankRequests[id] = CancelToken();
    rankLoading.add(id);
    rankFailed.remove(id);
    notifyListeners();
    try {
      final result = await service.hotRank(id, cancel: cancel);
      if (_disposed || cancel.isCancelled || _rankRequests[id] != cancel) {
        return;
      }
      rankings[id] = result;
    } catch (_) {
      if (!_disposed && !cancel.isCancelled && _rankRequests[id] == cancel) {
        rankFailed.add(id);
      }
    } finally {
      if (!_disposed && _rankRequests[id] == cancel) {
        _rankRequests.remove(id);
        rankLoading.remove(id);
        notifyListeners();
      }
    }
  }
}
