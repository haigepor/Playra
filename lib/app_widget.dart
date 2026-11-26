import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/features/sources/clicli/clicli_maintenance_trigger.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

class AppWidget extends StatefulWidget {
  const AppWidget({super.key});

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  final CliCliMaintenanceTrigger _maintenance = CliCliMaintenanceTrigger();

  static final ThemeData _lightTheme = buildShellTheme(Brightness.light);
  static final ThemeData _darkTheme = buildShellTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    // Runs once on launch and again on every return to foreground, so a user who
    // opens the app on any given day collects that day's coins. No background
    // execution: if the app is never opened, nothing is collected.
    _maintenance.attach();
  }

  @override
  void dispose() {
    _maintenance.detach();
    super.dispose();
  }

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
