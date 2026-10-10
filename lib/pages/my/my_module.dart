import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/my/my_page.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/pages/profile_page.dart';

final myModule = createModule(
  path: '/my',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => InterfacePageHost(
        legacy: (_) => MyPage(controller: inject<MyController>()),
        modern: (_) => const ModernProfilePage(),
      ),
    );
  },
);
