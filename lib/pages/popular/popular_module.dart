import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/modern/pages/discover_page.dart';

final popularModule = createModule(
  path: '/popular',
  register: (c) => c.route(
    '/',
    transition: TransitionType.none,
    child: (_, _) => const ModernDiscoverPage(),
  ),
);
