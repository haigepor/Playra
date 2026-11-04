import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'dart:async';
import 'package:kazumi/services/platform/platform_io.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/services/download/background_download_service.dart';
import 'package:kazumi/services/platform/windows_shortcut.dart';
import 'package:kazumi/services/platform/platform_environment_service.dart';
import 'package:kazumi/services/platform/app_exit.dart';
import 'package:kazumi/services/update/startup_update_check.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.downloadController,
    required this.danmakuShieldSync,
  });

  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DownloadController downloadController;
  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  PluginsController get pluginsController => widget.pluginsController;
  CollectController get collectController => widget.collectController;
  ShaderAssetService get shaderAssetService => widget.shaderAssetService;
  MyController get myController => widget.myController;
  DownloadController get downloadController => widget.downloadController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    widget.danmakuShieldSync.start();
    _migrateStorage();
    _loadShaders();
    unawaited(myController.loadShieldList());
    _webDavInit();
    try {
      await downloadController.init();
      _setupBackgroundDownloadNavigation();
    } catch (e) {
      KazumiLogger().e('InitPage: downloadController.init() failed', error: e);
    }

    await _checkRunningOnX11();
    await _showShortcutDialog();
    await _pluginInit();

    if (!mounted) {
      return;
    }
    // 旧用户按已有规则迁移；新设备先记录未完成，避免安装默认规则后跳过剩余步骤。
    var onboardingCompleted = GStorage.getSetting(
      SettingsKeys.onboardingCompleted,
    );
    if (onboardingCompleted == null) {
      onboardingCompleted = pluginsController.pluginList.isNotEmpty;
      try {
        await GStorage.putSetting(
          SettingsKeys.onboardingCompleted,
          onboardingCompleted,
        );
      } catch (error, stackTrace) {
        KazumiLogger().e('引导状态初始化失败', error: error, stackTrace: stackTrace);
        if (mounted) context.navigate('/error');
        return;
      }
      if (!mounted) return;
    }
    if (!onboardingCompleted) {
      context.navigate('/onboarding');
      return;
    }

    final updateController = myController;
    unawaited(
      runStartupUpdateCheck(
        isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
        checkForUpdate: () async {
          await updateController.checkUpdate(type: 'auto');
        },
      ),
    );
    _startDefaultPage();
  }

  void _setupBackgroundDownloadNavigation() {
    final backgroundService = BackgroundDownloadService();

    backgroundService.onNavigateToDownloadRequested = () {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final navigationContext = rootNavigatorKey.currentContext;
          if (navigationContext == null || !navigationContext.mounted) return;
          final path = navigationContext.routeState(listen: false).uri.path;
          if (path.contains('/download')) return;
          navigationContext.pushNamed('/settings/download/');
        } catch (e) {
          KazumiLogger().w(
            'InitPage: failed to navigate to download page',
            error: e,
          );
        }
      });
    };

    backgroundService.onNotificationPermissionRequired = () async {
      final result = await KazumiDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) {
          return PlayraDialog(
            title: const Text('需要通知权限'),
            content: const Text(
              '开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n'
              '如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。',
            ),
            actions: [
              PlayraButton.ghost(
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: Text(
                  '稍后再说',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              PlayraButton.ghost(
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: const Text('允许'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    };
  }

  void _startDefaultPage() {
    final defaultStartupPage = GStorage.getSetting(
      SettingsKeys.defaultStartupPage,
    );
    if (!mounted) {
      return;
    }
    context.navigate(defaultStartupPage);
  }

  // migrate collect from old version (favorites)
  Future<void> _migrateStorage() async {
    await collectController.migrateCollect();
  }

  Future<void> _loadShaders() async {
    await shaderAssetService.copyShadersToExternalDirectory();
  }

  Future<void> _webDavInit() async {
    bool webDavEnable = await GStorage.getSetting(SettingsKeys.webDavEnable);
    bool webDavEnableHistory = await GStorage.getSetting(
      SettingsKeys.webDavEnableHistory,
    );
    if (webDavEnable) {
      var webDav = WebDav();
      KazumiLogger().i('WebDav: Starting WebDav initialization');
      try {
        await webDav.init();
        await widget.danmakuShieldSync.syncIfEnabled();
        if (webDavEnableHistory) {
          try {
            await webDav.syncHistory();
            KazumiLogger().i('WebDav: Completed syncing watch history');
          } catch (e, stackTrace) {
            KazumiLogger().w(
              'WebDav: automatic watch history sync failed',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'WebDav: automatic initialization failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: PlayraDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                '检测到您当前运行在X11环境下，Playra在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Playra？',
              ),
              actions: [
                PlayraButton.ghost(
                  onPressed: AppExit.quit,
                  child: Text(
                    '退出',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                PlayraButton.ghost(
                  onPressed: () {
                    KazumiDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await KazumiDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => PlayraDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 Playra 的快捷方式？'),
        actions: [
          PlayraButton.ghost(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: Text(
              '暂不创建',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          PlayraButton.ghost(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      KazumiDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  Future<void> _pluginInit() async {
    try {
      await pluginsController.init();
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'Plugin: failed to initialize rules',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return InterfacePageHost(
      legacy: (_) => Scaffold(body: Container()),
      modern: (_) => ModernSecondaryScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(PlayraSpace.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SecondaryArtwork(
                        asset: 'modern-onboarding-decoration',
                        width: 160,
                      ),
                      const SizedBox(height: PlayraSpace.lg),
                      Text(
                        'Playra',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: PlayraSpace.md),
                      const Text('正在准备你的观看空间'),
                      const SizedBox(height: PlayraSpace.xxl),
                      const SizedBox(width: 120, child: PlayraProgress()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
