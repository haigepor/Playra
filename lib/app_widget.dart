import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

class AppWidget extends StatelessWidget {
  const AppWidget({super.key});

  static final ThemeData _lightTheme = buildShellTheme(Brightness.light);
  static final ThemeData _darkTheme = buildShellTheme(Brightness.dark);

  ThemeMode get _themeMode => switch (GStorage.getSetting(
    SettingsKeys.themeMode,
  )) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: GStorage.settings.listenable(
        keys: [SettingsKeys.themeMode.name],
      ),
      builder: (context, box, child) {
        return MaterialApp.router(
          title: AppBrand.name,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _themeMode,
          themeAnimationDuration: Duration.zero,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          routerConfig: ModularApp.routerConfigOf(context),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: const [
            Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
              countryCode: 'CN',
            ),
          ],
          locale: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
        );
      },
    );
  }
}
