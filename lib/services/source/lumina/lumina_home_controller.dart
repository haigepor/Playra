import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../source_models.dart' show SourceException;
import 'lumina_service.dart';

/// 首页只消费 SDK 已公开的频道和分页，不用 Bangumi 或计划总集数拼出来源目录。
class LuminaHomeController extends ChangeNotifier {
  LuminaHomeController(this.service);
  // 首页与后续页固定同一窗口，避免缩小首屏后翻页跳过中间作品。
  static const pageSize = 12;
  final LuminaService service;
  List<LuminaChannel> channels = const [];
  List<LuminaVideo> items = const [];
  List<LuminaBanner> banners = const [];
  final Map<String, List<LuminaVideo>> channelItems = {};
  final _catalogRequests = <String, CancelToken>{};
  final _channelPages = <String, int>{};
  final _channelMore = <String, bool>{};
  final _pageFailures = <String>{};
  int _warmGeneration = 0, _featuredBatch = 0;
  String? channelId, errorCode;
  bool loading = false, hasMore = false, _disposed = false;
  int _page = 0, _generation = 0;
  CancelToken? _request, _bannersRequest;
  bool get useFallback => !loading && items.isEmpty && errorCode != null;
  List<LuminaChannel> browseChannels([String bucket = 'all']) => channels
      .where(
        (channel) => switch (bucket) {
          final value when value.startsWith('channel:') =>
            channel.id == value.substring('channel:'.length),
          'japanese' =>
            channel.name.contains('日本') || channel.name.contains('日漫'),
          'chinese' => ['国产', '國產', '国漫', '國漫'].any(channel.name.contains),
          'movies' => ['电影', '電影', '剧场', '劇場'].any(channel.name.contains),
          'season' => channel.name.contains('新番'),
          _ => true,
        },
      )
      .toList();
  List<LuminaVideo> browseItems([String bucket = 'all']) {
    final selected = browseChannels(bucket);
    final lists = [
      for (final channel in selected)
        channelItems[channel.id] ??
            (channel.id == channelId ? items : <LuminaVideo>[]),
    ];
    final result = <LuminaVideo>[];
    final seen = <String>{};
    // 频道与栏内条目均沿用来源顺序，不按索引跨频道交错。
    for (final list in lists) {
      for (final video in list) {
        if ((video.updatedTo == null || video.updatedTo! > 0 || video.isEnd) &&
            seen.add(video.id)) {
          result.add(video);
        }
      }
    }
    return result;
  }

  List<LuminaVideo> featuredItems(List<LuminaVideo> pool) => pool.isEmpty
      ? const []
      : List.generate(
          pool.length < 4 ? pool.length : 4,
          (index) => pool[(_featuredBatch * 4 + index) % pool.length],
        );
  void shuffleFeatured() {
    _featuredBatch++;
    notifyListeners();
  }

  bool hasMoreIn(String bucket) =>
      browseChannels(bucket).any((channel) => _channelMore[channel.id] == true);
  bool pageFailedIn(String bucket) => browseChannels(
    bucket,
  ).any((channel) => _pageFailures.contains(channel.id));
  bool loadingIn(String bucket) => browseChannels(bucket).any(
    (channel) =>
        _catalogRequests.containsKey(channel.id) ||
        channel.id == channelId && loading,
  );
  Future<void> loadMoreIn(String bucket) async {
    final generation = _warmGeneration;
    for (final channel in browseChannels(bucket)) {
      if (_disposed || generation != _warmGeneration) return;
      if (_channelMore[channel.id] != true ||
          _catalogRequests.containsKey(channel.id)) {
        continue;
      }
      final cancel = _catalogRequests[channel.id] = CancelToken();
      final page = (_channelPages[channel.id] ?? 1) + 1;
      _pageFailures.remove(channel.id);
      notifyListeners();
      try {
        final result = await service.catalog(
          channel.id,
          page: page,
          size: pageSize,
          cancel: cancel,
        );
        if (_disposed || cancel.isCancelled || generation != _warmGeneration) {
          return;
        }
        channelItems[channel.id] = List.unmodifiable(
          {
            for (final item in [...?channelItems[channel.id], ...result.items])
              item.id: item,
          }.values,
        );
        _channelPages[channel.id] = page;
        _channelMore[channel.id] = result.hasMore;
        if (channel.id == channelId) {
          items = channelItems[channel.id]!;
          _page = page;
          hasMore = result.hasMore;
        }
      } catch (_) {
        // 失败保留目录与页码；自动分页暂停，手动重试仍取同一页。
        if (!_disposed &&
            !cancel.isCancelled &&
            generation == _warmGeneration) {
          _pageFailures.add(channel.id);
        }
      } finally {
        if (identical(_catalogRequests[channel.id], cancel)) {
          _catalogRequests.remove(channel.id);
        }
        if (!_disposed && generation == _warmGeneration) notifyListeners();
      }
    }
  }

  Future<void> bootstrap({
    bool force = false,
    bool warmOtherChannels = true,
  }) async {
    if (_disposed || loading || !force && items.isNotEmpty) return;
    if (force) {
      service.clearCatalogCache();
      channelItems.clear();
      _pageFailures.clear();
      items = const [];
      banners = const [];
    }
    _request?.cancel();
    _warmGeneration++;
    for (final request in _catalogRequests.values) {
      request.cancel();
    }
    _catalogRequests.clear();
    final cancel = _request = CancelToken(), generation = ++_generation;
    loading = true;
    errorCode = null;
    notifyListeners();
    try {
      final result = await service.channels(cancel: cancel);
      if (!current(generation, cancel)) return;
      channels = result;
      if (result.isEmpty) {
        throw const SourceException('PLAYBACK_UNAVAILABLE', '来源未提供动漫频道');
      }
      channelId = result.any((c) => c.id == channelId)
          ? channelId
          : result.first.id;
      loading = false;
      await load(refresh: true);
      if (!_disposed && warmOtherChannels) unawaited(warmChannels());
    } catch (error) {
      if (!current(generation, cancel)) return;
      errorCode = error is SourceException ? error.code : 'SOURCE_ERROR';
      loading = false;
      notifyListeners();
    }
  }

  bool current(int generation, CancelToken cancel) =>
      !_disposed && generation == _generation && !cancel.isCancelled;

  Future<void> selectChannel(String id) async {
    if (_disposed || channelId == id || !channels.any((c) => c.id == id)) {
      return;
    }
    channelId = id;
    await load(refresh: true);
  }

  Future<void> load({bool refresh = false}) async {
    final id = channelId;
    if (_disposed || id == null || !refresh && (loading || !hasMore)) return;
    _request?.cancel();
    final cancel = _request = CancelToken(), generation = ++_generation;
    final page = refresh ? 1 : _page + 1;
    loading = true;
    errorCode = null;
    if (refresh) {
      _pageFailures.remove(id);
      items = const [];
      banners = const [];
      hasMore = false;
      _bannersRequest?.cancel();
      final bannerCancel = _bannersRequest = CancelToken();
      unawaited(
        service
            .banners(id, cancel: bannerCancel)
            .then((value) async {
              if (current(generation, cancel) && !bannerCancel.isCancelled) {
                banners = value;
                notifyListeners();
                await _fillBannerCovers(value, generation, bannerCancel);
              }
            })
            .catchError((Object _) {
              /* 轮播失败不阻塞目录，也不伪造推荐图。 */
            }),
      );
    }
    notifyListeners();
    try {
      final result = await service.catalog(
        id,
        page: page,
        size: pageSize,
        cancel: cancel,
      );
      if (!current(generation, cancel)) return;
      items = List.unmodifiable(
        {
          for (final video in [...items, ...result.items]) video.id: video,
        }.values,
      );
      channelItems[id] = items;
      _channelPages[id] = page;
      _channelMore[id] = result.hasMore;
      _page = page;
      hasMore = result.hasMore;
      if (items.isEmpty) errorCode = 'EMPTY_SOURCE';
    } catch (error) {
      if (!current(generation, cancel)) return;
      errorCode = error is SourceException ? error.code : 'SOURCE_ERROR';
    } finally {
      if (current(generation, cancel)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// banner 接口只返回 id/videoId/title/cover，部分条目 cover 为空；
  /// 用作品详情补图，最多补 5 个，失败时保留占位。
  Future<void> _fillBannerCovers(
    List<LuminaBanner> source,
    int generation,
    CancelToken cancel,
  ) async {
    final missing = source.where((banner) => banner.cover.isEmpty).take(5);
    for (final banner in missing) {
      try {
        final video = await service.detail(banner.videoId, cancel: cancel);
        if (!current(generation, cancel) || video.cover.isEmpty) continue;
        final index = banners.indexWhere(
          (item) => item.videoId == banner.videoId,
        );
        if (index < 0) continue;
        banners = [...banners]..[index] = banner.withCover(video.cover);
        notifyListeners();
      } catch (_) {
        // 详情补图失败时保留占位，不影响其他轮播内容。
      }
    }
  }

  Future<void> _warmOtherChannels(int generation) async {
    final pending = channels
        .where((channel) => channel.id != channelId)
        .toList();
    var cursor = 0;
    Future<void> worker() async {
      while (!_disposed &&
          generation == _warmGeneration &&
          cursor < pending.length) {
        final channel = pending[cursor++];
        final cancel = _catalogRequests[channel.id] = CancelToken();
        try {
          final page = await runZoned(
            () => service.catalog(channel.id, size: pageSize, cancel: cancel),
            zoneValues: {#luminaBackground: true},
          );
          if (_disposed ||
              cancel.isCancelled ||
              generation != _warmGeneration) {
            return;
          }
          channelItems[channel.id] = page.items;
          _channelPages[channel.id] = 1;
          _channelMore[channel.id] = page.hasMore;
        } catch (error) {
          // 调度器为前台让路不等于频道失效；下一轮重新等待空闲再取本频道。
          if (error is SourceException &&
              error.code == 'CANCELLED' &&
              !cancel.isCancelled) {
            cursor--;
          }
          /* 单频道失败继续使用已加载内容和原有资料栏目。 */
        } finally {
          if (identical(_catalogRequests[channel.id], cancel)) {
            _catalogRequests.remove(channel.id);
          }
          if (!_disposed && generation == _warmGeneration) notifyListeners();
        }
      }
    }

    // 预热经全局空闲调度；播放/详情进入时取消尚未执行的后台解密。
    await worker();
  }

  Future<void> warmChannels() => _warmOtherChannels(_warmGeneration);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _request?.cancel();
    _bannersRequest?.cancel();
    _warmGeneration++;
    for (final request in _catalogRequests.values) {
      request.cancel();
    }
    super.dispose();
  }
}
