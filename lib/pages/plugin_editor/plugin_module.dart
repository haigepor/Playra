import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';

final pluginModule = createModule(
  path: '/plugin',
  register: (c) {
    for (final path in ['/', '/shop', '/test', '/editor']) {
      c.route(
        path,
        child: (_, _) => const SourceUnavailablePage(feature: '站点规则'),
      );
    }
  },
);
