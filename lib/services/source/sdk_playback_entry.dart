import 'content_search.dart';
import 'sdk_playback_models.dart';
import 'sdk_playback_provider.dart';

class SdkSourceBinding {
  const SdkSourceBinding({
    required this.provider,
    required this.contentId,
    this.seed,
  });
  final SdkPlaybackProvider provider;
  final String contentId;
  final SdkVideo? seed;
}

class SdkPlaybackEntry {
  SdkPlaybackEntry({
    required this.title,
    required Iterable<SdkSourceBinding> sources,
    this.cover = '',
    this.autoPlay = true,
  }) : sources = List.unmodifiable(sources) {
    if (this.sources.isEmpty) {
      throw ArgumentError('SDK playback requires a source');
    }
  }
  final String title, cover;
  final List<SdkSourceBinding> sources;
  final bool autoPlay;

  static SdkPlaybackEntry? fromWork(
    ContentWork work,
    Iterable<ContentSearchProvider> providers,
  ) {
    final sources = <SdkSourceBinding>[];
    for (final provider in providers) {
      final sdk = provider.sdkPlayback;
      if (sdk == null || sdk.id != provider.id || !provider.canPlay) continue;
      final hits = work.hits
          .where((hit) => hit.providerId == provider.id)
          .toList();
      // 同一 SDK 的多个不同身份不能靠“取第一条”猜出影片版本。
      if (hits.length != 1) continue;
      sources.add(
        SdkSourceBinding(provider: sdk, contentId: hits.single.contentId),
      );
    }
    return sources.isEmpty
        ? null
        : SdkPlaybackEntry(
            title: work.title,
            cover: work.cover,
            sources: sources,
          );
  }
}
