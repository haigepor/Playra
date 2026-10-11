import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_sync_plan.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_sync_dialog.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/storage.dart';
import '../home/home_theme.dart';
import '../library/modern_library_controller.dart';
import '../library/modern_library_view.dart';

class ModernLibraryPage extends StatefulWidget {
  const ModernLibraryPage({super.key, required this.controller});
  final CollectController controller;
  @override
  State<ModernLibraryPage> createState() => _ModernLibraryPageState();
}

/// 路由接线沿用共享收藏控制器、仓库和播放器，新版不另建数据存储。
class _ModernLibraryPageState extends State<ModernLibraryPage>
    with WidgetsBindingObserver, KazumiDialogOwner {
  late final ModernLibraryController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final collections = inject<ICollectCrudRepository>();
    final histories = inject<IHistoryRepository>();
    controller = ModernLibraryController(
      readCollections: collections.getAllCollectibles,
      readHistory: histories.getAllHistories,
      collectionChanges: collections.changes,
      historyChanges: histories.changes,
      layout: CollectLayout.fromValue(
        GStorage.getSetting(SettingsKeys.defaultCollectLayout),
      ),
      changeCollection: (item, type) =>
          widget.controller.addCollect(item, type: type.value),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.reloadLocal();
  }

  Future<bool> _changeType(BangumiItem item, CollectType type) async {
    if (dialogs.isRunning || !controller.canEdit(item.id)) return false;
    final changed = await controller.changeStatus(item, type);
    if (mounted && controller.mutationError != null) {
      KazumiDialog.showToast(message: controller.mutationError!);
    }
    return changed;
  }

  Future<void> _resume(History history) async {
    if (dialogs.isRunning || !controller.canSync) return;
    controller.setLocked(true);
    try {
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
    } finally {
      controller.setLocked(false);
      controller.reloadLocal();
    }
  }

  Future<bool> _syncStep(
    CollectSyncStep step, {
    required ValueChanged<String> onError,
    required void Function(String message, int current, int total) onProgress,
  }) => switch (step) {
    CollectSyncStep.webDav => widget.controller.syncCollectibles(
      onError: onError,
    ),
    CollectSyncStep.bangumi => widget.controller.syncCollectiblesBangumi(
      onError: onError,
      onProgress: onProgress,
    ),
    CollectSyncStep.upload => widget.controller.uploadCollectiblesToWebDav(
      onError: onError,
    ),
  };

  Future<void> _sync() async {
    if (dialogs.isRunning || !controller.canSync) return;
    controller.setLocked(true);
    try {
      final plan = CollectSyncPlan(
        webDavEnabled: GStorage.getSetting(SettingsKeys.webDavEnable),
        webDavCollectiblesEnabled: GStorage.getSetting(
          SettingsKeys.webDavEnableCollect,
        ),
        bangumiEnabled: GStorage.getSetting(SettingsKeys.bangumiSyncEnable),
      );
      await dialogs.run((task) async {
        final destination = await task.show<CollectSyncDestination>(
          builder: (_) => ModernHomeScope(
            child: CollectSyncDialog(
              plan: plan,
              priority: BangumiSyncPriority.fromValue(
                GStorage.getSetting(SettingsKeys.bangumiSyncPriority),
              ),
              onSync: _syncStep,
            ),
          ),
        );
        task.withContext(
          (context) => context.pushNamed(switch (destination) {
            CollectSyncDestination.webDavSettings => '/settings/webdav/',
            CollectSyncDestination.bangumiSettings => '/settings/bangumi/',
          }),
        );
      }, errorMessage: '同步未完成，请稍后重试');
    } finally {
      controller.setLocked(false);
      controller.reloadLocal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernLibraryView(
    controller: controller,
    showRating: GStorage.getSetting(SettingsKeys.showRating),
    onDetails: (item) => context.pushNamed('/info/', arguments: item),
    onResume: (history) => unawaited(_resume(history)),
    onChangeType: _changeType,
    onSync: () => unawaited(_sync()),
    onStyle: () => context.pushNamed('/settings/interface'),
    onDiscover: () {
      final select = TabDestinationScope.maybeOf(context);
      if (select != null) {
        select(0);
      } else {
        context.pushNamed('/tab/popular/');
      }
    },
  );
}
