import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/storage.dart';
import '../home/modern_home_controller.dart';
import '../home/home_catalog.dart';
import '../home/modern_home_view.dart';
import '../home/home_theme.dart';
import '../miomedia/miomedia_home_controller.dart';
import '../miomedia/miomedia_browse.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

/// 路由适配层：新版视图不直接读取全局容器或启动独立业务仓库。
class ModernDiscoverPage extends StatefulWidget {
  const ModernDiscoverPage({super.key});
  @override
  State<ModernDiscoverPage> createState() => _ModernDiscoverPageState();
}

class _ModernDiscoverPageState extends State<ModernDiscoverPage>
    with KazumiDialogOwner {
  late final ModernHomeController controller;
  late final MioMediaService mediaService;
  late final MioHomeController media;
  bool _changingTheme = false;

  @override
  void initState() {
    super.initState();
    final repository = inject<IHistoryRepository>();
    controller = ModernHomeController(
      loadProgressiveCatalog: (onUpdate) => HomeCatalog.load(
        rules: inject<PluginsController>().pluginList,
        force: false,
        onUpdate: onUpdate,
      ),
      loadDetail: HomeCatalog.loadDetail,
      readHistory: repository.getAllHistories,
      historyChanges: repository.changes,
    );
    unawaited(controller.refresh());
    mediaService = MioMediaService();
    media = MioHomeController(mediaService);
    unawaited(media.bootstrap());
  }

  void _search(BuildContext pageContext) {
    showModalBottomSheet<void>(
      context: pageContext,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('动漫搜索'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.pushNamed('/search/');
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: const Text('影视搜索'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MioBrowsePage(
                      service: mediaService,
                      onDetails: (item) =>
                          context.pushNamed('/info/', arguments: item),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.setVisible(!RouteVisibility.isCoveredOf(context));
  }

  Future<void> _toggleTheme() async {
    if (_changingTheme) return;
    _changingTheme = true;
    final theme = context.read<ThemeProvider>();
    final mode = theme.isEffectiveDark() ? ThemeMode.light : ThemeMode.dark;
    try {
      // 先持久化，再通知全局主题，写入失败时不制造界面与设置不一致。
      await GStorage.putSetting(SettingsKeys.themeMode, mode.name);
      if (mounted) theme.setThemeMode(mode);
    } catch (_) {
      KazumiDialog.showToast(message: '保存主题失败，请稍后重试');
    } finally {
      _changingTheme = false;
    }
  }

  @override
  void dispose() {
    media.dispose();
    mediaService.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => ModernHomeView(
        controller: controller,
        media: media,
        onMediaDetails: (item) => context.pushNamed('/info/', arguments: item),
        onSearch: () => _search(context),
        // 交给主壳层切换，移动端不会重建整个分页缓存。
        onCalendar: () {
          final select = TabDestinationScope.maybeOf(context);
          if (select != null) {
            select(1);
          } else {
            (rootNavigatorKey.currentContext ?? context).navigate(
              '/tab/timeline/',
            );
          }
        },
        onBrowse: (tag) => context.pushNamed(
          tag.isEmpty ? '/search/' : '/search/${Uri.encodeComponent(tag)}',
        ),
        onHistory: () => context.pushNamed('/settings/history/'),
        onToggleTheme: _toggleTheme,
        onDetails: (item) => context.pushNamed('/info/', arguments: item),
        onResume: _resume,
      ),
    ),
  );
}
