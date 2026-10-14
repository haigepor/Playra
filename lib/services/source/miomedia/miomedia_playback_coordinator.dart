import '../sdk_playback_coordinator.dart';
import 'miomedia_service.dart';
import 'miomedia_playback_provider.dart';

typedef MioPlaybackOutcome = SdkPlaybackOutcome;

/// Compatibility entry; new SDK playback uses the shared automatic session.
class MioPlaybackCoordinator extends SdkPlaybackCoordinator {
  MioPlaybackCoordinator(
    String videoId,
    MioMediaService service, {
    bool singleMovie = false,
  }) : super(
         videoId,
         MioSdkPlaybackProvider(service),
         singleMovie: singleMovie,
       );

  static MioEpisode? match(
    MioEpisode original,
    List<MioEpisode> candidates, {
    bool singleMovie = false,
  }) =>
      SdkPlaybackCoordinator.match(
            original,
            candidates,
            singleMovie: singleMovie,
          )
          as MioEpisode?;
}
