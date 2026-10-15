import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'source_candidates.dart';

/// 页面级目录会话：弹层反复打开复用目录，不缓存有时效的媒体 URL。
class AnimeSourceSession extends ChangeNotifier {
  AnimeSourceSession(BangumiItem work, {SourceCandidates? candidates})
    : _work = work,
      candidates = candidates ?? SourceCandidates.shared;
  BangumiItem _work;
  BangumiItem get work => _work;
  final SourceCandidates candidates;
  final Map<String, List<PlaybackCandidate>> entries = {};
  final Map<String, String> status = {};
  final Set<String> loading = {};
  final Map<String, RuleCancelToken> _requests = {};
  final Map<String, Plugin> _plugins = {};
  final Set<String> _confirmed = {};
  bool _disposed = false;

  /// 详情资料会替换轻量入口对象；名称证据变化后重查，人工确认保持优先。
  void updateWork(BangumiItem value) {
    if (_disposed) return;
    if (value.id != work.id || value.type != work.type) {
      throw ArgumentError('source session identity cannot change');
    }
    final previous = candidates.titles(work).map(normalizeWorkTitle).toSet();
    final next = candidates.titles(value).map(normalizeWorkTitle).toSet();
    _work = value;
    if (setEquals(previous, next)) return;
    for (final id
        in _plugins.keys.where((id) => !_confirmed.contains(id)).toList()) {
      _requests.remove(id)?.cancel('metadata updated');
      loading.remove(id);
      entries.remove(id);
      status.remove(id);
      unawaited(prepare(_plugins[id]!));
    }
    notifyListeners();
  }

  Future<void> prepare(Plugin plugin, {bool retry = false}) async {
    final id = plugin.providerId;
    _plugins[id] = plugin;
    if (_disposed || loading.contains(id) || !retry && status.containsKey(id))
      return;
    if (retry) candidates.invalidate(work, plugin);
    final cached = candidates.cached(work, [plugin]);
    if (!retry && cached.isNotEmpty) {
      entries[id] = cached;
      status[id] = cached.length == 1 ? 'ready' : '作品存在歧义，请高级选源确认';
      notifyListeners();
      return;
    }
    final cancel = RuleCancelToken();
    _requests[id] = cancel;
    loading.add(id);
    notifyListeners();
    try {
      final currentWork = work;
      final results = await candidates.searchMatches(
        currentWork,
        plugin,
        cancelToken: cancel,
      );
      final found = await candidates.prepare(
        currentWork,
        plugin,
        results,
        cancelToken: cancel,
      );
      if (_disposed || cancel.isCancelled) return;
      entries[id] = found;
      status[id] = found.isEmpty
          ? '未匹配到同作品，请高级选源确认'
          : found.length == 1
          ? 'ready'
          : '作品存在歧义，请高级选源确认';
    } catch (_) {
      if (!_disposed && !cancel.isCancelled) status[id] = '目录获取失败，点击重试';
    } finally {
      if (!_disposed && identical(_requests[id], cancel)) {
        loading.remove(id);
        _requests.remove(id);
        notifyListeners();
      }
    }
  }

  void seed(PlaybackCandidate candidate) {
    if (_disposed) return;
    _confirmed.add(candidate.plugin.providerId);
    // 用户确认的作品优先于较早的自动目录请求，迟到响应不能覆盖这次确认。
    _requests
        .remove(candidate.plugin.providerId)
        ?.cancel('confirmed selection');
    loading.remove(candidate.plugin.providerId);
    entries[candidate.plugin.providerId] = [candidate];
    status[candidate.plugin.providerId] = 'ready';
  }

  @override
  void dispose() {
    _disposed = true;
    for (final request in _requests.values) {
      request.cancel('page disposed');
    }
    super.dispose();
  }
}
