import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'content_search.dart';
import 'source_models.dart';

enum ContentDirectoryStatus {
  pending,
  ready,
  empty,
  failed,
  verificationRequired,
}

class ContentSourceBinding {
  ContentSourceBinding(this.hit);
  final ContentHit hit;
  ContentDirectoryStatus status = ContentDirectoryStatus.pending;
  List<ContentLine> lines = [];
  String? errorCode;
}

/// 目录验证有独立并发池，不占搜索槽位，也不提前解析/消费媒体凭证。
class ContentSourceController extends ChangeNotifier {
  ContentSourceController(
    Iterable<ContentSearchProvider> providers, {
    this.concurrency = 2,
  }) : _providers = {for (final p in providers) p.id: p} {
    if (concurrency < 1 || concurrency > 4) {
      throw ArgumentError('Invalid directory concurrency');
    }
  }
  final Map<String, ContentSearchProvider> _providers;
  final int concurrency;
  final _bindings = <String, ContentSourceBinding>{};
  final _queue = <ContentSourceBinding>[];
  final _lifetime = CancelToken();
  CancelToken? _selection;
  int _active = 0;
  bool _disposed = false;
  List<ContentSourceBinding> get bindings =>
      List.unmodifiable(_bindings.values);
  ContentSourceBinding? selected;
  ContentLine? selectedLine;
  List<ContentEpisode> episodes = [];
  bool loadingEpisodes = false;
  String? episodeError;
  ContentSearchProvider provider(ContentHit hit) => _providers[hit.providerId]!;

  void add(ContentHit hit) {
    if (_disposed ||
        _bindings.containsKey(hit.key) ||
        _providers[hit.providerId]?.canPlay != true) {
      return;
    }
    final binding = ContentSourceBinding(hit);
    _bindings[hit.key] = binding;
    _queue.add(binding);
    _pump();
    notifyListeners();
  }

  void retry(ContentSourceBinding binding) {
    if (_disposed || binding.status == ContentDirectoryStatus.pending) return;
    binding.status = ContentDirectoryStatus.pending;
    binding.errorCode = null;
    _queue.add(binding);
    _pump();
    notifyListeners();
  }

  Future<T> _budget<T>(CancelToken cancel, Future<T> Function() action) =>
      Future.any<T>([
        action(),
        cancel.whenCancel.then(
          (_) => throw const SourceException('CANCELLED', '目录请求已取消'),
        ),
      ]).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          cancel.cancel('deadline');
          throw const SourceException('TIMEOUT', '目录请求超时');
        },
      );

  CancelToken _token() {
    final token = CancelToken();
    unawaited(_lifetime.whenCancel.then((_) => token.cancel('disposed')));
    return token;
  }

  void _pump() {
    while (!_disposed && _active < concurrency && _queue.isNotEmpty) {
      final binding = _queue.removeAt(0);
      _active++;
      unawaited(_validate(binding));
    }
  }

  Future<void> _validate(ContentSourceBinding binding) async {
    final token = _token();
    try {
      final p = provider(binding.hit);
      final lines = await _budget(token, () async {
        final result = List<ContentLine>.of(await p.lines(binding.hit, token));
        // SDK 线路目录与剧集分开：只验证首条线路，其他线路按用户选择延迟读取。
        if (result.isNotEmpty && result.first.episodes.isEmpty) {
          final first = result.first;
          result[0] = ContentLine(
            first.id,
            first.name,
            await p.episodes(binding.hit, first, token),
          );
        }
        return result;
      });
      if (_disposed || token.isCancelled) return;
      binding.lines = lines;
      binding.status = lines.isEmpty
          ? ContentDirectoryStatus.empty
          : ContentDirectoryStatus.ready;
    } catch (error) {
      if (_disposed) return;
      binding.errorCode = error is SourceException
          ? error.code
          : 'SOURCE_ERROR';
      binding.status = binding.errorCode == 'CHALLENGE_REQUIRED'
          ? ContentDirectoryStatus.verificationRequired
          : ContentDirectoryStatus.failed;
    } finally {
      _active--;
      if (!_disposed) {
        notifyListeners();
        _pump();
      }
    }
  }

  Future<void> select(ContentSourceBinding binding, ContentLine line) async {
    if (_disposed || binding.status != ContentDirectoryStatus.ready) return;
    _selection?.cancel('replaced');
    final token = _selection = _token();
    selected = binding;
    selectedLine = line;
    episodes = [];
    episodeError = null;
    loadingEpisodes = true;
    notifyListeners();
    try {
      final result = line.episodes.isNotEmpty
          ? line.episodes
          : await _budget(
              token,
              () => provider(binding.hit).episodes(binding.hit, line, token),
            );
      if (!_disposed && !token.isCancelled && identical(_selection, token)) {
        episodes = result;
      }
    } catch (error) {
      if (!_disposed && !token.isCancelled) {
        episodeError = error is SourceException ? error.code : 'SOURCE_ERROR';
      }
    } finally {
      if (!_disposed && identical(_selection, token)) {
        loadingEpisodes = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lifetime.cancel('disposed');
    _selection?.cancel();
    _queue.clear();
    super.dispose();
  }
}
