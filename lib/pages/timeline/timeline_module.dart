import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';

final timelineModule = createModule(
  path: '/timeline',
  register: (c) => c.route(
    '/',
    transition: TransitionType.none,
    child: (_, _) => const SourceUnavailablePage(feature: '放送日历'),
  ),
);
