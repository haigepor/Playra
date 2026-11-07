import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/calendar/calendar_service.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/source/content_search.dart' show contentTitleKey;
import 'package:kazumi/services/source/lumina/lumina_playback_provider.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import '../calendar/modern_calendar_controller.dart';
import '../calendar/modern_calendar_view.dart';

class ModernCalendarPage extends StatefulWidget {
  const ModernCalendarPage({super.key});
  @override
  State<ModernCalendarPage> createState() => _ModernCalendarPageState();
}

/// 路由层只连接已有仓库与播放流程，新版视图不直接访问 Hive。
class _ModernCalendarPageState extends State<ModernCalendarPage>
    with WidgetsBindingObserver, KazumiDialogOwner {
  late final ModernCalendarController controller;
  LuminaService? _lumina;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final collections = inject<ICollectCrudRepository>();
    final preferences = inject<ICollectRepository>();
    final histories = inject<IHistoryRepository>();
    final service = CalendarService.instance;
    controller = ModernCalendarController(
      load: (season, {required force, required cancelToken}) =>
          service.load(season, force: force, cancelToken: cancelToken),
      enrich: (entry, {required force, required cancelToken}) =>
          service.enrich(entry, force: force, cancelToken: cancelToken),
      readCollections: () => {
        for (final item in collections.getAllCollectibles())
          item.bangumiItem.id: CollectType.fromValue(item.type),
      },
      readHistory: histories.getAllHistories,
      collectionChanges: collections.changes,
      historyChanges: histories.changes,
      watchingOnly: preferences.getTimelineOnlyShowWatchingBangumis(),
      hideWatched: preferences.getTimelineNotShowWatchedBangumis(),
      hideAbandoned: preferences.getTimelineNotShowAbandonedBangumis(),
      writePreferences:
          ({
            required watchingOnly,
            required hideWatched,
            required hideAbandoned,
          }) async {
            await preferences.updateTimelineOnlyShowWatchingBangumis(
              watchingOnly,
            );
            await preferences.updateTimelineNotShowWatchedBangumis(hideWatched);
            await preferences.updateTimelineNotShowAbandonedBangumis(
              hideAbandoned,
            );
          },
    );
    unawaited(controller.refresh(force: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) {
      controller.updateToday();
      unawaited(controller.refresh(force: false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = !RouteVisibility.isCoveredOf(context);
    controller.setVisible(_visible);
  }

  Future<void> _resume(History history) async {
    if (dialogs.isRunning) return;
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final result = await task.loading(
        message: '获取中',
        barrierDismissible: false,
        onCancel: cancelToken.cancel,
        action: () => inject<HistoryPlaybackService>().open(
          history,
          cancelToken: cancelToken,
        ),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
            (context) => context.pushNamed('/video/', arguments: args),
          );
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请稍后重试');
  }

  Future<void> _openDetails(BangumiItem item) async {
    final title = (item.nameCn.isEmpty ? item.name : item.nameCn).trim();
    if (title.isEmpty) return;
    if (luminaSupported) {
      if (dialogs.isRunning) return;
      await dialogs.run((task) async {
        final cancelToken = CancelToken();
        SdkPlaybackEntry? entry;
        try {
          entry = await task.loading<SdkPlaybackEntry?>(
            message: '获取中',
            barrierDismissible: false,
            onCancel: cancelToken.cancel,
            action: () async {
              final service = _lumina ??= LuminaService();
              final page = await service.search(
                title,
                size: 10,
                cancel: cancelToken,
              );
              final key = contentTitleKey(title);
              final exact = page.items
                  .where((v) => contentTitleKey(v.title) == key)
                  .firstOrNull;
              final target =
                  exact ?? (page.items.length == 1 ? page.items.single : null);
              if (target == null) return null;
              return SdkPlaybackEntry(
                title: target.title,
                cover: target.cover.isNotEmpty
                    ? target.cover
                    : [
                        for (final size in [
                          'large',
                          'common',
                          'medium',
                          'small',
                        ])
                          item.images[size] ?? '',
                      ].firstWhere((url) => url.isNotEmpty, orElse: () => ''),
                autoPlay: false,
                sources: [
                  SdkSourceBinding(
                    provider: LuminaPlaybackProvider(service),
                    contentId: target.id,
                    seed: target,
                  ),
                ],
              );
            },
          );
        } catch (_) {
          if (cancelToken.isCancelled) return;
        }
        if (cancelToken.isCancelled) return;
        task.withContext((context) {
          if (entry != null) {
            context.pushNamed('/info/', arguments: entry);
          } else {
            context.pushNamed('/search/${Uri.encodeComponent(title)}');
          }
        });
      });
      return;
    }
    context.pushNamed('/search/${Uri.encodeComponent(title)}');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lumina?.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernCalendarView(
    controller: controller,
    onDetails: _openDetails,
    onResume: _resume,
    onStyle: () => context.pushNamed('/settings/interface'),
  );
}
