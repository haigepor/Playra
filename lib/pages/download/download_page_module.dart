import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/download/download_page.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

final downloadModule = createModule(
  path: '/download',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => SettingsAppearanceHost(
        child: DownloadPage(controller: inject<DownloadController>()),
      ),
    );
  },
);
