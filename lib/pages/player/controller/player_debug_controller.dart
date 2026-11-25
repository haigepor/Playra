// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

part 'player_debug_controller.g.dart';

class PlayerDebugController = _PlayerDebugController
    with _$PlayerDebugController;

/// Fixed-format diagnostics. Native text and metadata can contain signed URLs,
/// local paths, credentials or request headers and are intentionally omitted.
@visibleForTesting
class PlayerDebugSummary {
  static String log(PlayerLog event) {
    final level = switch (event.level.toLowerCase()) {
      'fatal' => '致命',
      'error' => '错误',
      'warn' => '警告',
      'info' => '信息',
      'v' || 'debug' || 'trace' => '调试',
      _ => '其他',
    };
    return '播放器内核 · $level（详细内容已隐藏）';
  }

  static String playlist(Playlist value) {
    final active = value.index >= 0 && value.index < value.medias.length
        ? '${value.index + 1}'
        : '无';
    return '条目数：${value.medias.length}，当前序号：$active';
  }

  static String videoTrack(VideoTrack value) =>
      '尺寸：${value.w ?? 0} × ${value.h ?? 0}，帧率：${value.fps ?? 0}';

  static String audioTrack(AudioTrack value) =>
      '声道数：${value.channelscount ?? 0}，采样率：${value.samplerate ?? 0} Hz';

  static String videoParams(VideoParams value) =>
      '尺寸：${value.w ?? 0} × ${value.h ?? 0}，旋转：${value.rotate ?? 0}°';

  static String audioParams(AudioParams value) =>
      '声道数：${value.channelCount ?? 0}，采样率：${value.sampleRate ?? 0} Hz';
}

abstract class _PlayerDebugController with Store {
  static const int maxLogEntries = 500;

  /// Adds only a fixed-format summary and bounds memory for long sessions.
  @visibleForTesting
  void recordLog(PlayerLog event, {bool persist = false}) {
    final summary = PlayerDebugSummary.log(event);
    runInAction(() {
      if (playerLog.length >= maxLogEntries) {
        playerLog.removeRange(0, playerLog.length - maxLogEntries + 1);
      }
      playerLog.add(summary);
    });
    if (persist) KazumiLogger().i(summary, forceLog: true);
  }

  /// LogLevel 0: 错误 1: 警告 2: 简略 3: 详细
  int playerLogLevel = 2;

  @observable
  ObservableList<String> playerLog = ObservableList.of([]);
  @observable
  int playerWidth = 0;
  @observable
  int playerHeight = 0;
  @observable
  String playerVideoParams = '';
  @observable
  String playerAudioParams = '';
  @observable
  String playerPlaylist = '';
  @observable
  String playerAudioTracks = '';
  @observable
  String playerVideoTracks = '';
  @observable
  String playerAudioBitrate = '';
  @observable
  String playerVideoBitrate = '';

  StreamSubscription<PlayerLog>? playerLogSubscription;
  StreamSubscription<int?>? playerWidthSubscription;
  StreamSubscription<int?>? playerHeightSubscription;
  StreamSubscription<VideoParams>? playerVideoParamsSubscription;
  StreamSubscription<AudioParams>? playerAudioParamsSubscription;
  StreamSubscription<Playlist>? playerPlaylistSubscription;
  StreamSubscription<Track>? playerTracksSubscription;
  StreamSubscription<double?>? playerAudioBitrateSubscription;
  StreamSubscription<double?>? playerVideoBitrateSubscription;

  Future<void> setup(
    Player player, {
    required bool Function(Player player) isCurrentPlayer,
    required bool playerDebugMode,
  }) async {
    await playerLogSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerLogSubscription = player.stream.log.listen((event) {
      if (!isCurrentPlayer(player)) return;
      recordLog(event, persist: playerDebugMode);
    });
    await playerWidthSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerWidthSubscription = player.stream.width.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerWidth = event ?? 0;
    });
    await playerHeightSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerHeightSubscription = player.stream.height.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerHeight = event ?? 0;
    });
    await playerVideoParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoParamsSubscription = player.stream.videoParams.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerVideoParams = PlayerDebugSummary.videoParams(event);
    });
    await playerAudioParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioParamsSubscription = player.stream.audioParams.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioParams = PlayerDebugSummary.audioParams(event);
    });
    await playerPlaylistSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerPlaylistSubscription = player.stream.playlist.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerPlaylist = PlayerDebugSummary.playlist(event);
    });
    await playerTracksSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerTracksSubscription = player.stream.track.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioTracks = PlayerDebugSummary.audioTrack(event.audio);
      playerVideoTracks = PlayerDebugSummary.videoTrack(event.video);
    });
    await playerAudioBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioBitrateSubscription = player.stream.audioBitrate.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerAudioBitrate = event.toString();
    });
    await playerVideoBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoBitrateSubscription = player.stream.videoBitrate.listen((event) {
      if (!isCurrentPlayer(player)) return;
      playerVideoBitrate = event.toString();
    });
  }

  Future<void> cancel() async {
    // Detach fields before awaiting so a new player cannot lose its listeners.
    final logSubscription = playerLogSubscription;
    final widthSubscription = playerWidthSubscription;
    final heightSubscription = playerHeightSubscription;
    final videoParamsSubscription = playerVideoParamsSubscription;
    final audioParamsSubscription = playerAudioParamsSubscription;
    final playlistSubscription = playerPlaylistSubscription;
    final tracksSubscription = playerTracksSubscription;
    final audioBitrateSubscription = playerAudioBitrateSubscription;
    final videoBitrateSubscription = playerVideoBitrateSubscription;

    playerLogSubscription = null;
    playerWidthSubscription = null;
    playerHeightSubscription = null;
    playerVideoParamsSubscription = null;
    playerAudioParamsSubscription = null;
    playerPlaylistSubscription = null;
    playerTracksSubscription = null;
    playerAudioBitrateSubscription = null;
    playerVideoBitrateSubscription = null;

    await logSubscription?.cancel();
    await widthSubscription?.cancel();
    await heightSubscription?.cancel();
    await videoParamsSubscription?.cancel();
    await audioParamsSubscription?.cancel();
    await playlistSubscription?.cancel();
    await tracksSubscription?.cancel();
    await audioBitrateSubscription?.cancel();
    await videoBitrateSubscription?.cancel();
  }
}
