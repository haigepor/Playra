import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'lumina/lumina_service.dart';
import 'lumina/lumina_playback_provider.dart';
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
  String get providerName => binding.provider.name;
  SdkVideo get video => binding.seed!;
  String get identity => '$providerId:${binding.contentId}';
  // 上游未公开可验证的七天窗口，保留原始目录顺序。
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

class SdkRankController extends ChangeNotifier {
  SdkRankController({this.lumina});
  final LuminaService? lumina;
  final Set<String> loading = {}, failed = {};
  final Map<String, String> errors = {};
  final Map<String, String?> _scopes = {};
  final Map<String, CancelToken> _requests = {};
  final Map<String, Future<void>> _pending = {};
  final Map<String, List<SdkRankEntry>> _items = {};
  bool _disposed = false, discoveringSources = false;
  List<SdkRankEntry> get entries => _items['lumina'] ?? const [];
  List<SdkRankEntry?> get displaySlots => entries;
  Future<void> load({
    String? luminaChannelId,
    bool refresh = false,
    bool discovering = false,
  }) {
    discoveringSources = discovering;
    return _load('lumina', lumina == null ? null : luminaChannelId, refresh, (
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
          SdkRankEntry(
            position: i + 1,
            sourcePosition: i + 1,
            binding: SdkSourceBinding(
              provider: provider,
              contentId: result.items[i].id,
              seed: result.items[i],
            ),
          ),
      ];
    });
  }

  Future<void> retry() =>
      load(luminaChannelId: _scopes['lumina'], refresh: true);
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
        // 同源重复 ID 去重，保留上游顺序。
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
