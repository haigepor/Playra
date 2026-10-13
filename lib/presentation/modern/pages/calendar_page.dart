import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/calendar/calendar_service.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernCalendarView(
    controller: controller,
    onDetails: (item) => context.pushNamed('/info/', arguments: item),
    onResume: _resume,
    onStyle: () => context.pushNamed('/settings/interface'),
  );
}
