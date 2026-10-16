import 'package:dio/dio.dart';
import '../content_search.dart';
import 'lumina_service.dart';
import 'lumina_playback_provider.dart';

class LuminaContentProvider extends ContentSearchProvider {
  LuminaContentProvider(this.service);
  final LuminaService service;
  @override
  String get id => 'lumina';
  @override
  String get name => 'Lumina';
  @override
  int get priority => 100;
  @override
  bool get canPlay => true;
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  @override
  late final LuminaPlaybackProvider sdkPlayback = LuminaPlaybackProvider(
    service,
  );
  @override
  Future<ContentSearchPage> search(
    ContentQuery query,
    int page,
    CancelToken cancel,
  ) async {
    final result = await service.search(
      query.keyword,
      page: page,
      cancel: cancel,
    );
    return ContentSearchPage([
      for (final video in result.items)
        ContentHit(
          providerId: id,
          contentId: video.id,
          title: video.title,
          cover: video.cover,
          year: int.tryParse(video.year),
          region: video.area,
          group: ContentGroup.anime,
        ),
    ], hasMore: result.hasMore);
  }

  @override
  void dispose() => service.dispose();
}
