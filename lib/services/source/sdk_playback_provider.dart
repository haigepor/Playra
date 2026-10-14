import 'package:dio/dio.dart';
import 'sdk_playback_models.dart';

/// SDK 负责协议，公共会话负责选线；不要求页面识别具体 SDK 类型。
abstract class SdkPlaybackProvider {
  String get id;
  String get name;
  bool get supportsQualities => false;
  Future<SdkVideo> detail(String id, {CancelToken? cancel});
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  });
  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) async => const [];
  // selection 必须回显当前来源的 videoId/code/episodeNum，不能混用来源身份。
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  });
}
