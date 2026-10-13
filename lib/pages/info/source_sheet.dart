import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/captcha_verification_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_candidates.dart';
import 'package:kazumi/services/source/source_policy.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/device.dart';
import 'package:url_launcher/url_launcher.dart';

part 'source_alias_dialog.dart';
part 'source_captcha_flow.dart';
part 'source_sheet_view.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({
    super.key,
    required this.infoController,
    this.onSelected,
    this.emptyIllustration,
    this.episodeNumber,
    this.rules,
  });

  final InfoController infoController;

  /// 新版原位播放；未传入时保留旧版播放路由行为。
  final ValueChanged<OnlineVideoPlaybackArgs>? onSelected;
  final Widget? emptyIllustration;
  final int? episodeNumber;
  final List<Plugin>? rules;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> with KazumiDialogOwner {
  final CollectController _collectController = inject<CollectController>();
  final PluginsController _pluginsController = inject<PluginsController>();
  List<Plugin> get _rules => widget.rules ?? _pluginsController.pluginList;
  final Map<String, String> _sourceKeywords = {};

  late final String _keyword;
  late final PluginSearchService _searchService;
  late final _SourceCaptchaFlow _captchaFlow;

  @override
  void initState() {
    super.initState();
    final item = widget.infoController.bangumiItem;
    _keyword = item.nameCn.isEmpty ? item.name : item.nameCn;
    _searchService = PluginSearchService(
      infoController: widget.infoController,
      pluginsController: _pluginsController,
      plugins: widget.rules,
    );
    _captchaFlow = _SourceCaptchaFlow(
      onVerified: _showVerifiedResult,
      onCancelled: (plugin) => _retry(plugin.name),
    );
    _searchService.queryAllSource(_keyword);
  }

  @override
  void dispose() {
    _searchService.cancel();
    _captchaFlow.dispose();
    super.dispose();
  }

  String _keywordFor(String name) => _sourceKeywords[name] ?? _keyword;

  Plugin _pluginFor(String name) =>
      _rules.firstWhere((plugin) => plugin.name == name);

  void _querySource(String keyword, String pluginName) {
    final trimmed = keyword.trim();
    if (!mounted || trimmed.isEmpty) return;
    setState(() => _sourceKeywords[pluginName] = trimmed);
    SourceCandidates.shared.invalidate(
      widget.infoController.bangumiItem,
      _pluginFor(pluginName),
    );
    _searchService.querySource(trimmed, pluginName);
  }

  void _retry(String name) => _querySource(_keywordFor(name), name);

  void _refreshAll() {
    setState(() => _sourceKeywords.clear());
    for (final plugin in _rules) {
      SourceCandidates.shared.invalidate(
        widget.infoController.bangumiItem,
        plugin,
      );
    }
    _searchService.queryAllSource(_keyword);
  }

  void _showVerifiedResult(Plugin plugin, String pageHtml) {
    if (!mounted) return;
    if (_searchService.applyHarvestedSearchResult(plugin.name, pageHtml)) {
      KazumiDialog.showToast(message: '验证成功');
      return;
    }
    _captchaFlow.showSuccess(
      plugin.name,
      onComplete: () => _retry(plugin.name),
    );
  }

  Future<void> _openInBrowser(String name) async {
    final plugin = _pluginFor(name);
    final targetUrl = plugin.usesApiSearch
        ? plugin.baseUrl
        : plugin.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(_keywordFor(name)),
          );
    try {
      if (await launchUrl(
        Uri.parse(targetUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (error) {
      KazumiLogger().w('SourceSheet: failed to open browser', error: error);
    }
    if (mounted) KazumiDialog.showToast(message: '无法打开浏览器，请稍后重试');
  }

  Future<void> _openSearchItem(String name, SearchItem searchItem) async {
    if (dialogs.isRunning) return;
    final plugin = _pluginFor(name);
    await dialogs.run(
      (task) async {
        final cancelToken = RuleCancelToken();
        final roads = await task.loading(
          message: '正在获取播放列表',
          barrierDismissible: isDesktop(),
          onCancel: cancelToken.cancel,
          action: () async =>
              SourceCandidates.shared
                  .find(
                    widget.infoController.bangumiItem,
                    plugin,
                    searchItem.src,
                  )
                  ?.roads ??
              await plugin.queryChapterRoads(
                searchItem.src,
                cancelToken: cancelToken,
              ),
        );
        if (roads.isEmpty) throw ChapterErrorException(plugin.name);
        final args = OnlineVideoPlaybackArgs(
          bangumiItem: widget.infoController.bangumiItem,
          plugin: plugin,
          title: searchItem.name,
          src: searchItem.src,
          roads: roads,
        );
        task.withContext((context) {
          if (widget.onSelected case final onSelected?) {
            onSelected(args);
          } else {
            context.pushNamed('/video/', arguments: args);
          }
        });
      },
      onError: (error, stackTrace) {
        KazumiLogger().w('SourceSheet: failed to query playlist', error: error);
        KazumiDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
      },
    );
  }

  void _selectAutomatic() {
    final work = widget.infoController.bangumiItem;
    final readyNames = widget.infoController.pluginSearchStatus.entries
        .where((e) => e.value == PluginSearchStatus.success)
        .map((e) => e.key)
        .toSet();
    final candidates = SourceCandidates.shared
        .cached(work, _rules)
        .where(
          (c) =>
              c.matched &&
              (widget.episodeNumber == null ||
                  c.matchEpisode(widget.episodeNumber!) != null) &&
              readyNames.contains(c.plugin.name) &&
              !SourcePolicy.shared.coolingDown(
                c.plugin.providerId,
                c.plugin.version,
              ),
        )
        .toList();
    final unique = candidates
        .where(
          (c) =>
              candidates
                  .where(
                    (other) => other.plugin.providerId == c.plugin.providerId,
                  )
                  .length ==
              1,
        )
        .toList();
    if (unique.isEmpty) {
      KazumiDialog.showToast(message: '暂时没有能唯一匹配作品的来源，请手动选择');
      return;
    }
    final args = unique.first.args(work, automatic: true);
    if (widget.onSelected case final selected?) {
      selected(args);
    } else {
      context.pushNamed('/video/', arguments: args);
    }
  }

  void _showAliasPicker(String pluginName) {
    if (widget.infoController.bangumiItem.alias.isEmpty) {
      KazumiDialog.showToast(message: '无可用别名，试试修改检索关键词');
      return;
    }
    _showAliasPickerDialog(
      context: context,
      sourceName: pluginName,
      aliases: widget.infoController.bangumiItem.alias,
      onAliasSelected: (alias) => _querySource(alias, pluginName),
      onAliasesChanged: () => _collectController.updateLocalCollect(
        widget.infoController.bangumiItem,
      ),
    );
  }

  void _showCustomKeyword(String pluginName) => _showCustomKeywordDialog(
    context: context,
    initialKeyword: _keywordFor(pluginName),
    sourceName: pluginName,
    onSubmit: (keyword) {
      // 自定义检索词不是作品别名，不能污染后续自动匹配的证据。
      _querySource(keyword, pluginName);
    },
  );

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      // Snapshot observable values here; lazy list builders are not tracked.
      final groupsByName = {
        for (final plugin in SourceCandidates.shared.eligible(
          _rules,
          widget.infoController.bangumiItem,
        ))
          plugin.name: _SourceSearchGroup(
            name: plugin.name,
            keyword: _keywordFor(plugin.name),
            status:
                widget.infoController.pluginSearchStatus[plugin.name] ??
                PluginSearchStatus.pending,
            results: <SearchItem>[],
          ),
      };
      final seenBySource = <String, Set<String>>{};
      String? firstResultSource;
      // Responses follow completion order; groups keep configured order.
      for (final response in widget.infoController.pluginSearchResponseList) {
        final group = groupsByName[response.pluginName];
        if (group == null) continue;
        final seen = seenBySource.putIfAbsent(group.name, () => <String>{});
        for (final result in response.data) {
          final candidate = SourceCandidates.shared.find(
            widget.infoController.bangumiItem,
            _pluginFor(group.name),
            result.src,
          );
          if (widget.episodeNumber != null &&
              candidate?.confirmsMissingEpisode(widget.episodeNumber!) ==
                  true) {
            continue;
          }
          if (seen.add(result.src)) group.results.add(result);
        }
        if (group.hasResults) firstResultSource ??= group.name;
      }
      return _SourceSheetView(
        emptyIllustration: widget.emptyIllustration,
        keyword: _keyword,
        groups:
            groupsByName.values
                .where(
                  (group) =>
                      group.status != PluginSearchStatus.noResult &&
                      !(group.status == PluginSearchStatus.success &&
                          group.results.isEmpty),
                )
                .toList()
              ..sort((a, b) {
                final score = SourcePolicy.shared
                    .score(
                      _pluginFor(a.name).providerId,
                      _pluginFor(a.name).version,
                    )
                    .compareTo(
                      SourcePolicy.shared.score(
                        _pluginFor(b.name).providerId,
                        _pluginFor(b.name).version,
                      ),
                    );
                return score != 0
                    ? score
                    : _rules
                          .indexWhere((p) => p.name == a.name)
                          .compareTo(
                            _rules.indexWhere((p) => p.name == b.name),
                          );
              }),
        onAutomatic:
            SourceCandidates.shared
                .cached(widget.infoController.bangumiItem, _rules)
                .any(
                  (c) =>
                      c.matched &&
                      (widget.episodeNumber == null ||
                          c.matchEpisode(widget.episodeNumber!) != null),
                )
            ? _selectAutomatic
            : null,
        onRefresh: _refreshAll,
        onSearchAll: () => _showCustomKeywordDialog(
          context: context,
          initialKeyword: _keyword,
          sourceName: '全部来源',
          onSubmit: (keyword) {
            for (final p in _rules) {
              SourceCandidates.shared.invalidate(
                widget.infoController.bangumiItem,
                p,
              );
              _sourceKeywords[p.name] = keyword;
            }
            _searchService.queryAllSource(keyword);
          },
        ),
        firstResultSource: firstResultSource,
        onSourceSearch: _showCustomKeyword,
        onSourceAliasSearch: _showAliasPicker,
        onRetry: _retry,
        onVerify: (name) =>
            _captchaFlow.start(_pluginFor(name), _keywordFor(name)),
        onOpenBrowser: _openInBrowser,
        onPlay: _openSearchItem,
        onClose: () => Navigator.of(context).pop(),
      );
    },
  );
}
