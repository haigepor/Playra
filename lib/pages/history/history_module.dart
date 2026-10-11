import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/history/history_page.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

final historyModule = createModule(
  path: '/history',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => SettingsAppearanceHost(
        child: HistoryPage(controller: inject<HistoryController>()),
      ),
    );
  },
);
