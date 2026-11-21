import 'package:kazumi/playback/video_fullscreen_controller.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:mobx/mobx.dart';

/// 一条可播放线路。空壳阶段只保留播放器需要的身份字段，不绑定任何内容源。
class PlaybackRoad {
  PlaybackRoad({required this.name, required this.episodes});

  final String name;
  final List<PlaybackEpisode> episodes;

  List<PlaybackEpisode> get data => episodes;
  List<String> get identifier => episodes.map((e) => e.displayTitle).toList();
}

class PlaybackEpisode {
  const PlaybackEpisode({
    required this.title,
    required this.url,
    this.headers = const {},
    this.referer = '',
  });

  final String title;
  final String url;
  final Map<String, String> headers;
  final String referer;

  String get displayTitle => title;
}

class PlaybackEpisodeSelection {
  const PlaybackEpisodeSelection({required this.episode, required this.road});

  /// 1-based episode number; 0 means "not selected".
  final int episode;
  final int road;

  @override
  bool operator ==(Object other) =>
      other is PlaybackEpisodeSelection &&
      other.episode == episode &&
      other.road == road;

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() => 'PlaybackEpisodeSelection(episode: $episode, road: $road)';
}

class PlaybackResolvedEpisode {
  const PlaybackResolvedEpisode({
    required this.listIndex,
    required this.displayTitle,
    required this.episode,
  });

  final int listIndex;
  final String displayTitle;
  final PlaybackEpisode episode;
}

/// 播放器页面的最小会话状态。
///
/// 替代旧 `VideoPageController` 的播放器子集：只提供标题、线路、选集与全屏，
/// 不包含 Bangumi、弹幕、历史、下载或任何来源协议。
class PlaybackSession {
  PlaybackSession({
    required String title,
    required List<PlaybackRoad> roads,
    int episode = 1,
    int road = 0,
    String sourceName = '',
    String mediaId = 'local',
    String artworkUrl = '',
  }) : fullscreen = VideoFullscreenController(
         applyFullscreen: DisplayModeService.applyVideoFullscreen,
       ) {
    _title.value = title;
    _roads.value = roads;
    _sourceName.value = sourceName;
    _mediaId.value = mediaId;
    _artwork.value = artworkUrl;
    final initial = _clampSelection(episode, road);
    _selected.value = initial;
    _playing.value = initial;
  }

  final VideoFullscreenController fullscreen;

  final Observable<String> _title = Observable('');
  final Observable<List<PlaybackRoad>> _roads = Observable(const []);
  final Observable<PlaybackEpisodeSelection> _selected = Observable(
    const PlaybackEpisodeSelection(episode: 1, road: 0),
  );
  final Observable<PlaybackEpisodeSelection> _playing = Observable(
    const PlaybackEpisodeSelection(episode: 1, road: 0),
  );
  final Observable<bool> _loading = Observable(false);
  final Observable<bool> _isPip = Observable(false);
  final Observable<String> _sourceName = Observable('');
  final Observable<String> _mediaId = Observable('local');
  final Observable<String> _artwork = Observable('');

  String get title => _title.value;
  set title(String value) => _title.value = value;

  List<PlaybackRoad> get roadList => _roads.value;

  PlaybackEpisodeSelection get selectedEpisode => _selected.value;
  PlaybackEpisodeSelection get playbackEpisode => _playing.value;

  bool get loading => _loading.value;
  set loading(bool value) => _loading.value = value;

  bool get isPip => _isPip.value;
  set isPip(bool value) => _isPip.value = value;

  bool get isFullscreen => fullscreen.isFullscreen;

  String get playbackWorkTitle => _title.value;
  String get playbackSourceName => _sourceName.value;
  String get playbackMediaId => _mediaId.value;
  String get playbackArtwork => _artwork.value;

  PlaybackEpisode? get currentEpisode => resolveEpisode(_playing.value)?.episode;

  String get src => currentEpisode?.url ?? '';

  PlaybackResolvedEpisode? resolveEpisode(PlaybackEpisodeSelection selection) {
    final roads = _roads.value;
    if (selection.road < 0 || selection.road >= roads.length) return null;
    final episodes = roads[selection.road].data;
    if (selection.episode <= 0 || selection.episode > episodes.length) {
      return null;
    }
    final episode = episodes[selection.episode - 1];
    return PlaybackResolvedEpisode(
      listIndex: selection.episode,
      displayTitle: episode.displayTitle,
      episode: episode,
    );
  }

  /// 用户选择一集；真正起播由页面确认后调用 [markPlaying]。
  PlaybackEpisodeSelection selectEpisode(int episode, {int? road}) {
    final next = _clampSelection(episode, road ?? _selected.value.road);
    _selected.value = next;
    return next;
  }

  void markPlaying(int episode, {int? road}) {
    final next = _clampSelection(episode, road ?? _playing.value.road);
    _playing.value = next;
    _selected.value = next;
  }

  PlaybackEpisodeSelection _clampSelection(int episode, int road) {
    final roads = _roads.value;
    if (roads.isEmpty) {
      return const PlaybackEpisodeSelection(episode: 0, road: 0);
    }
    final safeRoad = road.clamp(0, roads.length - 1);
    final length = roads[safeRoad].data.length;
    final safeEpisode = length == 0 ? 0 : episode.clamp(1, length);
    return PlaybackEpisodeSelection(episode: safeEpisode, road: safeRoad);
  }

  void dispose() {
    fullscreen.detach();
  }
}
