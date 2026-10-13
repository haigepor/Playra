import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:kazumi/services/source/source_candidates.dart';

class PluginSearchService {
  PluginSearchService({
    required this.infoController,
    required this.pluginsController,
  });

  final InfoController infoController;
  final PluginsController pluginsController;
  final RuleCancelToken _cancelToken = RuleCancelToken();

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  final AsyncSessionOwner _batchSessions = AsyncSessionOwner();
  final Map<String, RuleCancelToken> _queryTokens = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName) {
        infoController.pluginSearchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        infoController.pluginSearchStatus[pluginName] =
            PluginSearchStatus.pending;
        await _queryPlugin(plugin, keyword);
        return;
      }
    }
  }

  /// Publishes the result page harvested by the captcha webview, skipping
  /// one network round trip. Returns false when the HTML does not parse
  /// into results; callers should fall back to [querySource].
  bool applyHarvestedSearchResult(String pluginName, String html) {
    if (_isCancelled) return false;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name != pluginName) continue;
      final result = plugin.parseHarvestedSearch(html);
      if (result == null) return false;
      // 验证结果与正常查询共用代次，防止旧搜索在验证后覆盖结果。
      final session = _querySessions
          .putIfAbsent(pluginName, AsyncSessionOwner.new)
          .begin();
      final token = _beginQuery(pluginName);
      infoController.pluginSearchStatus[pluginName] =
          PluginSearchStatus.pending;
      _publishPrepared(plugin, result, session, cancelToken: token);
      return true;
    }
    return false;
  }

  Future<void> queryAllSource(String keyword) async {
    if (_isCancelled) return;
    final batch = _batchSessions.begin();
    for (final owner in _querySessions.values) {
      owner.cancel();
    }
    for (final token in _queryTokens.values) {
      token.cancel('replaced');
    }
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();

    final plugins = SourceCandidates.shared.eligible(
      pluginsController.pluginList,
      infoController.bangumiItem,
    );
    final queuedTokens = <String, RuleCancelToken>{};
    for (final plugin in plugins) {
      queuedTokens[plugin.name] = _beginQuery(plugin.name);
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.pending;
    }
    var next = 0;
    Future<void> worker() async {
      while (!_isCancelled && batch.isActive && next < plugins.length) {
        final plugin = plugins[next++];
        await _queryPlugin(
          plugin,
          keyword,
          queuedToken: queuedTokens[plugin.name],
        );
      }
    }

    await Future.wait(
      List.generate(plugins.length.clamp(0, 4), (_) => worker()),
    );
  }

  Future<void> _queryPlugin(
    Plugin plugin,
    String keyword, {
    RuleCancelToken? queuedToken,
  }) async {
    if (_isCancelled) return;
    // 队列尚未启动时发生人工查询，旧批次不得重新抢占该来源。
    if (queuedToken != null &&
        !identical(_queryTokens[plugin.name], queuedToken)) {
      return;
    }
    final session = _querySessions
        .putIfAbsent(plugin.name, AsyncSessionOwner.new)
        .begin();
    final token = queuedToken ?? _beginQuery(plugin.name);
    try {
      final result = await plugin.queryBangumi(
        keyword,
        shouldRethrow: true,
        cancelToken: token,
      );
      if (_isCancelled || session.isStale) return;
      await _publishPrepared(
        plugin,
        result,
        session,
        cancelToken: token,
        allowUnmatched:
            keyword !=
            (infoController.bangumiItem.nameCn.isEmpty
                ? infoController.bangumiItem.name
                : infoController.bangumiItem.nameCn),
      );
    } catch (error) {
      if (_isCancelled || session.isStale) return;
      _handleSearchError(plugin, error);
    }
  }

  Future<void> _publishPrepared(
    Plugin plugin,
    PluginSearchResponse result,
    AsyncSession session, {
    required RuleCancelToken cancelToken,
    bool allowUnmatched = false,
  }) async {
    try {
      final candidates = await SourceCandidates.shared.prepare(
        infoController.bangumiItem,
        plugin,
        result.data,
        cancelToken: cancelToken,
        allowUnmatched: allowUnmatched,
      );
      if (_isCancelled || session.isStale) return;
      infoController.pluginSearchResponseList.removeWhere(
        (r) => r.pluginName == plugin.name,
      );
      infoController.pluginSearchStatus[plugin.name] = candidates.isEmpty
          ? PluginSearchStatus.noResult
          : PluginSearchStatus.success;
      if (candidates.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(
        PluginSearchResponse(
          pluginName: plugin.name,
          data: candidates.map((c) => c.item).toList(),
        ),
      );
    } catch (error) {
      if (!_isCancelled && session.isActive) _handleSearchError(plugin, error);
    }
  }

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      KazumiLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      KazumiLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    KazumiLogger().w('PluginSearchService: search error for $name');
    infoController.pluginSearchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    _batchSessions.cancel();
    _cancelToken.cancel();
  }

  RuleCancelToken _beginQuery(String name) {
    _queryTokens[name]?.cancel('replaced');
    final token = RuleCancelToken();
    _queryTokens[name] = token;
    _cancelToken.whenCancel.then((_) => token.cancel());
    return token;
  }
}
