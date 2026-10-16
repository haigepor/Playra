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
    this.autoPlay = false,
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
    final ordered = providers.toList().asMap().entries.toList()
      ..sort((a, b) {
        final rank = b.value.priority.compareTo(a.value.priority);
        return rank == 0 ? a.key.compareTo(b.key) : rank;
      });
    // 动漫规则已确认且优先级更高时，不能因后备影视 SDK 有接口就抢走入口。
    final playable = ordered
        .map((e) => e.value)
        .where(
          (p) => p.canPlay && work.hits.any((hit) => hit.providerId == p.id),
        )
        .toList();
    if (work.primary.group == ContentGroup.anime &&
        playable.isNotEmpty &&
        playable.first.sdkPlayback == null) {
      return null;
    }
    final seen = <String>{};
    for (final item in ordered) {
      final provider = item.value;
      if (!seen.add(provider.id)) continue;
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
