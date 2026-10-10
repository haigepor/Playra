import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_page.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/pages/library_page.dart';

final collectModule = createModule(
  path: '/collect',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => InterfacePageHost(
        legacy: (_) => CollectPage(controller: inject<CollectController>()),
        modern: (_) =>
            ModernLibraryPage(controller: inject<CollectController>()),
      ),
    );
  },
);
