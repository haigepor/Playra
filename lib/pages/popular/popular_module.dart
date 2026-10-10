import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/pages/discover_page.dart';

final popularModule = createModule(
  path: '/popular',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => InterfacePageHost(
        legacy: (_) => PopularPage(controller: inject<PopularController>()),
        modern: (_) => const ModernDiscoverPage(),
      ),
    );
  },
);
