/// 红果首页频道控制器：热榜（shortRank）+ 推荐流（discover/cell/change）。
/// 与 WhiskletHomeController 平行；数据面只含本源条目。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hongguo_client.dart';
import 'hongguo_env.dart';
import 'hongguo_models.dart';

void _logFail(String stage, Object error) {
  debugPrint('HONGGUO $stage failed: $error');
}

class HongguoHomeController extends ChangeNotifier {
  HongguoHomeController({HongguoClient? client})
    : client = client ?? HongguoEnv.shared;

  final HongguoClient client;

  /// 热榜行（shortRank 全部内容的第一页）。
  List<HongguoSeriesSummary> rank = const [];
  bool rankLoading = false;
  bool rankFailed = false;

  /// 推荐流（discover 第一屏 + cell/change 续页）。
  List<HongguoSeriesSummary> discover = const [];
  bool discoverLoading = false;
  bool discoverFailed = false;
  bool discoverHasMore = false;
  HongguoFeedContinuation? _discoverNext;

  /// 频道主列表：热榜在前、推荐流去重续接。
  List<HongguoSeriesSummary> get feed {
    final seen = <String>{};
    final result = <HongguoSeriesSummary>[];
    for (final item in [...rank, ...discover]) {
      if (item.id.isEmpty || item.title.isEmpty) continue;
      if (!seen.add(item.id)) continue;
      result.add(item);
    }
    return result;
  }

  bool get loading => rankLoading || discoverLoading;
  bool get failed => rankFailed && discoverFailed;
  bool _disposed = false;

  Future<void> load({bool refresh = false}) async {
    await Future.wait([
      loadRank(refresh: refresh),
      loadDiscover(refresh: refresh),
    ]);
  }

  Future<void> loadRank({bool refresh = false}) async {
    if (_disposed || rankLoading) return;
    if (!refresh && rank.isNotEmpty) return;
    rankLoading = true;
    rankFailed = false;
    _notify();
    try {
      final ranking = await client.shortRank();
      final items = <HongguoSeriesSummary>[
        for (final row in ranking.items)
          if (row.seriesId.isNotEmpty)
            HongguoSeriesSummary(
              id: row.seriesId,
              title: row.title,
              coverUrl: row.coverUrl,
              episodeCount: row.episodeCount,
            ),
      ];
      // 榜单为空不判失败：上游可能只返回了演员榜。
      rank = items;
    } on HongguoClientError catch (error) {
      _logFail('shortRank', error);
      rankFailed = true;
    } catch (error) {
      _logFail('shortRank', error);
      rankFailed = true;
    } finally {
      rankLoading = false;
      _notify();
    }
  }

  Future<void> loadDiscover({bool refresh = false}) async {
    if (_disposed || discoverLoading) return;
    if (!refresh && discover.isNotEmpty) return;
    discoverLoading = true;
    discoverFailed = false;
    if (refresh) {
      discover = const [];
      _discoverNext = null;
      discoverHasMore = false;
    }
    _notify();
    try {
      final page = await client.discover(next: refresh ? null : _discoverNext);
      discover = [
        for (final item in page.page.items)
          if (item.coverUrl.isNotEmpty) item,
      ];
      _discoverNext = page.next;
      discoverHasMore = page.next != null;
      if (discover.isEmpty && page.next != null) {
        // 首屏嵌在嵌套 cell 里时补一页 cell/change。
        final second = await client.discover(next: page.next);
        discover = [
          for (final item in second.page.items)
            if (item.coverUrl.isNotEmpty) item,
        ];
        _discoverNext = second.next;
        discoverHasMore = second.next != null;
      }
    } on HongguoClientError catch (error) {
      _logFail('discover', error);
      discoverFailed = true;
    } catch (error) {
      _logFail('discover', error);
      discoverFailed = true;
    } finally {
      discoverLoading = false;
      _notify();
    }
  }

  Future<void> loadMoreDiscover() async {
    if (_disposed || discoverLoading || !discoverHasMore) return;
    discoverLoading = true;
    _notify();
    try {
      final next = _discoverNext;
      if (next == null) return;
      final page = await client.discover(next: next);
      final seen = discover.map((item) => item.id).toSet();
      final fresh = <HongguoSeriesSummary>[
        for (final item in page.page.items)
          if (item.coverUrl.isNotEmpty && seen.add(item.id)) item,
      ];
      discover = [...discover, ...fresh];
      _discoverNext = page.next;
      discoverHasMore = page.next != null;
    } on HongguoClientError catch (_) {
      discoverHasMore = false;
    } catch (_) {
      discoverHasMore = false;
    } finally {
      discoverLoading = false;
      _notify();
    }
  }

  void retry() {
    _notify();
    unawaited(load(refresh: true));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
