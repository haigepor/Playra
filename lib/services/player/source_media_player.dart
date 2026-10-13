import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:kazumi/pages/player/controller/player_playback_controller.dart';
import 'package:kazumi/services/platform/resource_url.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 来源页面不伪造 Bangumi 身份；原生只复用原项目的播放配置与资源管理。
class SourceMediaPlayer {
  SourceMediaPlayer({
    bool? useWeb,
    PlayerPlaybackController Function(String Function(), PlayerDebugController)?
    createNative,
    double Function()? defaultRate,
    int Function()? logLevel,
  }) : _useWeb = useWeb ?? kIsWeb,
       _createNative = createNative,
       _defaultRate =
           defaultRate ??
           (() => GStorage.getSetting<double>(SettingsKeys.defaultPlaySpeed)),
       _logLevel =
           logLevel ??
           (() => GStorage.getSetting<int>(SettingsKeys.playerLogLevel));

  final bool _useWeb;
  final PlayerPlaybackController Function(
    String Function(),
    PlayerDebugController,
  )?
  _createNative;
  final double Function() _defaultRate;
  final int Function() _logLevel;
  final _debug = PlayerDebugController();
  PlayerPlaybackController? _native;
  StreamSubscription<String>? _errors;
  Player? player;
  VideoController? controller;
  String mediaUrl = '';
  bool _closed = false;
  Future<void>? _disposal;

  Future<Player?> open(
    String url,
    Map<String, String> headers, {
    required bool Function() canInstall,
    required void Function(String) onError,
  }) async {
    bool current() => !_closed && canInstall();
    if (!current()) return null;
    mediaUrl = platformResourceUrl(url, headers: headers);
    if (_useWeb) {
      final candidate = player ??= Player();
      controller ??= VideoController(candidate);
      await _errors?.cancel();
      await candidate.stop();
      if (!current()) return null;
      _errors = candidate.stream.error.listen(onError);
      await candidate.open(Media(mediaUrl));
      return current() ? candidate : null;
    }

    final core = _native ??=
        _createNative?.call(() => mediaUrl, _debug) ??
        PlayerPlaybackController(
          shaderAssetService: inject<ShaderAssetService>(),
          debug: _debug,
          videoUrl: () => mediaUrl,
          isLocalPlayback: () => false,
        );
    player = null;
    controller = null;
    await core.stop();
    if (!current()) return null;
    core.resetForInit();
    _debug.playerLogLevel = _logLevel();
    core.onMediaError = onError;
    // 硬解、OpenSLES/AudioTrack、渲染器、代理、着色器、双重缓存均由原控制器决定。
    final candidate = await core.createVideoController(
      headers,
      false,
      canInstall: current,
    );
    if (candidate == null) return null;
    if (!current()) {
      await core.stop();
      return null;
    }
    await candidate.setRate(_defaultRate());
    if (!current()) {
      await core.stop();
      return null;
    }
    core.loading = false;
    player = candidate;
    controller = core.videoController;
    return candidate;
  }

  Future<void> dispose() {
    _closed = true;
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    await _errors?.cancel();
    if (_native != null) {
      await _native!.stop();
    } else {
      await player?.dispose();
    }
    player = null;
    controller = null;
  }
}
