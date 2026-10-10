import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'app_module.dart';
import 'app_widget.dart';
import 'bean/dialog/dialog_helper.dart';
import 'bean/settings/theme_provider.dart';
import 'navigation.dart';
import 'presentation/interface_style.dart';
import 'services/platform/platform_paths.dart';
import 'services/platform/platform_setup.dart';
import 'services/storage/storage.dart';

/// 仅供开发验收的安卓首页浏览器入口，正常 main.dart 的平台限制保持不变。
/// 独立端口隔离浏览器存储，业务路由、接口和仓库与主应用共用。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configurePlatformPaths();
  MediaKit.ensureInitialized();
  final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
  await Hive.initFlutter(hivePath);
  await initializePlatformFiles();
  await GStorage.init();
  runApp(
    ModularApp(
      module: appModule,
      initialRoute: '/tab/popular/',
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
        scoped.addChangeNotifier<InterfaceStyleController>(
          () => InterfaceStyleController(
            supportsModern: true,
            savedStyle: 'modern',
            writeStyle: (value) =>
                GStorage.putSetting(SettingsKeys.androidUiStyle, value),
          ),
        );
      },
      child: const AppWidget(),
    ),
  );
}
