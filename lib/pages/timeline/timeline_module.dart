import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/modern/pages/calendar_page.dart';

final timelineModule = createModule(
  path: '/timeline',
  register: (c) => c.route(
    '/',
    transition: TransitionType.none,
    child: (_, _) => const ModernCalendarPage(),
  ),
);
