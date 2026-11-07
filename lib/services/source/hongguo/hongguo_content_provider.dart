/// 红果短剧的搜索聚合提供方（ContentSearchProvider）。
/// 播放走 [HongguoPlaybackProvider]（sdkPlayback 桥）。
library;

import 'package:dio/dio.dart';

import '../content_search.dart';
import 'hongguo_client.dart';
import 'hongguo_playback_provider.dart';

class HongguoContentProvider extends ContentSearchProvider {
  HongguoContentProvider(this.client);

  final HongguoClient client;

  @override
  String get id => 'hongguo';

  @override
  String get name => '红果短剧';

  @override
  int get priority => 60;

  @override
  bool get canPlay => true;

  @override
  Set<ContentGroup> get groups => {ContentGroup.series};

  @override
  late final HongguoPlaybackProvider sdkPlayback = HongguoPlaybackProvider(
    client,
  );

  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async {
    // 搜索接口按 offset 翻页：offset = (page-1) * pageSize。
    const pageSize = 20;
    final offset = page > 1 ? (page - 1) * pageSize : 0;
    final result = await client.search(
      query.keyword,
      cursor: offset > 0 ? '$offset' : '',
      pageSize: pageSize,
      cancel: cancel,
    );
    return ContentSearchPage(
      [
        for (final series in result.items)
          ContentHit(
            providerId: id,
            contentId: series.id,
            title: series.title,
            cover: series.coverUrl,
            group: ContentGroup.series,
          ),
      ],
      hasMore: result.hasMore,
    );
  }

  @override
  void dispose() => client.dispose();
}
