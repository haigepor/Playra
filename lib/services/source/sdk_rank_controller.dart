import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'lumina/lumina_service.dart';
import 'lumina/lumina_playback_provider.dart';
import 'miomedia/miomedia_service.dart';
import 'miomedia/miomedia_playback_provider.dart';
import 'sdk_playback_entry.dart';
import 'sdk_playback_models.dart';
import 'source_models.dart' show SourceException;

/// position 仅为混排展示序号；sourcePosition 始终保留 SDK 的原始顺序。
class SdkRankEntry {
  const SdkRankEntry({
    required this.position,
    required this.sourcePosition,
    required this.binding,
    this.sourceCategoryId,
  });
  final int position, sourcePosition;
  final SdkSourceBinding binding;
  final String? sourceCategoryId;
  String get providerId => binding.provider.id;
  String get providerName =>
      providerId == 'miomedia' ? 'MioMedia' : binding.provider.name;
  SdkVideo get video => binding.seed!;
  String get identity => '$providerId:${binding.contentId}';
  // 两个 SDK 均未公开可验证的七天窗口或同口径热度，不能生成跨源热度排名。
  Object? get window => null;
  SdkPlaybackEntry get playbackEntry => SdkPlaybackEntry(
    title: video.title,
    cover: video.cover,
    sources: [binding],
  );
  SdkRankEntry at(int position) => SdkRankEntry(
    position: position,
    sourcePosition: sourcePosition,
    binding: binding,
    sourceCategoryId: sourceCategoryId,
  );
}

/// 两端独立请求、取消和保留缓存；固定交替来源顺序不受响应先后影响。
class SdkRankController extends ChangeNotifier {
  SdkRankController({this.lumina, this.mio});
  final LuminaService? lumina;
  final MioMediaService? mio;
  final Set<String> loading = {}, failed = {};
  final Map<String, String> errors = {};
  final Map<String, String?> _scopes = {};
  final Map<String, CancelToken> _requests = {};
  final Map<String, Future<void>> _pending = {};
  final Map<String, List<SdkRankEntry>> _items = {};
  bool _disposed = false;
  bool discoveringSources = false;
  List<String> _mioOrder = const [];
  List<String>? _mioCategoryIds;

  /// 为空的来源也占自己的位置，避免迟到结果改变已显示海报的序号和横坐标。
  List<SdkRankEntry?> get displaySlots {
    final values = _items.values.expand((items) => items).toList();
    final pools = <List<SdkRankEntry>>[
      if (lumina != null) _items['lumina'] ?? const [],
      if (mio != null && _mioCategoryIds == null)
        [for (final key in _mioOrder) ...?_items[key]],
      if (mio != null && _mioCategoryIds != null) ...[
        values
            .where(
              (entry) =>
                  entry.providerId == 'miomedia' &&
                  entry.video is MioVideo &&
                  (entry.video as MioVideo).kind == MioKind.movie,
            )
            .toList(),
        values
            .where(
              (entry) =>
                  entry.providerId == 'miomedia' &&
                  entry.video is MioVideo &&
                  (entry.video as MioVideo).kind == MioKind.series,
            )
            .toList(),
      ],
    ];
    final rows = pools.fold<int>(
      1,
      (count, pool) => pool.length > count ? pool.length : count,
    );
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < pools.length; column++)
          row < pools[column].length
              ? pools[column][row].at(row * pools.length + column + 1)
              : null,
    ];
  }

  List<SdkRankEntry> get entries {
    final result = <SdkRankEntry>[];
    final pools = [
      _items['lumina'] ?? const <SdkRankEntry>[],
      for (final key in _mioOrder) _items[key] ?? const <SdkRankEntry>[],
    ];
    final count = pools.fold<int>(
      0,
      (n, list) => n > list.length ? n : list.length,
    );
    final seen = <String>{};
    for (var i = 0; i < count; i++) {
      for (final values in pools) {
        if (i < values.length && seen.add(values[i].identity)) {
          result.add(values[i].at(result.length + 1));
        }
      }
    }
    return List.unmodifiable(result);
  }

  Future<void> load({
    String? luminaChannelId,
    String? mioCategoryId,
    List<String>? mioCategoryIds,
    bool refresh = false,
    bool discovering = false,
  }) async {
    if (_disposed) return;
    if (discoveringSources != discovering) {
      discoveringSources = discovering;
      notifyListeners();
    }
    bool valid(String? value) =>
        value != null && RegExp(r'^[1-9]\d{0,63}$').hasMatch(value);
    final categories = mioCategoryIds == null
        ? null
        : (mioCategoryIds.where(valid).toSet().toList()..sort());
    _mioCategoryIds = categories;
    final scopes = <String, String>{
      if (mio != null && categories == null && valid(mioCategoryId))
        'miomedia': mioCategoryId!,
      if (mio != null && categories != null)
        for (final id in categories) 'miomedia:$id': id,
    };
    _mioOrder = scopes.keys.toList();
    // 分类晚到时移除旧全站/旧分类；其迟到响应不再有权限回填混合推荐。
    for (final key
        in _scopes.keys
            .where(
              (key) => key.startsWith('miomedia') && !scopes.containsKey(key),
            )
            .toList()) {
      _load(key, null, false, (_, _) async => const []);
    }
    await Future.wait([
      _load('lumina', lumina == null ? null : luminaChannelId, refresh, (
        scope,
        cancel,
      ) async {
        final result = await lumina!.catalog(
          scope,
          size: 10,
          sort: 'weight',
          refresh: refresh,
          cancel: cancel,
        );
        final provider = LuminaPlaybackProvider(lumina!);
        return [
          for (var i = 0; i < result.items.length; i++)
            // 与首页一致排除明确零更新且未完结的占位；来源位次仍取原始索引。
            if (result.items[i].updatedTo == null ||
                result.items[i].updatedTo! > 0 ||
                result.items[i].isEnd)
              SdkRankEntry(
                position: 0,
                sourcePosition: i + 1,
                binding: SdkSourceBinding(
                  provider: provider,
                  contentId: result.items[i].id,
                  seed: result.items[i],
                ),
              ),
        ];
      }),
      for (final scope in scopes.entries)
        _load(
          scope.key,
          scope.value,
          refresh,
          (id, cancel) => _fetchMio(id, cancel, screenOnly: categories != null),
        ),
    ]);
  }

  Future<List<SdkRankEntry>> _fetchMio(
    String scope,
    CancelToken cancel, {
    required bool screenOnly,
  }) async {
    final result = await mio!.hotRank(scope, cancel: cancel);
    final provider = MioSdkPlaybackProvider(mio!);
    return [
      for (final entry in result?.entries ?? const <MioRankEntry>[])
        // 真实影视分类仍须核对每条元数据，不以片名或全站榜猜测电影/剧集。
        if (!screenOnly ||
            entry.video.categoryId == scope &&
                const {
                  MioKind.movie,
                  MioKind.series,
                }.contains(entry.video.kind))
          SdkRankEntry(
            position: 0,
            sourcePosition: entry.position,
            sourceCategoryId: scope,
            binding: SdkSourceBinding(
              provider: provider,
              contentId: entry.video.id,
              seed: entry.video,
            ),
          ),
    ];
  }

  Future<void> retry() => load(
    luminaChannelId: _scopes['lumina'],
    mioCategoryId: _scopes['miomedia'],
    mioCategoryIds: _mioCategoryIds,
    refresh: true,
  );

  Future<void> _load(
    String provider,
    String? scope,
    bool refresh,
    Future<List<SdkRankEntry>> Function(String, CancelToken) fetch,
  ) {
    if (scope == null) {
      final changed =
          _requests.containsKey(provider) ||
          _items.containsKey(provider) ||
          failed.contains(provider);
      _requests.remove(provider)?.cancel('scope unavailable');
      _pending.remove(provider);
      _items.remove(provider);
      _scopes[provider] = null;
      loading.remove(provider);
      failed.remove(provider);
      errors.remove(provider);
      if (changed) notifyListeners();
      return Future.value();
    }
    if (!refresh && _scopes[provider] == scope) {
      return _pending[provider] ?? Future.value();
    }
    if (_scopes[provider] != scope) _items.remove(provider);
    _scopes[provider] = scope;
    _requests[provider]?.cancel('superseded');
    final cancel = _requests[provider] = CancelToken();
    bool current() =>
        !_disposed && !cancel.isCancelled && _requests[provider] == cancel;
    loading.add(provider);
    failed.remove(provider);
    errors.remove(provider);
    notifyListeners();
    Future<void> run() async {
      try {
        final result = await fetch(scope, cancel);
        if (!current()) return;
        final seen = <String>{};
        // 同源重复 ID 去重；跨 SDK 同名/同 ID 不代表同一版本，不能擅自合并身份。
        _items[provider] = List.unmodifiable(
          result.where((entry) => seen.add(entry.identity)).take(10),
        );
      } catch (error) {
        if (!current()) return;
        failed.add(provider);
        final code = error is SourceException ? error.code : 'SOURCE_ERROR';
        errors[provider] = RegExp(r'^[A-Z_]{1,64}$').hasMatch(code)
            ? code
            : 'SOURCE_ERROR';
      } finally {
        if (current()) {
          loading.remove(provider);
          _requests.remove(provider);
          _pending.remove(provider);
          notifyListeners();
        }
      }
    }

    return _pending[provider] = run();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final request in _requests.values) {
      request.cancel('disposed');
    }
    _requests.clear();
    _pending.clear();
    super.dispose();
  }
}
