import 'package:kazumi/features/sources/core/media_models.dart';

/// Route argument for `/browse`.
class BrowseArgs {
  const BrowseArgs({
    required this.sourceId,
    required this.categoryId,
    required this.title,
    this.initialSort = '',
  });

  final String sourceId;
  final String categoryId;
  final String title;
  final String initialSort;
}

/// Route argument for `/play`.
class PlaybackRequest {
  const PlaybackRequest({
    required this.sourceId,
    required this.detail,
    required this.roadCode,
    required this.episode,
    this.quality,
  });

  final String sourceId;
  final MediaDetail detail;
  final String roadCode;
  final int episode;
  final String? quality;

  PlaybackRequest copyWith({
    String? roadCode,
    int? episode,
    String? quality,
  }) {
    return PlaybackRequest(
      sourceId: sourceId,
      detail: detail,
      roadCode: roadCode ?? this.roadCode,
      episode: episode ?? this.episode,
      quality: quality ?? this.quality,
    );
  }
}
