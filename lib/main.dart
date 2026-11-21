import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:kazumi/shell/shell_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/platform/platform_io.dart';
import 'package:kazumi/services/platform/platform_paths.dart';
import 'package:kazumi/services/platform/platform_setup.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/device.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configurePlatformPaths();
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await initializePlatformFiles();
    await GStorage.init();
  } catch (error, stackTrace) {
    KazumiLogger().e(
      'Startup: storage initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(const _StartupFailureApp());
    return;
  }

  if (isDesktop()) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1280, 860),
        center: true,
        skipTaskbar: false,
        title: 'Playra',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  if (!kIsWeb && Platform.isWindows) {
    SystemProxyService.init();
  }
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();

  bootstrapMediaSources();
  unawaited(mediaSources.primary?.warmUp());

  // 播放器超分辨率着色器需要先落到应用数据目录。
  await ShaderAssetService().copyShadersToExternalDirectory();

  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [rootRouteObserver],
      defaultTransition: TransitionType.material,
      child: const AppWidget(),
    ),
  );
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '初始化失败',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      locale: const Locale('zh', 'CN'),
      theme: buildShellTheme(Brightness.dark),
      home: const Scaffold(
        body: SafeArea(
          child: PlayraPageState(
            icon: Icons.folder_off_outlined,
            title: '本地存储不可用',
            description: '请检查设备存储空间后重新打开 Playra。',
          ),
        ),
      ),
    );
  }
}
