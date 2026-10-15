import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';
import 'package:kazumi/services/source/source_candidates.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

sealed class HistoryPlaybackResult {
  const HistoryPlaybackResult();
}

class HistoryPlaybackReady extends HistoryPlaybackResult {
  const HistoryPlaybackReady(this.args);

  final VideoPlaybackArgs args;
}

class HistoryPlaybackUnavailable extends HistoryPlaybackResult {
  const HistoryPlaybackUnavailable(this.reason);

  final String reason;
}

/// Restores a history entry into arguments the player route can take.
///
/// The history page and the my page share this one resolution path; cards
/// carry no source-lookup logic of their own.
class HistoryPlaybackService {
  HistoryPlaybackService(this._pluginsController, this._downloadController);

  final PluginsController _pluginsController;
  final DownloadController _downloadController;

  /// [cancelToken] lets the caller abort the online lookup, e.g. when the
  /// loading dialog it put up is dismissed.
  Future<HistoryPlaybackResult> open(
    History history, {
    RuleCancelToken? cancelToken,
  }) async {
    if (HistoryEntryKind.normalize(history.entryKind) ==
        HistoryEntryKind.offline) {
      final args = _offlineArgs(history);
      return args == null
          ? const HistoryPlaybackUnavailable('未找到可用缓存')
          : HistoryPlaybackReady(args);
    }

    final args = await _onlineArgs(history, cancelToken);
    return args == null
        ? const HistoryPlaybackUnavailable('在线源不可用，请重新选择播放源')
        : HistoryPlaybackReady(args);
  }

  Future<VideoPlaybackArgs?> _onlineArgs(
    History history,
    RuleCancelToken? cancelToken,
  ) async {
    if (history.lastSrc.isEmpty) {
      return null;
    }
    Plugin? targetPlugin;
    for (final plugin in _pluginsController.pluginList) {
      if (matchesAnimeHistorySource(
        plugin,
        history.adapterName,
        history.lastSrc,
      )) {
        targetPlugin = plugin;
        break;
      }
    }
    if (targetPlugin == null) {
      // aafun 是 moonci 同站旧名；优先复用原详情/集路径，不改写历史库。
      if (history.adapterName.toLowerCase() == 'aafun') {
        targetPlugin = _pluginsController.pluginList
            .where((p) => isManagedAnimeSource(p, 'd') && p.enabled)
            .firstOrNull;
      }
      if (targetPlugin == null) return _replacementArgs(history, cancelToken);
    }
    try {
      final roads = await targetPlugin.queryChapterRoads(
        history.lastSrc,
        cancelToken: cancelToken,
      );
      if (roads.isEmpty) {
        return null;
      }
      return OnlineVideoPlaybackArgs(
        bangumiItem: history.bangumiItem,
        plugin: targetPlugin,
        title: history.bangumiItem.nameCn.isEmpty
            ? history.bangumiItem.name
            : history.bangumiItem.nameCn,
        src: history.lastSrc,
        roads: roads,
      );
    } catch (_) {
      KazumiLogger().w("QueryManager: failed to query roads");
      return null;
    }
  }

  Future<VideoPlaybackArgs?> _replacementArgs(
    History history,
    RuleCancelToken? parent,
  ) async {
    final number = regularEpisodeNumber(history.lastWatchEpisodeName);
    if (number == null || history.bangumiItem.type != 2) return null;
    final cancel = parent ?? RuleCancelToken();
    try {
      final choice = await SourceCandidates.shared
          .selectEpisode(
            history.bangumiItem,
            _pluginsController.pluginList.toList(),
            number,
            cancel,
          )
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (choice == null || cancel.isCancelled) return null;
      final args = choice.candidate.args(history.bangumiItem, automatic: true);
      // 不跨版本盲目套用时间偏移；旧历史和进度仍保留，目标集从头打开。
      return OnlineVideoPlaybackArgs(
        bangumiItem: args.bangumiItem,
        plugin: args.plugin,
        title: args.title,
        src: args.src,
        roads: args.roads,
        automatic: true,
        initialEpisode: choice.episode,
        initialRoad: choice.road,
      );
    } catch (_) {
      return null;
    } finally {
      if (parent == null) cancel.cancel('history lookup finished');
    }
  }

  VideoPlaybackArgs? _offlineArgs(History history) {
    final downloadedEpisodes = _downloadController.getCompletedEpisodes(
      history.bangumiItem.id,
      history.adapterName,
    );
    if (downloadedEpisodes.isEmpty) {
      return null;
    }

    // The page url pins the exact episode; the number is the legacy fallback.
    DownloadEpisode? targetEpisode;
    DownloadEpisode? numberMatch;
    for (final episode in downloadedEpisodes) {
      if (history.episodePageUrl.isNotEmpty &&
          episode.episodePageUrl == history.episodePageUrl) {
        targetEpisode = episode;
        break;
      }
      if (episode.episodeNumber == history.lastWatchEpisode) {
        numberMatch ??= episode;
      }
    }
    targetEpisode ??= numberMatch;
    if (targetEpisode == null) {
      return null;
    }

    final localPath = _downloadController.getLocalVideoPath(
      history.bangumiItem.id,
      history.adapterName,
      targetEpisode.episodeNumber,
    );
    if (localPath == null) {
      return null;
    }

    return OfflineVideoPlaybackArgs(
      bangumiItem: history.bangumiItem,
      pluginName: history.adapterName,
      episodeNumber: targetEpisode.episodeNumber,
      road: targetEpisode.road,
      downloadedEpisodes: downloadedEpisodes,
    );
  }
}
