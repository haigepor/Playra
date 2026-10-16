import 'package:dio/dio.dart';
import 'sdk_playback_models.dart';
import 'source_models.dart' show SourceException;

/// SDK 负责协议，公共会话负责选线；不要求页面识别具体 SDK 类型。
abstract class SdkPlaybackProvider {
  String get id;
  String get name;
  bool get supportsQualities => false;
  String get automaticQualityLabel => '自动（最高画质）';
  // 默认沿用最高已知分辨率；供应商可声明固定的画质偏好，不改线路身份。
  int qualityPreference(SdkQuality quality) => quality.height ?? 0;
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
  Future<List<SdkQuality>> qualitiesForEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    CancelToken? cancel,
  }) async {
    final number = episode.number;
    return number == null
        ? const []
        : qualities(id, code, number, cancel: cancel);
  }

  /// 默认兼容数字型 SDK；不透明集名由对应供应商重写，禁止转成数组下标。
  Future<Map<String, dynamic>> playEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    String? quality,
    CancelToken? cancel,
  }) {
    final number = episode.number;
    if (number == null) {
      throw const SourceException('INVALID_REFERENCE', '来源未提供数字剧集身份');
    }
    return play(id, code, number, quality: quality, cancel: cancel);
  }

  // selection 必须回显当前来源的 videoId/code/episodeNum，不能混用来源身份。
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  });
}
