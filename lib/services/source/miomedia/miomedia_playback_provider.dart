import 'package:dio/dio.dart';
import '../sdk_playback_models.dart';
import '../sdk_playback_provider.dart';
import 'miomedia_service.dart';

class MioSdkPlaybackProvider extends SdkPlaybackProvider {
  MioSdkPlaybackProvider(this.service);
  final MioMediaService service;
  @override
  String get id => 'miomedia';
  @override
  String get name => 'miomedia';
  @override
  bool get supportsQualities => true;
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) =>
      service.detail(id, cancel: cancel);
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) => service.episodes(id, code, cancel: cancel);
  @override
  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) => service.qualities(id, code, episode, cancel: cancel);
  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) => service.play(id, code, episode, quality: quality, cancel: cancel);
}
